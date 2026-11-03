import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/outbox.dart';
import '../services/site_api.dart';
import 'api.dart';
import 'store.dart';

const secureStorage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

/// Sign-in state plus the bootstrap payload (sites assigned to me, expense types, milestones...).
class Session extends ChangeNotifier {
  static const _kUrl = 'server_url';
  static const _kKey = 'api_key';
  static const _kSecret = 'api_secret';
  static const _kUser = 'user';

  /// Optional build-time default: flutter build apk --dart-define=SITE_SERVER=https://erp.example.com
  static const defaultServer = String.fromEnvironment('SITE_SERVER');

  String? serverUrl;
  String? user;
  bool ready = false;
  bool offline = false;
  Map<String, dynamic> _boot = {};

  bool get isLoggedIn => user != null && _boot.isNotEmpty;

  String get fullName => (_boot['full_name'] ?? user ?? '').toString();
  bool get isManager => _boot['is_manager'] == true;
  Map<String, dynamic>? get employee => _boot['employee'] == null ? null : Map<String, dynamic>.from(_boot['employee']);
  List<Map<String, dynamic>> get sites => _maps(_boot['sites']);
  List<String> get expenseTypes => List<String>.from(_boot['expense_types'] ?? const []);
  List<Map<String, dynamic>> get milestones => _maps(_boot['milestones']);
  List<String> get warehouses => List<String>.from(_boot['warehouses'] ?? const []);
  String? get centralStore => _boot['central_store'] as String?;

  /// Test hook: puts the session straight into a signed-in state with fixture data.
  @visibleForTesting
  void debugSignIn({required String user, required String server, required Map<String, dynamic> boot}) {
    this.user = user;
    serverUrl = server;
    _boot = boot;
    ready = true;
    notifyListeners();
  }

  static List<Map<String, dynamic>> _maps(dynamic v) =>
      (v as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> load() async {
    ApiClient.instance.onUnauthorized = _expire;
    serverUrl = await secureStorage.read(key: _kUrl) ?? (defaultServer.isEmpty ? null : defaultServer);
    final key = await secureStorage.read(key: _kKey);
    final secret = await secureStorage.read(key: _kSecret);
    user = await secureStorage.read(key: _kUser);
    if (serverUrl != null) ApiClient.instance.configure(baseUrl: serverUrl!, apiKey: key, apiSecret: secret);
    await Outbox.instance.load();
    if (user != null && key != null && secret != null) {
      try {
        await refresh(notify: false);
      } on ApiException catch (e) {
        if (e.isAuthError) await _clear();
      }
    }
    ready = true;
    notifyListeners();
    if (isLoggedIn) Outbox.instance.sync();
  }

  Future<void> login(String url, String usr, String pwd) async {
    ApiClient.instance.configure(baseUrl: url);
    final r = await SiteApi.login(usr.trim(), pwd);
    serverUrl = ApiClient.normalizeUrl(url);
    user = r['user'] as String;
    final key = r['api_key'] as String, secret = r['api_secret'] as String;
    await secureStorage.write(key: _kUrl, value: serverUrl);
    await secureStorage.write(key: _kKey, value: key);
    await secureStorage.write(key: _kSecret, value: secret);
    await secureStorage.write(key: _kUser, value: user);
    ApiClient.instance.configure(baseUrl: serverUrl!, apiKey: key, apiSecret: secret);
    _boot = Map<String, dynamic>.from(r['bootstrap'] as Map);
    await JsonStore.write('cache_bootstrap', _boot);
    offline = false;
    notifyListeners();
  }

  /// Reloads sites & masters. Falls back to the cached copy when there is no network.
  Future<void> refresh({bool notify = true}) async {
    try {
      _boot = await SiteApi.bootstrap();
      offline = false;
      // SiteApi returns the cache on network errors; detect that by trying a ping
      try {
        await SiteApi.ping();
      } on ApiException catch (e) {
        offline = e.isNetworkError;
      }
    } on ApiException catch (e) {
      if (!e.isNetworkError) rethrow;
      offline = true;
    }
    if (notify) notifyListeners();
  }

  Future<void> logout({bool force = false}) async {
    if (!force && Outbox.instance.pending.isNotEmpty) {
      throw ApiException(
          '${Outbox.instance.pending.length} report(s) are still waiting to be sent. Connect to the internet and sync first.',
          title: 'Unsent reports');
    }
    await Outbox.instance.clear();
    await JsonStore.clearAll();
    await _clear();
    notifyListeners();
  }

  void _expire() {
    if (user == null) return;
    _clear().then((_) => notifyListeners());
  }

  Future<void> _clear() async {
    await secureStorage.delete(key: _kKey);
    await secureStorage.delete(key: _kSecret);
    await secureStorage.delete(key: _kUser);
    user = null;
    _boot = {};
    if (serverUrl != null) ApiClient.instance.configure(baseUrl: serverUrl!);
  }
}
