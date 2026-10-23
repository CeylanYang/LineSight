import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'collaboration_api.dart';

const cloudIssuer = String.fromEnvironment(
  'LINESIGHT_OIDC_ISSUER',
  defaultValue: 'https://47.111.81.94/sso/realms/linesight',
);
const _redirect = 'com.linesight.app:/oauthredirect';
const _scopes = ['openid', 'profile', 'email'];

class CloudTokens {
  final String access, refresh, clientId;
  final String? idToken;
  final DateTime expiresAt;
  const CloudTokens(
    this.access,
    this.refresh,
    this.clientId,
    this.expiresAt, {
    this.idToken,
  });
  Map<String, dynamic> toJson() => {
    'access': access,
    'refresh': refresh,
    'client': clientId,
    'expires': expiresAt.toUtc().toIso8601String(),
    'idToken': idToken,
  };
  factory CloudTokens.fromJson(Map<String, dynamic> value) => CloudTokens(
    value['access'] as String,
    value['refresh'] as String,
    value['client'] as String,
    DateTime.parse(value['expires'] as String),
    idToken: value['idToken'] as String?,
  );
}

abstract interface class CloudTokenVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureCloudTokenVault implements CloudTokenVault {
  static const _storage = FlutterSecureStorage();
  static const _key = 'linesight.oidc.session.v1';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

abstract interface class CloudIdentityGateway {
  Future<CloudTokens?> signIn({bool changePassword = false});
  Future<CloudTokens> demo();
  Future<CloudTokens> refresh(CloudTokens previous);
  Future<bool> signOut(CloudTokens previous);
}

class KeycloakIdentityGateway implements CloudIdentityGateway {
  final FlutterAppAuth appAuth;
  KeycloakIdentityGateway({this.appAuth = const FlutterAppAuth()});
  CloudTokens _tokens(
    TokenResponse response,
    String client, {
    String? previousRefresh,
  }) {
    final access = response.accessToken,
        refresh = response.refreshToken ?? previousRefresh;
    if (access == null || refresh == null) {
      throw const CollaborationApiException(401, '登录未完成，请重新登录');
    }
    return CloudTokens(
      access,
      refresh,
      client,
      response.accessTokenExpirationDateTime ??
          DateTime.now().add(const Duration(minutes: 4)),
      idToken: response.idToken,
    );
  }

  @override
  Future<CloudTokens?> signIn({bool changePassword = false}) async {
    try {
      final response = await appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          'linesight-android',
          _redirect,
          issuer: cloudIssuer,
          scopes: _scopes,
          additionalParameters: changePassword
              ? {'kc_action': 'UPDATE_PASSWORD'}
              : null,
        ),
      );
      return _tokens(response, 'linesight-android');
    } on FlutterAppAuthUserCancelledException {
      return null;
    } on FlutterAppAuthPlatformException {
      throw const CollaborationApiException(0, '登录未完成，请检查网络后重试');
    }
  }

  Future<Map<String, dynamic>> _form(
    String endpoint,
    Map<String, String> body,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(
        Uri.parse('$cloudIssuer/protocol/openid-connect/$endpoint'),
      );
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write(Uri(queryParameters: body).query);
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CollaborationApiException(
          response.statusCode == 400 ? 401 : response.statusCode,
          '登录未完成，请重新登录',
        );
      }
      return text.isEmpty
          ? {}
          : Map<String, dynamic>.from(jsonDecode(text) as Map);
    } on SocketException {
      throw const CollaborationApiException(0, '无法连接服务，请检查网络后重试');
    } on TimeoutException {
      throw const CollaborationApiException(0, '连接超时，请重试');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<CloudTokens> demo() async {
    const username = String.fromEnvironment('LINESIGHT_DEMO_USERNAME');
    const password = String.fromEnvironment('LINESIGHT_DEMO_PASSWORD');
    if (username.isEmpty || password.isEmpty) {
      throw const CollaborationApiException(503, '演示团队暂不可用，请稍后重试');
    }
    final result = await _form('token', {
      'grant_type': 'password',
      'client_id': 'linesight-demo',
      'username': username,
      'password': password,
      'scope': 'openid profile email',
    });
    return CloudTokens(
      result['access_token'] as String,
      result['refresh_token'] as String,
      'linesight-demo',
      DateTime.now().add(Duration(seconds: result['expires_in'] as int)),
      idToken: result['id_token'] as String?,
    );
  }

  @override
  Future<CloudTokens> refresh(CloudTokens previous) async {
    try {
      final response = await appAuth.token(
        TokenRequest(
          previous.clientId,
          _redirect,
          issuer: cloudIssuer,
          refreshToken: previous.refresh,
        ),
      );
      return _tokens(
        response,
        previous.clientId,
        previousRefresh: previous.refresh,
      );
    } on FlutterAppAuthPlatformException catch (error) {
      if (error.details.error == 'invalid_grant') {
        throw const CollaborationApiException(401, '登录已过期，请重新登录');
      }
      throw const CollaborationApiException(0, '无法恢复登录，请检查网络后重试');
    }
  }

  @override
  Future<bool> signOut(CloudTokens previous) async {
    if (previous.clientId == 'linesight-demo') {
      await _form('logout', {
        'client_id': previous.clientId,
        'refresh_token': previous.refresh,
      });
      return true;
    }
    try {
      await appAuth.endSession(
        EndSessionRequest(
          issuer: cloudIssuer,
          idTokenHint: previous.idToken,
          postLogoutRedirectUrl: _redirect,
        ),
      );
      return true;
    } on FlutterAppAuthUserCancelledException {
      return false;
    }
  }
}

class CloudAccount extends ChangeNotifier {
  final CloudTokenVault vault;
  final CloudIdentityGateway identity;
  final String apiUrl;
  CloudAccount({
    CloudTokenVault? vault,
    CloudIdentityGateway? identity,
    this.apiUrl = defaultCollaborationApi,
  }) : vault = vault ?? SecureCloudTokenVault(),
       identity = identity ?? KeycloakIdentityGateway();
  CloudTokens? _tokens;
  Map<String, dynamic>? profile, activeWorkspace;
  List<Map<String, dynamic>> workspaces = [], jobs = [];
  bool busy = false, restoring = true;
  String? error;
  int _epoch = 0, _workspaceEpoch = 0;
  Future<void>? _refreshing;
  Future<void> _vaultWrites = Future<void>.value();
  bool get signedIn => _tokens != null;
  bool get demoAccount => profile?['is_demo'] == true;
  String get displayName => '${profile?['display_name'] ?? ''}';
  bool get canEdit =>
      activeWorkspace != null && activeWorkspace!['role'] != 'viewer';
  void _resetViews() {
    profile = null;
    activeWorkspace = null;
    workspaces = [];
    jobs = [];
    _workspaceEpoch++;
  }

  Future<void> _persist(int epoch) {
    _vaultWrites = _vaultWrites.catchError((_) {}).then((_) async {
      if (epoch != _epoch) return;
      final tokens = _tokens;
      if (tokens == null) {
        await vault.clear();
      } else {
        await vault.write(jsonEncode(tokens.toJson()));
      }
    });
    return _vaultWrites;
  }

  Future<void> _expired() async {
    final epoch = ++_epoch;
    _tokens = null;
    _resetViews();
    error = '登录已过期，请重新登录';
    await _persist(epoch);
    notifyListeners();
  }

  Future<void> _refresh() =>
      _refreshing ??= _refreshOnce().whenComplete(() => _refreshing = null);
  Future<void> _refreshOnce() async {
    final previous = _tokens, epoch = _epoch;
    if (previous == null) throw const CollaborationApiException(401, '请先登录');
    final next = await identity.refresh(previous);
    if (epoch != _epoch || !identical(_tokens, previous)) {
      throw const CollaborationApiException(401, '请先登录');
    }
    _tokens = next;
    await _persist(epoch);
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    final epoch = _epoch;
    try {
      if (_tokens == null) throw const CollaborationApiException(401, '请先登录');
      if (_tokens!.expiresAt.isBefore(
        DateTime.now().add(const Duration(seconds: 30)),
      )) {
        await _refresh();
      }
      final result = await CollaborationApi(
        apiUrl,
        token: _tokens!.access,
      ).request(method, path, body: body, idempotencyKey: idempotencyKey);
      if (epoch != _epoch) throw const CollaborationApiException(401, '请先登录');
      return result;
    } on CollaborationApiException catch (failure) {
      if (failure.status == 401 && epoch == _epoch) await _expired();
      rethrow;
    }
  }

  Future<void> _operation(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } on CollaborationApiException catch (failure) {
      error = failure.message;
    } catch (_) {
      error = '操作未完成，请重试。';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> restore() => _operation(() async {
    final epoch = _epoch;
    try {
      final saved = await vault.read();
      if (epoch != _epoch || saved == null) return;
      try {
        _tokens = CloudTokens.fromJson(
          Map<String, dynamic>.from(jsonDecode(saved) as Map),
        );
      } on FormatException {
        await vault.clear();
        return;
      } on TypeError {
        await vault.clear();
        return;
      }
      await _load();
    } finally {
      restoring = false;
    }
  });
  Future<void> signIn({bool demo = false, bool changePassword = false}) =>
      _operation(() async {
        final epoch = ++_epoch;
        final tokens = demo
            ? await identity.demo()
            : await identity.signIn(changePassword: changePassword);
        if (tokens == null || epoch != _epoch) return;
        _resetViews();
        _tokens = tokens;
        await _persist(epoch);
        await _load();
      });
  Future<void> reload() => _operation(_load);
  Future<void> _load() async {
    profile = Map<String, dynamic>.from(
      await request('GET', 'auth/me/') as Map,
    );
    workspaces = (await request('GET', 'workspaces/') as List)
        .cast<Map<String, dynamic>>();
    final selected = activeWorkspace?['id'] ?? profile?['home_workspace_id'];
    final match = workspaces.where((w) => w['id'] == selected);
    if (workspaces.isEmpty) {
      activeWorkspace = null;
      jobs = [];
      return;
    }
    await _select(match.isNotEmpty ? match.first : workspaces.first);
  }

  Future<void> selectWorkspace(Map<String, dynamic> workspace) =>
      _operation(() => _select(workspace));
  Future<void> _select(Map<String, dynamic> workspace) async {
    final epoch = ++_workspaceEpoch;
    activeWorkspace = workspace;
    jobs = [];
    notifyListeners();
    final rows =
        (await request('GET', 'workspaces/${workspace['id']}/jobs/') as List)
            .cast<Map<String, dynamic>>();
    if (epoch == _workspaceEpoch) jobs = rows;
  }

  Future<void> updateDisplayName(String value) => _operation(() async {
    profile = Map<String, dynamic>.from(
      await request('PATCH', 'auth/me/', body: {'display_name': value}) as Map,
    );
  });
  Future<void> signOut() => _operation(() async {
    final previous = _tokens;
    if (previous == null || !await identity.signOut(previous)) return;
    final epoch = ++_epoch;
    _tokens = null;
    _resetViews();
    await _persist(epoch);
  });
}

class CloudScope extends InheritedNotifier<CloudAccount> {
  const CloudScope({
    super.key,
    required CloudAccount account,
    required super.child,
  }) : super(notifier: account);
  static CloudAccount of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CloudScope>()!.notifier!;
}
