import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Error raised for any failed Frappe call, with the server's message
/// already extracted so screens can show it as-is.
class ApiException implements Exception {
  ApiException(this.message, {this.title = 'Something went wrong', this.status});

  final String title;
  final String message;
  final int? status;

  bool get isAuthError => status == 401;
  bool get isNetworkError => status == null;

  @override
  String toString() => message;
}

/// Thin wrapper around Dio for Frappe's `/api/method/<dotted.path>` endpoints.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 90),
    headers: {'Accept': 'application/json'},
  ));

  String? _baseUrl;
  String? _authHeader;

  /// Called when any request comes back 401 (secret rotated / user disabled).
  void Function()? onUnauthorized;

  String? get baseUrl => _baseUrl;

  /// Headers for loading private files (photos) with the same login as the API.
  Map<String, String> get authHeaders => {if (_authHeader != null) 'Authorization': _authHeader!};

  /// Absolute URL for a server path such as /private/files/x.jpg.
  String fileUrl(String path) => path.startsWith('http') ? path : '${_baseUrl ?? ''}$path';

  /// Test hook: lets the screenshot harness swap in a fake HTTP adapter.
  @visibleForTesting
  Dio get dio => _dio;

  void configure({required String baseUrl, String? apiKey, String? apiSecret}) {
    _baseUrl = normalizeUrl(baseUrl);
    _authHeader = (apiKey != null && apiSecret != null) ? 'token $apiKey:$apiSecret' : null;
  }

  static String normalizeUrl(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Options _options({ResponseType? responseType}) => Options(
        headers: {if (_authHeader != null) 'Authorization': _authHeader},
        responseType: responseType,
        contentType: Headers.jsonContentType,
      );

  String _url(String method) {
    if (_baseUrl == null) throw ApiException('Server address is not set', title: 'Setup');
    return '$_baseUrl/api/method/$method';
  }

  Future<dynamic> get(String method, [Map<String, dynamic>? params]) async {
    try {
      final r = await _dio.get(_url(method), queryParameters: _clean(params), options: _options());
      return _unwrap(r);
    } on DioException catch (e) {
      throw _convert(e);
    }
  }

  Future<dynamic> post(String method, [Map<String, dynamic>? data]) async {
    try {
      final r = await _dio.post(_url(method), data: jsonEncode(_clean(data) ?? {}), options: _options());
      return _unwrap(r);
    } on DioException catch (e) {
      throw _convert(e);
    }
  }

  Future<List<int>> download(String method, Map<String, dynamic> params) async {
    try {
      final r = await _dio.get<List<int>>(_url(method),
          queryParameters: _clean(params), options: _options(responseType: ResponseType.bytes));
      return r.data ?? <int>[];
    } on DioException catch (e) {
      throw _convert(e);
    }
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? m) =>
      m == null ? null : (Map.of(m)..removeWhere((_, v) => v == null));

  dynamic _unwrap(Response r) {
    final d = r.data;
    if (d is Map && d.containsKey('message')) return d['message'];
    return d;
  }

  ApiException _convert(DioException e) {
    final status = e.response?.statusCode;
    if (e.response == null) {
      final msg = switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout =>
          'The server took too long to respond. Check your connection and try again.',
        DioExceptionType.badCertificate => 'The server certificate is not trusted.',
        _ => 'Cannot reach the server. Check your internet connection.',
      };
      return ApiException(msg, title: 'Network');
    }
    if (status == 401) onUnauthorized?.call();

    var title = status == 401 ? 'Signed out' : 'Not allowed';
    String? message;
    var data = e.response?.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {}
    }
    if (data is Map) {
      final sm = data['_server_messages'];
      if (sm is String) {
        try {
          for (final item in (jsonDecode(sm) as List)) {
            final m = item is String ? jsonDecode(item) : item;
            if (m is Map && m['message'] != null) {
              message = _stripHtml(m['message'].toString());
              if (m['title'] != null && m['title'].toString().isNotEmpty) title = m['title'].toString();
            }
          }
        } catch (_) {}
      }
      if (message == null && data['message'] is String) message = data['message'] as String;
      if (message == null && data['exception'] is String) {
        final ex = data['exception'] as String;
        message = ex.contains(':') ? ex.substring(ex.indexOf(':') + 1).trim() : ex;
      }
    }
    message ??= switch (status) {
      401 => 'Your session has expired. Please sign in again.',
      403 => 'You do not have permission for this action.',
      404 => 'Not found on the server. Is the tower_site_execution app installed?',
      413 => 'The upload is too large.',
      _ => 'Server error ($status).',
    };
    return ApiException(message, title: title, status: status);
  }

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<br\s*/?>'), '\n').replaceAll(RegExp(r'<[^>]*>'), '').trim();
}
