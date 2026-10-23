import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'collaboration_api.dart';
import 'nfc_client.dart';

const cloudIssuer = String.fromEnvironment(
  'LINESIGHT_OIDC_ISSUER',
  defaultValue: 'https://47.111.81.94/sso/realms/linesight',
);
const _redirect = 'com.linesight.app:/oauthredirect';
const _scopes = ['openid', 'profile', 'email'];

class CloudTokens {
  final String access, refresh, clientId;
  final String? idToken;
  final String? nfcCredential;
  final DateTime expiresAt;
  const CloudTokens(
    this.access,
    this.refresh,
    this.clientId,
    this.expiresAt, {
    this.idToken,
    this.nfcCredential,
  });
  Map<String, dynamic> toJson() => {
    'access': access,
    'refresh': refresh,
    'client': clientId,
    'expires': expiresAt.toUtc().toIso8601String(),
    'idToken': idToken,
    'nfcCredential': nfcCredential,
  };
  factory CloudTokens.fromJson(Map<String, dynamic> value) => CloudTokens(
    value['access'] as String,
    value['refresh'] as String,
    value['client'] as String,
    DateTime.parse(value['expires'] as String),
    idToken: value['idToken'] as String?,
    nfcCredential: value['nfcCredential'] as String?,
  );
  factory CloudTokens.fromNfc(Map<String, dynamic> value, String credential) =>
      CloudTokens(
        value['access_token'] as String,
        value['refresh_token'] as String,
        'linesight-nfc',
        DateTime.now().add(Duration(seconds: value['expires_in'] as int)),
        idToken: value['id_token'] as String?,
        nfcCredential: credential,
      );
}

abstract interface class CloudTokenVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

const cloudSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    storageNamespace: 'linesight_cloud_v1',
    resetOnError: false,
  ),
);

class SecureCloudTokenVault implements CloudTokenVault {
  static const _storage = cloudSecureStorage;
  static const _key = 'linesight.oidc.session.v1';
  @override
  Future<String?> read() async {
    final current = await _storage.read(key: _key);
    if (current != null ||
        await _storage.read(key: 'session_migrated_v1') != null) {
      return current;
    }
    String? legacy;
    try {
      legacy = await const FlutterSecureStorage().read(key: _key);
    } catch (_) {
      /* Reauthenticate if the old Android keystore cannot decrypt this session. */
    }
    if (legacy != null) await _storage.write(key: _key, value: legacy);
    await _storage.write(key: 'session_migrated_v1', value: '1');
    return legacy;
  }

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> clear() async {
    await _storage.write(key: 'session_migrated_v1', value: '1');
    await _storage.delete(key: _key);
  }
}

abstract interface class CloudIdentityGateway {
  Future<CloudTokens?> signIn({bool changePassword = false});
  Future<CloudTokens> demo();
  Future<CloudTokens> refresh(CloudTokens previous);
  Future<bool> signOut(CloudTokens previous);
}

class KeycloakIdentityGateway implements CloudIdentityGateway {
  final FlutterAppAuth appAuth;
  final NfcClient nfcClient;
  final String issuer;
  KeycloakIdentityGateway({
    this.appAuth = const FlutterAppAuth(),
    this.issuer = cloudIssuer,
    NfcClient? nfcClient,
  }) : nfcClient = nfcClient ?? NfcClient();
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
          issuer: issuer,
          scopes: _scopes,
          additionalParameters: {
            'max_age': '240',
            if (changePassword) 'kc_action': 'UPDATE_PASSWORD',
          },
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
        Uri.parse('$issuer/protocol/openid-connect/$endpoint'),
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
    if (previous.clientId == 'linesight-demo') {
      final result = await _form('token', {
        'grant_type': 'refresh_token',
        'client_id': previous.clientId,
        'refresh_token': previous.refresh,
      });
      return CloudTokens(
        result['access_token'] as String,
        result['refresh_token'] as String? ?? previous.refresh,
        previous.clientId,
        DateTime.now().add(Duration(seconds: result['expires_in'] as int)),
        idToken: result['id_token'] as String? ?? previous.idToken,
      );
    }
    if (previous.clientId == 'linesight-nfc') {
      if (previous.nfcCredential == null) {
        throw const CollaborationApiException(401, '请重新刷卡登录');
      }
      return CloudTokens.fromNfc(
        await nfcClient.session(
          'refresh',
          previous.nfcCredential!,
          previous.refresh,
        ),
        previous.nfcCredential!,
      );
    }
    try {
      final response = await appAuth.token(
        TokenRequest(
          previous.clientId,
          _redirect,
          issuer: issuer,
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
    if (previous.clientId == 'linesight-nfc') {
      if (previous.nfcCredential == null) {
        throw const CollaborationApiException(401, '请重新刷卡登录');
      }
      try {
        await nfcClient.session(
          'logout',
          previous.nfcCredential!,
          previous.refresh,
        );
      } on CollaborationApiException catch (failure) {
        if (failure.status != 401) rethrow;
      }
      return true;
    }
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
          issuer: issuer,
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
  final CollaborationApi Function(String token)? identityApiFactory;
  CloudAccount({
    CloudTokenVault? vault,
    CloudIdentityGateway? identity,
    this.apiUrl = defaultCollaborationApi,
    this.identityApiFactory,
  }) : vault = vault ?? SecureCloudTokenVault(),
       identity =
           identity ??
           KeycloakIdentityGateway(nfcClient: NfcClient(apiUrl: apiUrl));
  CloudTokens? _tokens;
  Map<String, dynamic>? profile, activeWorkspace;
  List<Map<String, dynamic>> workspaces = [], jobs = [];
  List<Map<String, dynamic>> templates = [], records = [], notifications = [];
  Map<String, dynamic> metrics = {};
  bool busy = false, restoring = true;
  String? error;
  int _epoch = 0, _workspaceEpoch = 0;
  Future<void>? _refreshing;
  Future<void> _vaultWrites = Future<void>.value();
  bool get signedIn => _tokens != null;
  final Map<String, double> uploadProgress = {};
  String? get identityScope =>
      signedIn ? '$_epoch/${profile?['id'] ?? ''}' : null;
  String? get accessScope => identityScope == null || activeWorkspace == null
      ? null
      : '$identityScope/${activeWorkspace!['id']}/${activeWorkspace!['role']}';
  bool retainsAccess(String? captured) =>
      captured != null && captured == accessScope;
  void requireAccess(
    String? captured, {
    bool write = false,
    bool owner = false,
  }) {
    if (!retainsAccess(captured) ||
        (write && !canEdit) ||
        (owner && activeWorkspace?['role'] != 'owner')) {
      throw const CollaborationApiException(403, '账户或团队已切换，请重新打开页面');
    }
  }

  bool get demoAccount => profile?['is_demo'] == true;
  String get displayName => '${profile?['display_name'] ?? ''}';
  bool get canEdit =>
      signedIn &&
      const {'owner', 'operator'}.contains(activeWorkspace?['role']);
  void _resetViews() {
    profile = null;
    activeWorkspace = null;
    workspaces = [];
    jobs = [];
    templates = [];
    records = [];
    notifications = [];
    metrics = {};
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

  Future<dynamic> _identitySessionsRequest(String method, String path) async {
    final epoch = _epoch;
    try {
      if (_tokens == null) throw const CollaborationApiException(401, '请先登录');
      if (demoAccount || _tokens!.clientId == 'linesight-demo') {
        throw const CollaborationApiException(403, '当前账户没有访问权限');
      }
      if (_tokens!.expiresAt.isBefore(
        DateTime.now().add(const Duration(seconds: 30)),
      )) {
        await _refresh();
      }
      if (epoch != _epoch || _tokens == null) {
        throw const CollaborationApiException(401, '请先登录');
      }
      final api =
          identityApiFactory?.call(_tokens!.access) ??
          CollaborationApi('$cloudIssuer/account/', token: _tokens!.access);
      final result = await api.request(method, path);
      if (epoch != _epoch) throw const CollaborationApiException(401, '请先登录');
      return result;
    } on CollaborationApiException catch (failure) {
      if (failure.status == 401 && epoch == _epoch) await _expired();
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> listIdentitySessions() async {
    final data = await _identitySessionsRequest('GET', 'sessions');
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> revokeIdentitySession(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw const CollaborationApiException(400, '请核对填写内容');
    }
    final epoch = _epoch;
    final sessions = await listIdentitySessions();
    if (epoch != _epoch) {
      throw const CollaborationApiException(401, '请先登录');
    }
    final selected = sessions.where((row) => row['id'] == id).firstOrNull;
    if (selected == null) throw const CollaborationApiException(404, '记录暂不可访问');
    await _identitySessionsRequest('DELETE', 'sessions/$id');
    if (selected['current'] == true && epoch == _epoch) {
      _epoch++;
      _tokens = null;
      _resetViews();
      error = null;
      await _persist(_epoch);
      notifyListeners();
    }
  }

  Future<void> revokeOtherIdentitySessions() async {
    await _identitySessionsRequest('DELETE', 'sessions?current=false');
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
  Future<void> signInNfc(String cardCode) => _operation(() async {
    final epoch = ++_epoch;
    final result = await NfcClient(apiUrl: apiUrl).login(cardCode);
    if (epoch != _epoch) return;
    _resetViews();
    _tokens = CloudTokens.fromNfc(result, result['credential_id'] as String);
    await _persist(epoch);
    await _load();
  });
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
    templates = [];
    records = [];
    notifications = [];
    metrics = {};
    notifyListeners();
    final base = 'workspaces/${workspace['id']}/';
    final data = await Future.wait([
      for (final path in [
        'jobs/',
        'templates/',
        'records/',
        'metrics/',
        'notifications/',
      ])
        request('GET', '$base$path'),
    ]);
    if (epoch == _workspaceEpoch) {
      jobs = (data[0] as List).cast<Map<String, dynamic>>();
      templates = (data[1] as List).cast<Map<String, dynamic>>();
      records = (data[2] as List).cast<Map<String, dynamic>>();
      metrics = Map<String, dynamic>.from(data[3] as Map);
      notifications = (data[4] as List).cast<Map<String, dynamic>>();
    }
  }

  Future<void> updateDisplayName(String value) => _operation(() async {
    profile = Map<String, dynamic>.from(
      await request('PATCH', 'auth/me/', body: {'display_name': value}) as Map,
    );
  });

  String? draftKey(String kind) =>
      signedIn && profile?['id'] != null && activeWorkspace != null
      ? 'linesight.draft.${profile!['id']}.${activeWorkspace!['id']}.$kind'
      : null;
  Future<Map<String, dynamic>?> readDraft(String key) async {
    final raw = await cloudSecureStorage.read(key: key);
    return raw == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> _draftWrites = Future<void>.value();
  Future<void> saveDraft(String key, Map<String, dynamic> value) {
    final encoded = jsonEncode(value);
    return _draftWrites = _draftWrites
        .catchError((_) {})
        .then((_) => cloudSecureStorage.write(key: key, value: encoded));
  }

  Future<void> deleteDraft(String key) => _draftWrites = _draftWrites
      .catchError((_) {})
      .then((_) => cloudSecureStorage.delete(key: key));
  Future<List<Map<String, dynamic>>> listDrafts() async {
    final prefix = draftKey('');
    if (prefix == null) return [];
    final all = await cloudSecureStorage.readAll();
    if (prefix != draftKey('')) {
      throw const CollaborationApiException(401, '请切回原工作区后重试');
    }
    return [
      for (final entry in all.entries)
        if (entry.key.startsWith(prefix) &&
            (entry.key.endsWith('.create') ||
                entry.key.contains('.inspect-') ||
                entry.key.contains('.resolve-')))
          {
            ...Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
            '_key': entry.key,
          },
    ];
  }

  Future<List<int>> download(String path) async {
    final epoch = _epoch;
    if (_tokens == null) throw const CollaborationApiException(401, '请先登录');
    if (_tokens!.expiresAt.isBefore(
      DateTime.now().add(const Duration(seconds: 30)),
    )) {
      await _refresh();
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(apiUrl).resolve(path));
      req.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${_tokens!.access}',
      );
      final response = await req.close().timeout(const Duration(seconds: 25));
      if (response.statusCode == 401) {
        await _expired();
        throw const CollaborationApiException(401, '登录已过期，请重新登录');
      }
      if (response.statusCode != 200) {
        throw CollaborationApiException(response.statusCode, '无法读取文件，请重试');
      }
      final data = await response
          .fold<List<int>>([], (bytes, part) => bytes..addAll(part))
          .timeout(const Duration(seconds: 30));
      if (epoch != _epoch) throw const CollaborationApiException(401, '请先登录');
      return data;
    } on SocketException {
      throw const CollaborationApiException(503, '网络连接失败，请重试');
    } on TimeoutException {
      throw const CollaborationApiException(503, '连接超时，请重试');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> uploadPhoto(
    String path,
    List<int> bytes,
    String key,
    Map<String, String> fields,
  ) async {
    final epoch = _epoch;
    if (_tokens == null) throw const CollaborationApiException(401, '请先登录');
    if (_tokens!.expiresAt.isBefore(
      DateTime.now().add(const Duration(seconds: 30)),
    )) {
      await _refresh();
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    final boundary = 'linesight${DateTime.now().microsecondsSinceEpoch}';
    uploadProgress[key] = 0;
    notifyListeners();
    try {
      final req = await client.postUrl(Uri.parse(apiUrl).resolve(path));
      req.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${_tokens!.access}',
      );
      req.headers.set('Idempotency-Key', key);
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      final parts = <List<int>>[];
      for (final entry in fields.entries) {
        parts.add(
          utf8.encode(
            '--$boundary\r\nContent-Disposition: form-data; name="${entry.key}"\r\n\r\n${entry.value}\r\n',
          ),
        );
      }
      parts.add(
        utf8.encode(
          '--$boundary\r\nContent-Disposition: form-data; name="image"; filename="photo.jpg"\r\nContent-Type: image/jpeg\r\n\r\n',
        ),
      );
      parts.add(bytes);
      parts.add(utf8.encode('\r\n--$boundary--\r\n'));
      req.contentLength = parts.fold<int>(
        0,
        (total, part) => total + part.length,
      );
      var sent = 0;
      for (final part in parts) {
        for (var offset = 0; offset < part.length; offset += 65536) {
          if (epoch != _epoch) {
            throw const CollaborationApiException(401, '请先登录');
          }
          final end = (offset + 65536).clamp(0, part.length);
          req.add(part.sublist(offset, end));
          await req.flush().timeout(const Duration(seconds: 30));
          sent += end - offset;
          uploadProgress[key] = (sent / req.contentLength).clamp(0, .99);
          notifyListeners();
        }
      }
      final response = await req.close().timeout(const Duration(seconds: 60));
      final body = Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(response).join()) as Map,
      );
      if (response.statusCode == 401) await _expired();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CollaborationApiException(
          response.statusCode,
          '${body['detail'] ?? '上传失败，请重试'}',
        );
      }
      if (epoch != _epoch) throw const CollaborationApiException(401, '请先登录');
      return body;
    } on SocketException {
      throw const CollaborationApiException(503, '网络连接失败，请重试');
    } on TimeoutException {
      throw const CollaborationApiException(503, '连接超时，请重试');
    } finally {
      client.close(force: true);
      uploadProgress.remove(key);
      notifyListeners();
    }
  }

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
