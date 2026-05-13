import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/login_result.dart';
import '../models/technician_search_result.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/secure_storage_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated, pendingApproval }

class AuthRepository extends ChangeNotifier {
  final AuthService _authService;
  final SecureStorageService _storage;
  final DeviceService _deviceService;

  AuthStatus _status = AuthStatus.unknown;
  UserModel? _currentUser;
  String _pendingEmail = '';
  String _pendingPassword = '';
  int _pendingUserId = 0;

  AuthRepository({
    required AuthService authService,
    required SecureStorageService storage,
    required DeviceService deviceService,
  })  : _authService = authService,
        _storage = storage,
        _deviceService = deviceService;

  AuthStatus get status => _status;
  UserModel? get currentUser => _currentUser;
  bool get isPendingApproval => _status == AuthStatus.pendingApproval;

  Future<void> initialize() async {
    try {
      final token = await _storage.getAccessToken();
      if (token != null) {
        final results = await Future.wait([
          _storage.getUserId().then((v) => v?.toString() ?? '0'),
          _storage.getUserRole()    .then((v) => v ?? ''),
          _storage.getUserCompany() .then((v) => v ?? ''),
          _storage.getUserEmail()   .then((v) => v ?? ''),
          _storage.getFirstName()   .then((v) => v ?? ''),
          _storage.getLastName()    .then((v) => v ?? ''),
          _storage.getCargo()       .then((v) => v ?? ''),
          _storage.getPhone()       .then((v) => v ?? ''),
          _storage.getRut()         .then((v) => v ?? ''),
          _storage.getPhotoUrl()    .then((v) => v?.isNotEmpty == true ? v : null),
        ]);
        _currentUser = UserModel(
          id:        int.tryParse(results[0] as String) ?? 0,
          email:     results[3] as String,
          role:      results[1] as String,
          company:   results[2] as String,
          firstName: results[4] as String,
          lastName:  results[5] as String,
          cargo:     results[6] as String,
          phone:     results[7] as String,
          rut:       results[8] as String,
          photoUrl:  results[9] as String?,
        );
        _status = AuthStatus.authenticated;
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<LoginResult> login(String email, String password) async {
    try {
      final fingerprint = await _deviceService.getFingerprint();
      final result = await _authService.login(email, password, fingerprint);

      if (result is LoginSuccess) {
        await _storage.saveAuthTokens(
          accessToken:  result.accessToken,
          refreshToken: result.refreshToken,
          userId:       result.userId,
          role:         result.role,
          company:      result.company,
          email:        result.email,
        );

        final profile = await _authService.getProfile();
        final firstName = profile?['first_name'] as String? ?? '';
        final lastName  = profile?['last_name']  as String? ?? '';
        final cargo     = profile?['cargo']       as String? ?? '';
        final phone     = profile?['phone']       as String? ?? '';
        final rut       = profile?['rut']         as String? ?? '';
        final photoUrl  = profile?['photo_url']   as String?;

        await _storage.saveProfile(
          firstName: firstName,
          lastName:  lastName,
          cargo:     cargo,
          phone:     phone,
          rut:       rut,
          photoUrl:  photoUrl,
        );

        _currentUser = UserModel(
          id:        result.userId,
          email:     result.email,
          role:      result.role,
          company:   result.company,
          firstName: firstName,
          lastName:  lastName,
          cargo:     cargo,
          phone:     phone,
          rut:       rut,
          photoUrl:  photoUrl,
        );
        _status = AuthStatus.authenticated;
        _pendingEmail = '';
        _pendingPassword = '';
        notifyListeners();
      }

      return result;
    } on TimeoutException {
      return LoginError('El servidor no responde. Verifica tu conexión e intenta nuevamente.');
    } catch (_) {
      return LoginError('No se pudo conectar al servidor. Verifica tu conexión.');
    }
  }

  void setPendingApproval(String email, String password, int userId) {
    _pendingEmail = email;
    _pendingPassword = password;
    _pendingUserId = userId;
    _status = AuthStatus.pendingApproval;
    notifyListeners();
  }

  Future<LoginResult> retryLogin() async {
    if (_pendingEmail.isEmpty) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return LoginError('Debes iniciar sesión nuevamente');
    }
    return login(_pendingEmail, _pendingPassword);
  }

  String get pendingEmail => _pendingEmail;

  Future<String?> register({
    required String email,
    required String password,
    required String company,
    String firstName = '',
    String lastName = '',
    String cargo = '',
    String phone = '',
    String rut = '',
  }) async {
    final data = await _authService.register(
      email: email,
      password: password,
      company: company,
      firstName: firstName,
      lastName: lastName,
      cargo: cargo,
      phone: phone,
      rut: rut,
    );
    if (data.containsKey('email')) return null;
    return _extractFirstError(data);
  }

  Future<List<TechnicianSearchResult>> searchTechnicians(String query) {
    return _authService.searchTechnicians(query);
  }

  Future<TechnicianSearchResult?> lookupByEmail(String email) {
    return _authService.lookupTechnicianByEmail(email);
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
  }) {
    return _authService.claimTechnician(
      userId:    userId,
      password:  password,
      company:   company,
      rut:       rut,
      firstName: firstName,
      lastName:  lastName,
      phone:     phone,
      cargo:     cargo,
    );
  }

  String? _extractFirstError(Map<String, dynamic> data) {
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is List && value.isNotEmpty) return '${entry.key}: ${value.first}';
      if (value is String && value.isNotEmpty) return value;
    }
    return 'Error al registrar';
  }

  Future<bool> activate(LoginDeviceNotRegistered info, String imagePath) async {
    final fingerprint = await _deviceService.getFingerprint();
    final deviceInfo  = await _deviceService.getDeviceInfo();
    final identifiers = await _deviceService.getDeviceIdentifiers();
    return _authService.activate(
      userId:            info.userId,
      email:             info.email,
      password:          info.password,
      deviceFingerprint: fingerprint,
      manufacturer:      deviceInfo['manufacturer'] ?? '',
      model:             deviceInfo['model'] ?? '',
      osVersion:         deviceInfo['os_version'] ?? '',
      imagePath:         imagePath,
      androidId:         identifiers['android_id'] ?? '',
    );
  }

  Future<void> logout() async {
    await _storage.clearAll();
    _currentUser = null;
    _status = AuthStatus.unauthenticated;
    _pendingEmail = '';
    _pendingPassword = '';
    notifyListeners();
  }
}
