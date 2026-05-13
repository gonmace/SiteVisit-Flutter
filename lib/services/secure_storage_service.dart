import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/constants.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  Future<String?> getAccessToken()  => _storage.read(key: Constants.accessTokenKey);
  Future<String?> getRefreshToken() => _storage.read(key: Constants.refreshTokenKey);
  Future<String?> getUserRole()     => _storage.read(key: Constants.userRoleKey);
  Future<String?> getUserCompany()  => _storage.read(key: Constants.userCompanyKey);
  Future<String?> getUserEmail()    => _storage.read(key: Constants.userEmailKey);
  Future<String?> getFirstName()    => _storage.read(key: Constants.firstNameKey);
  Future<String?> getLastName()     => _storage.read(key: Constants.lastNameKey);
  Future<String?> getCargo()        => _storage.read(key: Constants.cargoKey);
  Future<String?> getPhone()        => _storage.read(key: Constants.phoneKey);
  Future<String?> getRut()          => _storage.read(key: Constants.rutKey);
  Future<String?> getPhotoUrl()     => _storage.read(key: Constants.photoUrlKey);

  Future<int?> getUserId() async {
    final v = await _storage.read(key: Constants.userIdKey);
    return v != null ? int.tryParse(v) : null;
  }

  Future<void> saveAuthTokens({
    required String accessToken,
    required String refreshToken,
    required int userId,
    required String role,
    required String company,
    required String email,
  }) =>
      Future.wait([
        _storage.write(key: Constants.accessTokenKey,  value: accessToken),
        _storage.write(key: Constants.refreshTokenKey, value: refreshToken),
        _storage.write(key: Constants.userIdKey,       value: userId.toString()),
        _storage.write(key: Constants.userRoleKey,     value: role),
        _storage.write(key: Constants.userCompanyKey,  value: company),
        _storage.write(key: Constants.userEmailKey,    value: email),
      ]);

  Future<void> saveProfile({
    required String firstName,
    required String lastName,
    required String cargo,
    required String phone,
    required String rut,
    String? photoUrl,
  }) =>
      Future.wait([
        _storage.write(key: Constants.firstNameKey, value: firstName),
        _storage.write(key: Constants.lastNameKey,  value: lastName),
        _storage.write(key: Constants.cargoKey,     value: cargo),
        _storage.write(key: Constants.phoneKey,     value: phone),
        _storage.write(key: Constants.rutKey,       value: rut),
        _storage.write(key: Constants.photoUrlKey,  value: photoUrl ?? ''),
      ]);

  Future<void> clearAll() => _storage.deleteAll();
}
