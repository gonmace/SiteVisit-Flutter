import 'dart:convert';
import '../config/constants.dart';
import '../models/login_result.dart';
import '../models/technician_search_result.dart';
import 'api_client.dart';

class AuthService {
  final ApiClient _client;
  AuthService({required ApiClient client}) : _client = client;

  // DRF wraps exception detail values in ErrorDetail (str subclass), so int fields
  // like user_id arrive as strings in 401/403 error responses.
  static int? _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  Future<LoginResult> login(String email, String password, String fingerprint) async {
    final resp = await _client.post(
      Constants.tokenPath,
      {'email': email, 'password': password, 'device_fingerprint': fingerprint},
      auth: false,
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;

    if (resp.statusCode == 200) {
      return LoginSuccess(
        accessToken:  body['access']  as String,
        refreshToken: body['refresh'] as String,
        userId:       _parseInt(body['user_id']) ?? 0,
        role:         body['role']    as String,
        company:      body['company'] as String,
        email:        email,
      );
    }

    if (resp.statusCode == 401) {
      final userId = _parseInt(body['user_id']);
      if (userId != null) {
        return LoginDeviceNotRegistered(userId: userId, email: email, password: password);
      }
      return LoginError(body['detail']?.toString() ?? 'Credenciales incorrectas');
    }

    if (resp.statusCode == 403) {
      final detail = body['detail']?.toString() ?? '';
      if (detail == 'pending_manager_approval') {
        return LoginPendingApproval(userId: _parseInt(body['user_id']) ?? 0);
      }
      if (detail == 'device_unauthorized') return LoginDeviceUnauthorized();
    }

    return LoginError('Error ${resp.statusCode}');
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String company,
    String firstName = '',
    String lastName = '',
    String cargo = '',
    String phone = '',
    String rut = '',
  }) async {
    final resp = await _client.post(
      Constants.publicRegisterPath,
      {
        'email': email,
        'password': password,
        'company': company,
        'first_name': firstName,
        'last_name': lastName,
        'cargo': cargo,
        'phone': phone,
        'rut': rut,
      },
      auth: false,
    );
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<TechnicianSearchResult>> searchTechnicians(String query) async {
    final resp = await _client.get(
      '${Constants.usersPath}search-technicians/?q=${Uri.encodeComponent(query)}',
      auth: false,
    );
    final list = jsonDecode(resp.body) as List<dynamic>;
    return list.map((j) => TechnicianSearchResult.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<TechnicianSearchResult?> lookupTechnicianByEmail(String email) async {
    final resp = await _client.get(
      '${Constants.usersPath}search-technicians/?email=${Uri.encodeComponent(email)}',
      auth: false,
    );
    if (resp.statusCode != 200) return null;
    final list = jsonDecode(resp.body) as List<dynamic>;
    if (list.isEmpty) return null;
    return TechnicianSearchResult.fromJson(list.first as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> claimTechnician({
    required int userId,
    required String password,
    String company = '',
    String rut = '',
    String firstName = '',
    String lastName = '',
    String phone = '',
    String cargo = '',
  }) async {
    final resp = await _client.post(
      '${Constants.usersPath}$userId/claim/',
      {
        'password':   password,
        'company':    company,
        'rut':        rut,
        'first_name': firstName,
        'last_name':  lastName,
        'phone':      phone,
        'cargo':      cargo,
      },
      auth: false,
    );

    Map<String, dynamic> body;
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Error ${resp.statusCode}: respuesta inesperada del servidor');
    }

    if (resp.statusCode >= 400) {
      throw Exception(_parseBodyError(body));
    }

    return body;
  }

  static String _parseBodyError(Map<String, dynamic> data) {
    if (data['detail'] != null) return data['detail'].toString();
    final buf = StringBuffer();
    for (final entry in data.entries) {
      final v = entry.value;
      if (v is List && v.isNotEmpty) {
        buf.writeln('${entry.key}: ${v.first}');
      } else if (v is String && v.isNotEmpty) {
        buf.writeln('${entry.key}: $v');
      }
    }
    final msg = buf.toString().trim();
    return msg.isNotEmpty ? msg : 'Error del servidor';
  }

  Future<Map<String, dynamic>?> getProfile() async {
    final resp = await _client.get('${Constants.usersPath}me/');
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    return null;
  }

  Future<bool> activate({
    required int userId,
    required String email,
    required String password,
    required String deviceFingerprint,
    required String manufacturer,
    required String model,
    required String osVersion,
    required String imagePath,
    String androidId = '',
  }) async {
    final resp = await _client.multipart(
      '${Constants.usersPath}$userId/activate/',
      {
        'email':              email,
        'password':           password,
        'device_fingerprint': deviceFingerprint,
        'manufacturer':       manufacturer,
        'model':              model,
        'os_version':         osVersion,
        'android_id':         androidId,
      },
      {'image': imagePath},
      auth: false,
    );
    return resp.statusCode == 202;
  }
}
