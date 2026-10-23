enum AccountType {
  offline('Offline'),
  msa('Microsoft'),
  authlib('Skin server');

  const AccountType(this.label);

  final String label;

  static AccountType fromName(String? name) =>
      AccountType.values.firstWhere(
        (e) => e.name == name,
        orElse: () => AccountType.offline,
      );
}

class Account {
  const Account({
    required this.username,
    required this.uuid,
    this.type = AccountType.offline,
    this.accessToken = '',
    this.refreshToken = '',
    this.expiresAtMs = 0,
    this.authServerUrl = '',
    this.authServerName = '',
  });

  final String username;
  final String uuid;
  final AccountType type;

  /// Microsoft / skin-station session token ('' for offline).
  final String accessToken;
  final String refreshToken;
  final int expiresAtMs;

  /// authlib-injector API root for third-party accounts.
  final String authServerUrl;
  final String authServerName;

  bool get isOffline => type == AccountType.offline;

  bool get tokenExpired {
    if (type == AccountType.offline) return false;
    if (expiresAtMs <= 0) return true;
    return DateTime.now().millisecondsSinceEpoch >= expiresAtMs - 300000;
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'uuid': uuid,
        'isOffline': isOffline,
        'type': type.name,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAtMs': expiresAtMs,
        'authServerUrl': authServerUrl,
        'authServerName': authServerName,
      };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        username: json['username'] as String? ?? '',
        uuid: json['uuid'] as String? ?? '',
        type: AccountType.fromName(json['type'] as String?),
        accessToken: json['accessToken'] as String? ?? '',
        refreshToken: json['refreshToken'] as String? ?? '',
        expiresAtMs: json['expiresAtMs'] as int? ?? 0,
        authServerUrl: json['authServerUrl'] as String? ?? '',
        authServerName: json['authServerName'] as String? ?? '',
      );

  Account copyWith({
    String? username,
    String? uuid,
    AccountType? type,
    String? accessToken,
    String? refreshToken,
    int? expiresAtMs,
    String? authServerUrl,
    String? authServerName,
  }) {
    return Account(
      username: username ?? this.username,
      uuid: uuid ?? this.uuid,
      type: type ?? this.type,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAtMs: expiresAtMs ?? this.expiresAtMs,
      authServerUrl: authServerUrl ?? this.authServerUrl,
      authServerName: authServerName ?? this.authServerName,
    );
  }
}
