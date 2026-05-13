class Constants {
  // Desarrollo local:
  //   Emulador Android         : http://10.0.2.2:8010
  //   Simulador iOS            : http://localhost:8010
  //   Dispositivo Android real : adb reverse tcp:8010 tcp:8010  → http://localhost:8010
  //   Dispositivo iOS real     : http://<IP-LAN-tu-máquina>:8010  (ej. 192.168.1.x)
  // En desarrollo usar:  --dart-define=API_BASE_URL=http://10.0.2.2:8010  (emulador)
  // En producción usar:  --dart-define=API_BASE_URL=https://sitevisit.btspti.com
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8010',
  );

  static const String tokenPath        = '/api/token/';
  static const String tokenRefreshPath = '/api/token/refresh/';
  static const String usersPath        = '/api/v1/users/';
  static const String sitesPath        = '/api/v1/sites/';
  static const String visitsPath       = '/api/v1/visits/';
  static const String dashboardPath    = '/api/v1/dashboard/';
  static const String themePath        = '/api/v1/theme/';
  static const String publicRegisterPath = '/api/v1/users/public-register/';

  static const String accessTokenKey  = 'sv_access_token';
  static const String refreshTokenKey = 'sv_refresh_token';
  static const String userIdKey       = 'sv_user_id';
  static const String userRoleKey     = 'sv_user_role';
  static const String userCompanyKey  = 'sv_user_company';
  static const String userEmailKey    = 'sv_user_email';
  static const String firstNameKey    = 'sv_first_name';
  static const String lastNameKey     = 'sv_last_name';
  static const String cargoKey        = 'sv_cargo';
  static const String phoneKey        = 'sv_phone';
  static const String rutKey          = 'sv_rut';
  static const String photoUrlKey     = 'sv_photo_url';
}
