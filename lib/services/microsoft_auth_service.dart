import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/account.dart';
import 'auth_models.dart';

/// Microsoft (Xbox / Minecraft services) authentication via the OAuth2
/// device-code flow, suitable for desktop launchers with a public client.
class MicrosoftAuthService {
  MicrosoftAuthService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const clientId = '1690fd82-6ca5-4711-9441-afacf06b4e73';
  static const _scope = 'XboxLive.signin offline_access';
  static const _deviceCodeUrl =
      'https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode';
  static const _tokenUrl =
      'https://login.microsoftonline.com/consumers/oauth2/v2.0/token';
  static const _xblUrl = 'https://user.auth.xboxlive.com/user/authenticate';
  static const _xstsUrl = 'https://xsts.auth.xboxlive.com/xsts/authorize';
  static const _mcAuthUrl =
      'https://api.minecraftservices.com/authentication/login_with_xbox';
  static const _profileUrl =
      'https://api.minecraftservices.com/minecraft/profile';

  /// Starts the device-code flow and returns what to show the user.
  Future<DeviceCodeStart> startDeviceCodeFlow() async {
    final response = await _client
        .post(
          Uri.parse(_deviceCodeUrl),
          body: {'client_id': clientId, 'scope': _scope},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw AuthException(
        'Microsoft device code request failed (${response.statusCode}): '
        '${_errorHint(response.body)}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return DeviceCodeStart(
      deviceCode: json['device_code'] as String,
      userCode: json['user_code'] as String,
      verificationUri: json['verification_uri'] as String? ??
          'https://www.microsoft.com/link',
      interval: json['interval'] as int? ?? 5,
      expiresIn: json['expires_in'] as int? ?? 900,
      message: json['message'] as String? ?? '',
    );
  }

  /// Polls until the user completes sign-in, then builds a full account.
  Future<Account> pollAndComplete(
    DeviceCodeStart start, {
    void Function(String status)? onStatus,
    Duration? timeout,
  }) async {
    final deadline =
        DateTime.now().add(timeout ?? Duration(seconds: start.expiresIn));
    var interval = Duration(seconds: start.interval.clamp(3, 15));

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
      final tokens = await _requestToken({
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        'client_id': clientId,
        'device_code': start.deviceCode,
      });
      if (tokens != null) {
        return _finishWithTokens(
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          expiresIn: tokens.expiresIn,
          onStatus: onStatus,
        );
      }
    }
    throw TimeoutException('Microsoft sign-in timed out');
  }

  /// Refreshes an expired MSA session; returns an updated account.
  Future<Account> refreshAccount(Account account) async {
    if (account.refreshToken.isEmpty) {
      throw const AuthException('No refresh token stored for this account');
    }
    final tokens = await _requestToken({
      'grant_type': 'refresh_token',
      'client_id': clientId,
      'refresh_token': account.refreshToken,
      'scope': _scope,
    });
    if (tokens == null) {
      throw const AuthException('Failed to refresh Microsoft session');
    }
    final fresh = await _finishWithTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresIn: tokens.expiresIn,
    );
    return fresh.copyWith(
      username:
          account.username.isNotEmpty ? account.username : fresh.username,
      uuid: account.uuid.isNotEmpty ? account.uuid : fresh.uuid,
    );
  }

  Future<_MsaTokens?> _requestToken(Map<String, String> body) async {
    final response = await _client
        .post(Uri.parse(_tokenUrl), body: body)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _MsaTokens(
        accessToken: json['access_token'] as String? ?? '',
        refreshToken: json['refresh_token'] as String? ?? '',
        expiresIn: json['expires_in'] as int? ?? 86400,
      );
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AuthException(
        'Microsoft token endpoint error (${response.statusCode})',
      );
    }
    final error = json['error'] as String?;
    if (error == 'authorization_pending' || error == 'slow_down') {
      return null;
    }
    throw AuthException(
      'Microsoft sign-in failed: $error ${json['error_description'] ?? ''}',
    );
  }

  Future<Account> _finishWithTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Authenticating with Xbox Live...');

    final xblResponse = await _postJson(
      _xblUrl,
      {
        'Properties': {
          'AuthMethod': 'RPS',
          'SiteName': 'user.auth.xboxlive.com',
          'RpsTicket': 'd=$accessToken',
        },
        'RelyingParty': 'http://auth.xboxlive.com',
        'TokenType': 'JWT',
      },
    );
    final xblToken = xblResponse['Token'] as String? ??
        (throw const AuthException('Xbox Live authentication failed'));

    onStatus?.call('Authorizing XSTS...');
    final xstsResponse = await _postJson(
      _xstsUrl,
      {
        'Properties': {
          'SandboxId': 'RETAIL',
          'UserTokens': [xblToken],
        },
        'RelyingParty': 'rp://api.minecraftservices.com/',
        'TokenType': 'JWT',
      },
    );
    final xstsToken = xstsResponse['Token'] as String? ??
        (throw AuthException(
          'XSTS authorization failed (code ${xstsResponse['XErr'] ?? '?'}) '
          'or this account does not own Minecraft.',
        ));
    final xstsUhs = ((xstsResponse['DisplayClaims'] as Map<String, dynamic>)['xui']
            as List<dynamic>)
        .first['uhs'] as String;

    onStatus?.call('Signing in to Minecraft services...');
    final mcResponse = await _postJson(_mcAuthUrl, {
      'identityToken': 'XBL3.0 x=$xstsUhs;$xstsToken',
    });
    final mcToken = mcResponse['access_token'] as String? ??
        (throw const AuthException('Minecraft authentication failed'));

    onStatus?.call('Fetching profile...');
    final profileResponse = await _client
        .get(Uri.parse(_profileUrl),
            headers: {'Authorization': 'Bearer $mcToken'})
        .timeout(const Duration(seconds: 30));
    if (profileResponse.statusCode != 200) {
      throw AuthException(
        'Failed to fetch Minecraft profile (${profileResponse.statusCode}). '
        'Does this account own Minecraft?',
      );
    }
    final profile = jsonDecode(profileResponse.body) as Map<String, dynamic>;

    return Account(
      username: profile['name'] as String? ?? '',
      uuid: profile['id'] as String? ?? '',
      type: AccountType.msa,
      accessToken: mcToken,
      refreshToken: refreshToken,
      expiresAtMs: DateTime.now().millisecondsSinceEpoch + expiresIn * 1000,
    );
  }

  Future<Map<String, dynamic>> _postJson(
    String url,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));
    final bodyText = response.body;
    if (response.statusCode != 200 || bodyText.isEmpty) {
      Object? err;
      try {
        err = jsonDecode(bodyText);
      } catch (_) {}
      final xerr = err is Map<String, dynamic> ? err['XErr'] : null;
      throw AuthException(
        '$url failed (${response.statusCode})${xerr != null ? ' XErr=$xerr' : ''}',
      );
    }
    return jsonDecode(bodyText) as Map<String, dynamic>;
  }

  static String _errorHint(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['error_description'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }
}

class _MsaTokens {
  const _MsaTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
}
