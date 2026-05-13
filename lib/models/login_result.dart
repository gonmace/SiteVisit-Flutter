sealed class LoginResult {}

class LoginSuccess extends LoginResult {
  final String accessToken;
  final String refreshToken;
  final int userId;
  final String role;
  final String company;
  final String email;

  LoginSuccess({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.role,
    required this.company,
    required this.email,
  });
}

class LoginDeviceNotRegistered extends LoginResult {
  final int userId;
  final String email;
  final String password;

  LoginDeviceNotRegistered({
    required this.userId,
    required this.email,
    required this.password,
  });
}

class LoginPendingApproval extends LoginResult {
  final int userId;
  LoginPendingApproval({this.userId = 0});
}

class LoginDeviceUnauthorized extends LoginResult {}

class LoginError extends LoginResult {
  final String message;
  LoginError(this.message);
}
