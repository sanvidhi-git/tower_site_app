import 'dart:async';

import '../core/api.dart';
import '../core/store.dart';

/// Calls into `tower_site_execution.mobile_api` on the ERPNext server.
/// Read calls cache their last good answer so the forms keep working offline.
class SiteApi {
  SiteApi._();

  static const _m = 'tower_site_execution.mobile_api';
  static ApiClient get _api => ApiClient.instance;

  static Future<Map<String, dynamic>> ping() async => Map<String, dynamic>.from(await _api.get('$_m.ping'));

  static Future<Map<String, dynamic>> login(String usr, String pwd) async =>
      Map<String, dynamic>.from(await _api.post('$_m.login', {'usr': usr, 'pwd': pwd}));

  static Future<Map<String, dynamic>> bootstrap() => _cached('bootstrap', () => _api.get('$_m.bootstrap'));

  static Future<Map<String, dynamic>> siteDetail(String site) =>
      _cached('site_${_safe(site)}', () => _api.get('$_m.site_detail', {'site': site}));

  static Future<List<Map<String, dynamic>>> poItems(String po) async {
    final r = await _cachedAny('po_${_safe(po)}', () => _api.get('$_m.get_po_pending_items', {'purchase_order': po}));
    return _list(r);
  }

  static Future<List<Map<String, dynamic>>> searchItems(String txt) async {
    final r = await _cachedAny('items_${_safe(txt)}', () => _api.get('$_m.search_items', {'txt': txt, 'limit': 30}));
    return _list(r);
  }

  static Future<List<Map<String, dynamic>>> mySubmissions() async => _list(await _api.get('$_m.my_submissions'));

  static Future<Map<String, dynamic>> submission(String doctype, String name) =>
      _cached('sub_${_safe(name)}', () => _api.get('$_m.get_submission', {'doctype': doctype, 'name': name}));

  static String doctypeFor(Map<String, dynamic> row) =>
      (row['doctype'] as String?) ?? (row['kind'] == 'Daily Report' ? 'Daily Site Report' : 'Site Material Receipt');

  static Future<Map<String, dynamic>> submitDailyReport(Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api.post('$_m.submit_daily_report', {'payload': payload}));

  static Future<Map<String, dynamic>> submitMaterialReceipt(Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api.post('$_m.submit_material_receipt', {'payload': payload}));

  // ---------------------------------------------------------------- caching
  static Future<Map<String, dynamic>> _cached(String key, Future<dynamic> Function() fetch) async =>
      Map<String, dynamic>.from(await _cachedAny(key, fetch));

  /// Network first; on a network failure fall back to the last saved answer.
  static Future<dynamic> _cachedAny(String key, Future<dynamic> Function() fetch) async {
    try {
      final r = await fetch();
      unawaited(JsonStore.write('cache_$key', r)); // save for offline use without delaying the screen
      return r;
    } on ApiException catch (e) {
      if (!e.isNetworkError) rethrow;
      final c = await JsonStore.read('cache_$key');
      if (c == null) rethrow;
      return c;
    }
  }

  static List<Map<String, dynamic>> _list(dynamic r) =>
      (r as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}
