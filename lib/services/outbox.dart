import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../core/store.dart';
import 'site_api.dart';

enum OutboxKind { dailyReport, materialReceipt }

/// A report captured on the phone and not yet accepted by the server.
class OutboxItem {
  OutboxItem({
    required this.ref,
    required this.kind,
    required this.site,
    required this.title,
    required this.created,
    required this.payload,
    this.error,
    this.attempts = 0,
  });

  /// Also sent to the server as `mobile_ref`, so a retry never creates a duplicate.
  final String ref;
  final OutboxKind kind;
  final String site;
  final String title;
  final DateTime created;
  final Map<String, dynamic> payload;
  String? error;
  int attempts;

  String get kindLabel => kind == OutboxKind.dailyReport ? 'Daily Report' : 'Material Receipt';

  Map<String, dynamic> toJson() => {
        'ref': ref,
        'kind': kind.name,
        'site': site,
        'title': title,
        'created': created.toIso8601String(),
        'payload': payload,
        'error': error,
        'attempts': attempts,
      };

  factory OutboxItem.fromJson(Map<String, dynamic> j) => OutboxItem(
        ref: j['ref'] as String,
        kind: OutboxKind.values.byName(j['kind'] as String),
        site: j['site'] as String,
        title: j['title'] as String? ?? '',
        created: DateTime.parse(j['created'] as String),
        payload: Map<String, dynamic>.from(j['payload'] as Map),
        error: j['error'] as String?,
        attempts: j['attempts'] as int? ?? 0,
      );

  /// Every local photo path referenced by this item.
  List<String> get photoPaths {
    final out = <String>[];
    for (final p in (payload['photos'] as List? ?? [])) {
      if (p is Map && p['path'] != null) out.add(p['path'] as String);
    }
    for (final e in (payload['expenses'] as List? ?? [])) {
      if (e is Map && e['bill_path'] != null) out.add(e['bill_path'] as String);
    }
    return out;
  }
}

/// Result of [Outbox.submit]: either accepted by the server now, or queued for later.
class SubmitResult {
  SubmitResult.sent(this.serverName) : queued = false, error = null;
  SubmitResult.queued(this.error) : queued = true, serverName = null;

  final bool queued;
  final String? serverName;
  final String? error;
}

/// Store-and-forward queue. Everything is written to disk first, then sent; failures stay
/// in the queue and are retried on app start, pull-to-refresh, the Sync button and every 2 minutes.
class Outbox extends ChangeNotifier {
  Outbox._();
  static final Outbox instance = Outbox._();
  static const _key = 'outbox';

  final List<OutboxItem> _items = [];
  bool syncing = false;
  DateTime? lastSync;
  Timer? _timer;

  List<OutboxItem> get pending => List.unmodifiable(_items);

  Future<void> load() async {
    final raw = await JsonStore.read(_key);
    _items
      ..clear()
      ..addAll((raw as List? ?? []).map((e) => OutboxItem.fromJson(Map<String, dynamic>.from(e as Map))));
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_items.isNotEmpty) sync();
    });
    notifyListeners();
  }

  Future<void> _save() => JsonStore.write(_key, _items.map((e) => e.toJson()).toList());

  static String newRef() => const Uuid().v4();

  /// Copies a picked photo into app storage so it survives until it is uploaded.
  static Future<String> keepPhoto(String path) async {
    final dir = await JsonStore.photoDir();
    final dest = '${dir.path}/${const Uuid().v4()}.jpg';
    await File(path).copy(dest);
    return dest;
  }

  /// Saves the report to the outbox and tries to send it straight away.
  Future<SubmitResult> submit(OutboxKind kind, String site, String title, Map<String, dynamic> payload) async {
    final ref = (payload['mobile_ref'] as String?) ?? newRef();
    payload['mobile_ref'] = ref;
    final item = OutboxItem(ref: ref, kind: kind, site: site, title: title, created: DateTime.now(), payload: payload);
    _items.add(item);
    await _save();
    notifyListeners();
    try {
      final name = await _send(item);
      await _remove(item);
      return SubmitResult.sent(name);
    } on ApiException catch (e) {
      item.attempts++;
      item.error = e.isNetworkError ? null : e.message;
      await _save();
      notifyListeners();
      return SubmitResult.queued(e.isNetworkError ? null : e.message);
    }
  }

  /// Sends everything waiting. Stops at the first network failure (still offline).
  Future<int> sync() async {
    if (syncing || _items.isEmpty) return 0;
    syncing = true;
    notifyListeners();
    var sent = 0;
    try {
      for (final item in List.of(_items)) {
        try {
          await _send(item);
          await _remove(item);
          sent++;
        } on ApiException catch (e) {
          item.attempts++;
          if (e.isNetworkError) {
            item.error = null;
            break;
          }
          item.error = e.message; // server rejected it: keep it so the user can see why
        }
      }
    } finally {
      syncing = false;
      lastSync = DateTime.now();
      await _save();
      notifyListeners();
    }
    return sent;
  }

  Future<void> discard(OutboxItem item) => _remove(item);

  /// Test hook: shows an item as waiting without touching disk or network.
  @visibleForTesting
  void debugAdd(OutboxItem item) {
    _items.add(item);
    notifyListeners();
  }

  Future<void> clear() async {
    for (final i in List.of(_items)) {
      await _remove(i);
    }
  }

  Future<void> _remove(OutboxItem item) async {
    for (final p in item.photoPaths) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
    _items.removeWhere((e) => e.ref == item.ref);
    await _save();
    notifyListeners();
  }

  Future<String> _send(OutboxItem item) async {
    final body = await _withImages(item.payload);
    final r = item.kind == OutboxKind.dailyReport
        ? await SiteApi.submitDailyReport(body)
        : await SiteApi.submitMaterialReceipt(body);
    return r['name'] as String;
  }

  /// Replaces local photo paths with base64 JPEG data just before sending.
  static Future<Map<String, dynamic>> _withImages(Map<String, dynamic> payload) async {
    Future<String?> b64(String? path) async {
      if (path == null) return null;
      final f = File(path);
      if (!await f.exists()) return null;
      return base64Encode(await f.readAsBytes());
    }

    final body = Map<String, dynamic>.from(jsonDecode(jsonEncode(payload)) as Map);
    final photos = <Map<String, dynamic>>[];
    for (final p in (body['photos'] as List? ?? [])) {
      final m = Map<String, dynamic>.from(p as Map);
      final data = await b64(m.remove('path') as String?);
      if (data != null) photos.add({...m, 'image': data});
    }
    body['photos'] = photos;
    if (body['expenses'] is List) {
      body['expenses'] = [
        for (final e in body['expenses'] as List)
          {
            ...Map<String, dynamic>.from(e as Map)..remove('bill_path'),
            'bill_image': await b64((e)['bill_path'] as String?),
          }
      ];
    }
    return body;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
