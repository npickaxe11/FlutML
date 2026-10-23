/// Shared value objects / exceptions for authentication services.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Data returned when starting the Microsoft device-code flow.
class DeviceCodeStart {
  const DeviceCodeStart({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.interval,
    required this.expiresIn,
    required this.message,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int interval;
  final int expiresIn;
  final String message;
}

/// Metadata of an authlib-injector compatible skin server.
class AuthServerInfo {
  const AuthServerInfo({required this.apiRoot, required this.serverName});

  final String apiRoot;
  final String serverName;
}
