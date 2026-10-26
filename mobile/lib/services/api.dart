import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'mock_backend.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// HTTP client yar oo token-ka ku dara codsi kasta.
///
/// Marka AppConfig.useMock uu yahay true, codsiyada waxaa loo diraa
/// MockBackend (telefoonka gudihiisa), halkii server laga diri lahaa.
class Api {
  Api._();
  static final Api instance = Api._();

  String? token;
  void Function()? onUnauthorized;

  Map<String, String> _query(Map<String, dynamic>? query) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null) q[k] = '$v';
    });
    return q;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = _query(query);
    final uri = Uri.parse('${AppConfig.apiUrl}$path').replace(queryParameters: q.isEmpty ? null : q);
    if (kReleaseMode && uri.scheme != 'https') {
      throw ApiException(0, 'Xiriirka server-ka release-ka waa inuu isticmaalaa HTTPS.');
    }
    return uri;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _mock(String method, String path, {Map<String, dynamic>? query, Object? body}) async {
    try {
      return await MockBackend.instance.handle(method, path, _query(query), body, token);
    } on ApiException catch (e) {
      if (e.status == 401 && token != null) onUnauthorized?.call();
      rethrow;
    }
  }

  Future<dynamic> _send(Future<http.Response> Function() fn, {Duration timeout = const Duration(seconds: 20)}) async {
    http.Response res;
    try {
      res = await fn().timeout(timeout);
    } on SocketException {
      throw ApiException(0, 'Internet ama server lama heli karo. Hubi xiriirka.');
    } on TimeoutException {
      throw ApiException(0, 'Server-ku wuu daahay. Mar kale isku day.');
    } on http.ClientException {
      throw ApiException(0, 'Server lama heli karo.');
    }
    dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    final msg = body is Map && body['error'] != null ? body['error'].toString() : 'Cillad (${res.statusCode})';
    throw ApiException(res.statusCode, msg);
  }

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) {
    if (AppConfig.useMock) return _mock('GET', path, query: query);
    return _send(() => http.get(_uri(path, query), headers: _headers));
  }

  Future<dynamic> post(String path, [Object? body, Duration? timeout]) {
    if (AppConfig.useMock) return _mock('POST', path, body: body ?? const <String, dynamic>{});
    return _send(
      () => http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})),
      timeout: timeout ?? const Duration(seconds: 20),
    );
  }

  Future<dynamic> put(String path, [Object? body]) {
    if (AppConfig.useMock) return _mock('PUT', path, body: body ?? const <String, dynamic>{});
    return _send(() => http.put(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));
  }

  Future<dynamic> delete(String path) {
    if (AppConfig.useMock) return _mock('DELETE', path);
    return _send(() => http.delete(_uri(path), headers: _headers));
  }
}
