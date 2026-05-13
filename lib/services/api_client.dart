import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import 'secure_storage_service.dart';

class ApiClient {
  final SecureStorageService _storage;

  VoidCallback? onAuthFailed;

  ApiClient({required SecureStorageService storage}) : _storage = storage;

  static const _timeout = Duration(seconds: 15);

  Future<http.Response> get(String path, {bool retry = true, bool auth = true}) async {
    final headers = auth ? await _authHeaders() : <String, String>{};
    final resp = await http
        .get(Uri.parse('${Constants.baseUrl}$path'), headers: headers)
        .timeout(_timeout);
    if (resp.statusCode == 401 && retry && auth && await _refreshTokens()) {
      return get(path, retry: false);
    }
    return resp;
  }

  Future<http.Response> post(
    String path,
    Map<String, dynamic> body, {
    bool retry = true,
    bool auth = true,
  }) async {
    final headers = auth ? await _authHeaders() : {'Content-Type': 'application/json'};
    final resp = await http
        .post(
          Uri.parse('${Constants.baseUrl}$path'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (resp.statusCode == 401 && retry && auth && await _refreshTokens()) {
      return post(path, body, retry: false);
    }
    return resp;
  }

  Future<http.Response> patch(
    String path,
    Map<String, dynamic> body, {
    bool retry = true,
  }) async {
    final headers = await _authHeaders();
    final resp = await http
        .patch(
          Uri.parse('${Constants.baseUrl}$path'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (resp.statusCode == 401 && retry && await _refreshTokens()) {
      return patch(path, body, retry: false);
    }
    return resp;
  }

  Future<http.Response> multipart(
    String path,
    Map<String, String> fields,
    Map<String, String> filePaths, {
    bool auth = true,
  }) async {
    final token = auth ? await _storage.getAccessToken() : null;
    final request = http.MultipartRequest('POST', Uri.parse('${Constants.baseUrl}$path'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields.addAll(fields);
    for (final e in filePaths.entries) {
      request.files.add(await http.MultipartFile.fromPath(e.key, e.value));
    }
    final streamed = await request.send().timeout(_timeout);
    return http.Response.fromStream(streamed);
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await _storage.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<bool> _refreshTokens() async {
    final refresh = await _storage.getRefreshToken();
    if (refresh == null) return false;
    final resp = await http
        .post(
          Uri.parse('${Constants.baseUrl}${Constants.tokenRefreshPath}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh': refresh}),
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      await _storage.clearAll();
      onAuthFailed?.call();
      return false;
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final userId  = await _storage.getUserId();
    final role    = await _storage.getUserRole();
    final company = await _storage.getUserCompany();
    final email   = await _storage.getUserEmail();
    await _storage.saveAuthTokens(
      accessToken:  data['access'] as String,
      refreshToken: data['refresh'] as String? ?? refresh,
      userId:       userId ?? 0,
      role:         role ?? '',
      company:      company ?? '',
      email:        email ?? '',
    );
    return true;
  }
}
