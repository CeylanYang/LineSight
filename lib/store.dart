import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'models.dart';
import 'backup.dart';
import 'state_storage.dart';
import 'recovery_storage.dart';
import 'record_csv.dart';

Future<String> _derivePassword(List<String> input) async {
  final kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  );
  return base64Encode(
    await (await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(input[0])),
      nonce: base64Decode(input[1]),
    )).extractBytes(),
  );
}

enum ExportOutcome { saved, cancelled, failed }

// Issued only after permission checks and a durable start entry. This ticket
// permits recording one native picker outcome; it grants no workspace access.
class ExportTicket {
  final String id, actorId, actor, kind;
  final String? reference;
  final int session, count;
  final List<AuditTarget> targets;
  ExportTicket._(
    this.id,
    LocalUser user,
    this.kind,
    this.count,
    this.session,
    Iterable<AuditTarget> targets, {
    this.reference,
  }) : actorId = user.id,
       actor = user.name,
       targets = List.unmodifiable(targets);
}

class AppStore extends ChangeNotifier {
  late Database db;
  Workspace data = Workspace.seed(examples: false);
  int revision = 0;
  RestorePointInfo? restorePoint;
  BackupReceipt? lastBackup;
  List<TimeMigrationArchive> timeArchives = [];
  LocalUser? user;
  List<LocalUser> users = [];
  Json preferences = {};
  bool ready = false, _writing = false;
  Completer<void>? _writeFinished;
  bool get writing => _writing;
  set writing(bool value) {
    if (value == _writing) return;
    _writing = value;
    if (value) {
      _writeFinished = Completer<void>();
    } else {
      _writeFinished?.complete();
      _writeFinished = null;
    }
  }

  final Map<String, ExportTicket> _exports = {};
  final Map<String, String> _fileNotices = {};
  String? get fileNotice => user == null ? null : _fileNotices[user!.id];
  String? lockReason;
  Stopwatch? _away;
  Timer? _lockTimer;
  String? startupError;
  String startupStage = '打开本机存储';
  bool initializing = false, canRecoverStorage = false;
  String? _databasePath;
  LocalUser? _recoveryUser;
  LocalUser? get recoveryUser => _recoveryUser;
  int session = 0;
  Future<void> _preferenceWrites = Future<void>.value();
  bool get admin => user?.role == 'admin';
  bool get engineer => admin || user?.role == 'engineer';
  bool get dark => preferences['dark'] == true;
  bool get glass => preferences['glass'] != false;
  bool get haptics => preferences['haptics'] != false;
  bool get reduceMotion => preferences['reduceMotion'] == true;
  bool get autoLock => preferences['autoLock'] != false;
  List<Inspection> get records =>
      data.inspections.where((r) => !r.archived).toList()
        ..sort((a, b) => b.at.compareTo(a.at));
  List<Inspection> get pending => records.where((r) => r.pending).toList();

  Future<void> init({String? path}) async {
    if (initializing || writing) throw StateError('正在读取或保存，请稍后重试');
    initializing = true;
    ready = false;
    canRecoverStorage = false;
    user = null;
    _recoveryUser = null;
    session++;
    startupError = null;
    startupStage = '打开本机存储';
    notifyListeners();
    try {
      _databasePath =
          path ??
          _databasePath ??
          p.join(await getDatabasesPath(), 'linesight_local_v1.db');
      db = await openDatabase(
        _databasePath!,
        version: 3,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE accounts (id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL, name TEXT NOT NULL, role TEXT NOT NULL, enabled INTEGER NOT NULL, salt TEXT NOT NULL, hash TEXT NOT NULL, recoverySalt TEXT NOT NULL, recoveryHash TEXT NOT NULL, failures INTEGER NOT NULL DEFAULT 0, lockedUntil INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await StateStorage.create(db);
          await RecoveryStorage.create(db);
          await db.insert('state', {
            'key': 'workspace',
            'value': jsonEncode(Workspace.seed(examples: false).toJson()),
          });
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await StateStorage.create(db);
          if (oldVersion < 3) await RecoveryStorage.create(db);
        },
      );
      startupStage = '读取本机账户';
      await _loadUsers();
      canRecoverStorage = users.any((u) => u.enabled && u.role == 'admin');
      startupStage = '校验工作区与本机设置';
      final stored = await db.transaction(StateStorage.readAll);
      if (!stored.any((row) => row['key'] == 'workspace')) {
        throw const FormatException('本机工作区缺失');
      }
      final rows = await _normalizeStoredTimes(stored);
      preferences = {};
      lastBackup = null;
      for (final row in rows) {
        if (row['key'] == 'workspace') {
          data = Workspace.fromJson(jsonDecode(row['value'] as String));
          data.validate();
        }
        if (row['key'] == 'preferences') {
          preferences = jsonDecode(row['value'] as String);
        }
        if (row['key'] == 'backupReceipt') {
          lastBackup = BackupReceipt.fromJson(
            jsonDecode(row['value'] as String),
          );
        }
      }
      final point = rows
          .where((row) => row['key'] == 'restorePoint')
          .firstOrNull;
      final meta = rows
          .where((row) => row['key'] == 'restorePointMeta')
          .firstOrNull;
      restorePoint = point == null
          ? null
          : meta == null
          ? RestorePointInfo.legacy(
              Workspace.fromJson(jsonDecode(point['value'] as String)),
            )
          : RestorePointInfo.fromJson(jsonDecode(meta['value'] as String));
      await _loadUsers();
      ready = true;
      canRecoverStorage = false;
      startupError = null;
    } catch (_) {
      startupError = '无法读取本机数据库。请检查存储空间，然后重试。原始数据已保留。';
    } finally {
      initializing = false;
    }
    notifyListeners();
  }

  Future<List<Map<String, Object?>>> _normalizeStoredTimes(
    List<Map<String, Object?>> rows,
  ) async {
    final values = {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    final archives =
        (values['timeArchives'] == null
                ? <dynamic>[]
                : jsonDecode(values['timeArchives']!) as List)
            .map((j) => TimeMigrationArchive.fromJson(Json.from(j)))
            .toList();
    for (final archive in archives) {
      parseInstant(archive.capturedAt);
    }
    final originals = <String, String>{}, normalized = <String, String>{};
    var count = 0;
    for (final key in [
      'workspace',
      'restorePoint',
      'restorePointMeta',
      'backupReceipt',
    ]) {
      final source = values[key];
      if (source == null) continue;
      originals[key] = source;
      final j = Json.from(jsonDecode(source));
      if (key == 'workspace' || key == 'restorePoint') {
        count += normalizeWorkspaceTimes(j, localGapCompatibility: true);
        Workspace.fromJson(j).validate();
      } else if (key == 'restorePointMeta') {
        count += normalizeTimeField(
          j,
          'createdAt',
          localGapCompatibility: true,
        );
        RestorePointInfo.fromJson(j);
      } else {
        count += normalizeTimeField(j, 'savedAt', localGapCompatibility: true);
        BackupReceipt.fromJson(j);
      }
      normalized[key] = jsonEncode(j);
    }
    if (count > 0) {
      final now = DateTime.now();
      archives.add(
        TimeMigrationArchive(
          id: uid(),
          capturedAt: instantJson(now),
          zoneName: now.timeZoneName,
          offsetMinutes: now.timeZoneOffset.inMinutes,
          count: count,
          originals: originals,
        ),
      );
      // Preserve raw snapshots and canonicalize as one atomic operation.
      await db.transaction((tx) async {
        await StateStorage.write(
          tx,
          'timeArchives',
          jsonEncode(archives.map((a) => a.toJson()).toList()),
        );
        for (final entry in normalized.entries) {
          await StateStorage.write(tx, entry.key, entry.value);
        }
      });
      values.addAll(normalized);
    }
    timeArchives = List.unmodifiable(archives);
    return values.entries
        .map((e) => <String, Object?>{'key': e.key, 'value': e.value})
        .toList();
  }

  Future<void> _loadUsers() async {
    users = (await db.query(
      'accounts',
      columns: ['id', 'username', 'name', 'role', 'enabled'],
      orderBy: 'username',
    )).map((x) => LocalUser.fromJson(x)).toList();
  }

  String _salt() =>
      base64Encode(List.generate(24, (_) => Random.secure().nextInt(256)));
  Future<String> _hash(String password, String salt) =>
      compute(_derivePassword, [password, salt]);
  bool _equal(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  void _password(String value) {
    if (value.length < 8 || value.length > 128 || value.trim().length < 8) {
      throw StateError('密码需要 8–128 个字符');
    }
  }

  void _require({bool elevated = false, bool owner = false}) {
    checkAutoLock();
    if (!ready || startupError != null) throw StateError('本机工作区尚未打开');
    if (user == null) throw StateError('请先登录');
    if (owner && !admin || elevated && !engineer) {
      throw StateError('当前账户没有此操作权限');
    }
  }

  void feedback() {
    if (haptics) HapticFeedback.selectionClick();
  }

  void lock({String? reason}) {
    _lockTimer?.cancel();
    lockReason = reason;
    user = null;
    _recoveryUser = null;
    session++;
    notifyListeners();
  }

  void backgrounded() {
    _away ??= Stopwatch()..start();
    _lockTimer?.cancel();
    if ((autoLock && user != null) || _recoveryUser != null) {
      final remaining = const Duration(seconds: 30) - _away!.elapsed;
      _lockTimer = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        checkAutoLock,
      );
    }
  }

  void checkAutoLock() {
    if (((autoLock && user != null) || _recoveryUser != null) &&
        (_away?.elapsed ?? Duration.zero) >= const Duration(seconds: 30)) {
      lock(reason: '离开应用超过 30 秒，已自动锁定。请重新登录。');
    }
  }

  void resumed() {
    checkAutoLock();
    _lockTimer?.cancel();
    _away = null;
  }

  void requireSession(
    int expected, {
    bool elevated = false,
    bool owner = false,
  }) {
    _require(elevated: elevated, owner: owner);
    if (session != expected) throw StateError('会话已过期，请重新操作');
  }

  void dismissFileNotice() {
    if (user != null) _fileNotices.remove(user!.id);
    notifyListeners();
  }

  void reportFileNotice(ExportTicket ticket, String message) {
    _fileNotices[ticket.actorId] = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }

  Future<void> signOut() async {
    try {
      await _commit('退出登录', '本地会话已结束', (_) {});
    } finally {
      lock();
    }
  }

  Future<String> register(
    String username,
    String name,
    String password, {
    bool examples = true,
  }) async {
    if (!ready || startupError != null) throw StateError('本机工作区尚未打开');
    if (writing) throw StateError('正在保存，请稍后重试');
    final first = users.isEmpty;
    if (!first) _require(owner: true);
    final startedSession = session;
    username = username.trim().toLowerCase();
    name = name.trim();
    if (!RegExp(r'^[a-z0-9_.-]{3,32}$').hasMatch(username)) {
      throw StateError('用户名需为 3–32 位字母、数字、点、横线或下划线');
    }
    if (name.isEmpty || name.length > 40) throw StateError('姓名需要 1–40 个字符');
    _password(password);
    writing = true;
    try {
      final salt = _salt(), recoverySalt = _salt();
      final recovery = List.generate(
        4,
        (_) =>
            Random.secure().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0'),
      ).join('-').toUpperCase();
      final id = uid();
      final hash = await _hash(password, salt);
      final recoveryHash = await _hash(recovery, recoverySalt);
      if (!first) requireSession(startedSession, owner: true);
      final next = first
          ? Workspace.seed(examples: examples)
          : Workspace.fromJson(data.toJson());
      next.audits.add(
        AuditEntry(
          uid(),
          first ? name : user!.name,
          '创建账户',
          '$username · ${first ? '管理员' : '操作员'}',
          DateTime.now(),
          actorId: first ? id : user!.id,
          targets: [AuditTarget('account', id, '$name · $username')],
        ),
      );
      await db.transaction((tx) async {
        await tx.insert('accounts', {
          'id': id,
          'username': username,
          'name': name,
          'role': first ? 'admin' : 'operator',
          'enabled': 1,
          'salt': salt,
          'hash': hash,
          'recoverySalt': recoverySalt,
          'recoveryHash': recoveryHash,
        });
        await StateStorage.write(tx, 'workspace', jsonEncode(next.toJson()));
      });
      data = next;
      revision++;
      await _loadUsers();
      notifyListeners();
      return recovery;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw StateError('该用户名已存在');
      rethrow;
    } finally {
      writing = false;
    }
  }

  Future<LocalUser> _verifyAccount(
    String username,
    String password,
    int startedSession, {
    bool recoveryCode = false,
    bool adminOnly = false,
  }) async {
    final rows = await db.query(
      'accounts',
      where: 'username = ?',
      whereArgs: [username.trim().toLowerCase()],
    );
    if (rows.isEmpty) {
      await _hash(password, _salt());
      throw StateError(recoveryCode ? '账户或恢复码不正确' : '用户名或密码不正确');
    }
    final account = rows.first;
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((account['lockedUntil'] as int) > now) {
      throw StateError('尝试次数过多，请在 1 分钟后重试');
    }
    final valid = _equal(
      await _hash(
        recoveryCode ? password.trim().toUpperCase() : password,
        account[recoveryCode ? 'recoverySalt' : 'salt'] as String,
      ),
      account[recoveryCode ? 'recoveryHash' : 'hash'] as String,
    );
    if (!valid) {
      final fails = (account['failures'] as int) + 1;
      await db.update(
        'accounts',
        {'failures': fails, 'lockedUntil': fails >= 5 ? now + 60000 : 0},
        where: 'id = ?',
        whereArgs: [account['id']],
      );
      throw StateError(recoveryCode ? '账户或恢复码不正确' : '用户名或密码不正确');
    }
    if (adminOnly && account['role'] != 'admin') {
      throw StateError('异常恢复需要本机管理员账户');
    }
    if (account['enabled'] != 1) throw StateError('该账户已停用，请联系本机管理员');
    if (session != startedSession) throw StateError('会话已过期，请重新登录');
    await db.update(
      'accounts',
      {'failures': 0, 'lockedUntil': 0},
      where: 'id = ?',
      whereArgs: [account['id']],
    );
    if (session != startedSession) throw StateError('会话已过期，请重新登录');
    return LocalUser.fromJson(account);
  }

  Future<void> login(String username, String password) async {
    if (!ready || startupError != null) throw StateError('请通过异常恢复入口验证管理员');
    if (writing) throw StateError('正在处理，请稍后');
    final startedSession = session;
    writing = true;
    try {
      user = await _verifyAccount(username, password, startedSession);
      lockReason = null;
      session++;
    } finally {
      writing = false;
    }
    try {
      await _commit('登录', '本机密码验证成功', (_) {});
    } catch (_) {
      lock();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> loginForStorageRecovery(
    String username,
    String secret, {
    bool recoveryCode = false,
  }) async {
    if (startupError == null || !canRecoverStorage || ready) {
      throw StateError('当前无需异常恢复，或账户无法读取');
    }
    if (writing || initializing) throw StateError('正在处理，请稍后');
    final startedSession = session;
    writing = true;
    try {
      final actor = await _verifyAccount(
        username,
        secret,
        startedSession,
        recoveryCode: recoveryCode,
        adminOnly: true,
      );
      if (session != startedSession || startupError == null) {
        throw StateError('会话已过期，请重新验证');
      }
      _recoveryUser = actor;
      lockReason = null;
      session++;
    } finally {
      writing = false;
    }
    notifyListeners();
  }

  void requireStorageRecovery(int expectedSession) {
    checkAutoLock();
    if (ready ||
        startupError == null ||
        !canRecoverStorage ||
        _recoveryUser == null ||
        session != expectedSession) {
      throw StateError('恢复验证已过期，请重新验证管理员');
    }
  }

  Future<List<RecoverySnapshot>> recoveryHistory() async {
    _require(owner: true);
    final startedSession = session;
    final result = await RecoveryStorage.history(db);
    requireSession(startedSession, owner: true);
    return result;
  }

  Future<void> recoverStorage(
    BackupDocument document, {
    required int expectedSession,
    required String fileName,
    required bool acknowledged,
  }) async {
    requireStorageRecovery(expectedSession);
    if (writing) throw StateError('正在保存，请稍后');
    if (!acknowledged || !document.readyToRestore) {
      throw StateError('请先确认备份内容和旧时间解释');
    }
    if (fileName.isEmpty || fileName.length > 255) throw StateError('备份文件名无效');
    final actor = _recoveryUser!, snapshotId = uid();
    writing = true;
    try {
      final restored = Workspace.fromJson(document.workspace.toJson());
      restored.audits.add(
        AuditEntry(
          uid(),
          actor.name,
          '异常恢复',
          '从 $fileName 恢复 ${restored.inspections.length} 条记录；恢复前原件 $snapshotId 已保留'
              '${document.timeInterpretation == null ? '' : '；旧时间解释：${document.timeInterpretation}'}',
          DateTime.now(),
          actorId: actor.id,
          operationId: snapshotId,
        ),
      );
      restored.validate();
      var keptPreferences = <String, dynamic>{};
      var keptArchives = <TimeMigrationArchive>[];
      await db.transaction((tx) async {
        requireStorageRecovery(expectedSession);
        final accounts = await tx.query(
          'accounts',
          where: 'id = ? AND role = ? AND enabled = 1',
          whereArgs: [actor.id, 'admin'],
        );
        if (accounts.length != 1) throw StateError('管理员权限已改变，请重新验证');
        await RecoveryStorage.preserve(
          tx,
          id: snapshotId,
          actor: actor,
          sourceName: fileName,
          document: document,
        );
        try {
          final source = await StateStorage.read(tx, 'preferences');
          if (source != null) {
            final values = Json.from(jsonDecode(source));
            keptPreferences = {
              for (final key in [
                'dark',
                'glass',
                'haptics',
                'reduceMotion',
                'autoLock',
              ])
                if (values[key] is bool) key: values[key],
            };
          }
        } on FormatException {
          /* Exact originals were preserved above. */
        } on TypeError {
          /* Invalid settings use defaults. */
        }
        try {
          final source = await StateStorage.read(tx, 'timeArchives');
          if (source != null) {
            final candidates = (jsonDecode(source) as List)
                .map((value) => TimeMigrationArchive.fromJson(Json.from(value)))
                .toList();
            for (final archive in candidates) {
              parseInstant(archive.capturedAt);
            }
            keptArchives = candidates;
          }
        } on FormatException {
          /* Preserved in recovery originals. */
        } on TypeError {
          /* Preserved in recovery originals. */
        }
        await tx.delete('state_chunks');
        await tx.delete('state');
        await StateStorage.write(
          tx,
          'workspace',
          jsonEncode(restored.toJson()),
        );
        await StateStorage.write(
          tx,
          'preferences',
          jsonEncode(keptPreferences),
        );
        if (keptArchives.isNotEmpty) {
          await StateStorage.write(
            tx,
            'timeArchives',
            jsonEncode(keptArchives.map((a) => a.toJson()).toList()),
          );
        }
        requireStorageRecovery(expectedSession);
      });
      data = restored;
      preferences = keptPreferences;
      timeArchives = List.unmodifiable(keptArchives);
      restorePoint = null;
      lastBackup = null;
      revision++;
      ready = true;
      startupError = null;
      canRecoverStorage = false;
      lock(reason: '业务数据已恢复，请重新登录。恢复前原件可在“数据管理 → 异常恢复记录”查看。');
    } finally {
      writing = false;
    }
  }

  Future<void> recover(String username, String code, String newPassword) async {
    if (!ready || startupError != null) throw StateError('本机工作区尚未打开');
    _password(newPassword);
    if (writing) throw StateError('正在处理，请稍后');
    writing = true;
    try {
      final rows = await db.query(
        'accounts',
        where: 'username = ?',
        whereArgs: [username.trim().toLowerCase()],
      );
      if (rows.isEmpty) throw StateError('账户或恢复码不正确');
      final a = rows.first;
      final now = DateTime.now().millisecondsSinceEpoch;
      if ((a['lockedUntil'] as int) > now) throw StateError('请在 1 分钟后重试');
      if (!_equal(
        await _hash(code.trim().toUpperCase(), a['recoverySalt'] as String),
        a['recoveryHash'] as String,
      )) {
        final fails = (a['failures'] as int) + 1;
        await db.update(
          'accounts',
          {'failures': fails, 'lockedUntil': fails >= 5 ? now + 60000 : 0},
          where: 'id = ?',
          whereArgs: [a['id']],
        );
        throw StateError('账户或恢复码不正确');
      }
      final salt = _salt();
      final hash = await _hash(newPassword, salt);
      final next = Workspace.fromJson(data.toJson());
      next.audits.add(
        AuditEntry(
          uid(),
          a['name'] as String,
          '密码恢复',
          '通过本机恢复码重设密码',
          DateTime.now(),
          actorId: a['id'] as String,
          targets: [
            AuditTarget('account', a['id'] as String, a['username'] as String),
          ],
        ),
      );
      await db.transaction((tx) async {
        await tx.update(
          'accounts',
          {'salt': salt, 'hash': hash, 'failures': 0, 'lockedUntil': 0},
          where: 'id = ?',
          whereArgs: [a['id']],
        );
        await StateStorage.write(tx, 'workspace', jsonEncode(next.toJson()));
      });
      data = next;
      revision++;
    } finally {
      writing = false;
    }
  }

  Future<void> changePassword(String old, String next) async {
    _require();
    _password(next);
    final id = user!.id;
    final startedSession = session;
    final a = (await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [id],
    )).first;
    if (!_equal(await _hash(old, a['salt'] as String), a['hash'] as String)) {
      throw StateError('当前密码不正确');
    }
    final salt = _salt();
    final hash = await _hash(next, salt);
    requireSession(startedSession);
    await _commit(
      '修改密码',
      '已更新当前账户密码',
      (_) {},
      accountChange: (tx) async {
        await tx.update(
          'accounts',
          {'salt': salt, 'hash': hash},
          where: 'id = ?',
          whereArgs: [id],
        );
      },
    );
  }

  Future<void> _commit(
    String action,
    String detail,
    void Function(Workspace) edit, {
    bool elevated = false,
    bool owner = false,
    Iterable<AuditTarget> targets = const [],
    Iterable<AuditChange> changes = const [],
    String? operationId,
    Future<void> Function(Transaction)? accountChange,
    void Function()? onCommitted,
    int? expectedRevision,
  }) async {
    _require(elevated: elevated, owner: owner);
    if (expectedRevision != null && expectedRevision != revision) {
      throw StateError('工作区已发生变化，请重新查看预览后确认');
    }
    if (writing) throw StateError('正在保存，请稍后重试');
    writing = true;
    try {
      final next = Workspace.fromJson(data.toJson());
      edit(next);
      next.audits.add(
        AuditEntry(
          uid(),
          user!.name,
          action,
          detail,
          DateTime.now(),
          actorId: user!.id,
          targets: targets,
          changes: changes,
          operationId: operationId,
        ),
      );
      next.validate();
      await db.transaction((tx) async {
        if (accountChange != null) await accountChange(tx);
        await StateStorage.write(tx, 'workspace', jsonEncode(next.toJson()));
      });
      data = next;
      revision++;
      onCommitted?.call();
      await _loadUsers();
      if (user != null) user = users.firstWhere((u) => u.id == user!.id);
      feedback();
      notifyListeners();
    } finally {
      writing = false;
    }
  }

  Future<void> preference(String key, bool value) {
    _require();
    final startedSession = session;
    final operation = _preferenceWrites.then((_) async {
      requireSession(startedSession);
      final next = {...preferences, key: value};
      await db.transaction(
        (tx) => StateStorage.write(tx, 'preferences', jsonEncode(next)),
      );
      preferences = next;
      feedback();
      notifyListeners();
    });
    _preferenceWrites = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> rename(String name) async {
    _require();
    name = name.trim();
    if (name.isEmpty || name.length > 40) throw StateError('姓名需要 1–40 个字符');
    final id = user!.id;
    await _commit(
      '修改资料',
      '显示名称更新为 $name',
      (_) {},
      accountChange: (tx) async {
        await tx.update(
          'accounts',
          {'name': name},
          where: 'id = ?',
          whereArgs: [id],
        );
      },
    );
  }

  Future<void> updateUser(LocalUser target, String role, bool enabled) async {
    _require(owner: true);
    if (!['admin', 'engineer', 'operator'].contains(role)) {
      throw StateError('角色无效');
    }
    if (target.id == user!.id && (role != 'admin' || !enabled)) {
      throw StateError('不能撤销自己的管理员权限或停用自己');
    }
    await _commit(
      '更新账户权限',
      '${target.username} · ${roleName(role)} · ${enabled ? '启用' : '停用'}',
      (_) {},
      owner: true,
      targets: [
        AuditTarget(
          'account',
          target.id,
          '${target.name} · ${target.username}',
        ),
      ],
      accountChange: (tx) async {
        await tx.update(
          'accounts',
          {'role': role, 'enabled': enabled ? 1 : 0},
          where: 'id = ?',
          whereArgs: [target.id],
        );
      },
    );
  }

  Future<void> saveRecipe(Recipe recipe) async {
    await _commit(
      '保存配方',
      recipe.label,
      (w) {
        if (w.recipes.any(
          (r) =>
              r.id != recipe.id &&
              r.name == recipe.name &&
              r.version == recipe.version,
        )) {
          throw StateError('配方名称与版本已存在');
        }
        final i = w.recipes.indexWhere((r) => r.id == recipe.id);
        if (i < 0) {
          w.recipes.add(recipe);
        } else {
          w.recipes[i] = recipe;
        }
      },
      elevated: true,
      targets: [AuditTarget('recipe', recipe.id, recipe.label)],
      changes: _changes(
        data.recipes.where((r) => r.id == recipe.id).firstOrNull?.toJson() ??
            {},
        recipe.toJson(),
        const {
          'name': '配方名称',
          'version': '版本',
          'material': '材料',
          'sensitivity': '灵敏度（%）',
          'confidence': '置信度阈值',
          'defects': '启用缺陷',
        },
      ),
    );
  }

  Future<void> deleteRecipe(String id) => _commit(
    '删除配方',
    data.recipes.firstWhere((r) => r.id == id).label,
    (w) {
      if (w.stations.any((s) => s.recipeId == id)) {
        throw StateError('配方正在使用，请先为工位换型');
      }
      w.recipes.removeWhere((r) => r.id == id);
    },
    elevated: true,
    targets: [recipeTarget(id)],
  );
  Future<void> changeover(
    String stationId,
    String recipeId,
    String reason,
  ) => _commit(
    '配方换型',
    '${station(stationId).name} → ${recipe(recipeId).label} · ${reason.trim()}',
    (w) {
      if (reason.trim().length < 3 || reason.length > 500) {
        throw StateError('请填写 3–500 字的换型原因');
      }
      final s = w.stations.firstWhere((s) => s.id == stationId);
      if (s.recipeId == recipeId) throw StateError('该工位已使用此配方');
      s.recipeId = recipeId;
    },
    elevated: true,
    targets: [
      stationTarget(stationId),
      recipeTarget(recipeId),
      if (station(stationId).recipeId != recipeId)
        recipeTarget(station(stationId).recipeId),
    ],
    changes: [
      AuditChange(
        '当前配方',
        recipe(station(stationId).recipeId).label,
        recipe(recipeId).label,
      ),
    ],
  );
  Future<void> toggleStation(String id) => _commit(
    '工位状态',
    '${station(id).name} · ${station(id).running ? '暂停' : '启动'}',
    (w) {
      final s = w.stations.firstWhere((s) => s.id == id);
      s.running = !s.running;
    },
    targets: [stationTarget(id)],
  );
  Recipe recipe(String id) => data.recipes.firstWhere((r) => r.id == id);
  Station station(String id) => data.stations.firstWhere((s) => s.id == id);
  AuditTarget recipeTarget(String id) =>
      AuditTarget('recipe', id, recipe(id).label);
  AuditTarget stationTarget(String id) =>
      AuditTarget('station', id, '${station(id).line} · ${station(id).name}');
  AuditTarget recordTarget(Inspection record) =>
      AuditTarget('record', record.id, record.serial);
  List<AuditChange> _changes(
    Json before,
    Json after,
    Map<String, String> labels,
  ) {
    String display(Object? value) => value == null
        ? '未设置'
        : value is List
        ? value.join('、')
        : '$value';
    return [
      for (final entry in labels.entries)
        if (display(before[entry.key]) != display(after[entry.key]))
          AuditChange(
            entry.value,
            display(before[entry.key]),
            display(after[entry.key]),
          ),
    ];
  }

  List<AuditEntry> history(String type, String id, {String? legacySerial}) =>
      data.audits.reversed
          .where((a) => a.relatesTo(type, id, legacySerial: legacySerial))
          .toList();
  Future<void> saveStation(Station station) => _commit(
    '配置工位',
    '${station.line} · ${station.name}',
    (w) {
      if (w.stations.any(
        (s) =>
            s.id != station.id &&
            s.name == station.name &&
            s.line == station.line,
      )) {
        throw StateError('这条产线上已存在同名工位');
      }
      final index = w.stations.indexWhere((s) => s.id == station.id);
      if (index < 0) {
        w.stations.add(station);
      } else {
        if (station.recipeId != w.stations[index].recipeId) {
          throw StateError('更换配方请使用工位换型');
        }
        w.stations[index].name = station.name;
        w.stations[index].line = station.line;
      }
    },
    elevated: true,
    targets: [
      AuditTarget('station', station.id, '${station.line} · ${station.name}'),
      recipeTarget(station.recipeId),
    ],
    changes: _changes(
      data.stations.where((s) => s.id == station.id).firstOrNull?.toJson() ??
          {},
      station.toJson(),
      const {'name': '工位名称', 'line': '产线'},
    ),
  );
  Future<void> deleteStation(String id) => _commit(
    '删除工位',
    '${station(id).line} · ${station(id).name}',
    (w) {
      if (w.stations.length == 1) throw StateError('至少保留一个工位');
      if (w.inspections.any((r) => r.stationId == id)) {
        throw StateError('工位关联了检测记录，请保留工位以便追溯');
      }
      if (w.stations.firstWhere((s) => s.id == id).running) {
        throw StateError('请先暂停工位');
      }
      w.stations.removeWhere((s) => s.id == id);
    },
    elevated: true,
    targets: [stationTarget(id)],
  );
  Future<String> simulate(String stationId) async {
    _require();
    final s = station(stationId), r = recipe(s.recipeId);
    if (!s.running) throw StateError('请先启动工位');
    final random = Random();
    final failed = random.nextDouble() < (.08 + r.sensitivity / 700);
    final record = Inspection(
      id: uid(),
      stationId: s.id,
      recipeName: r.label,
      recipeSnapshot: Recipe.fromJson(r.toJson()).toJson(),
      serial: 'SIM-${DateTime.now().millisecondsSinceEpoch}',
      at: DateTime.now(),
      passed: !failed,
      defect: failed ? r.defects[random.nextInt(r.defects.length)] : '',
      confidence: r.confidence + random.nextDouble() * (1 - r.confidence),
      operatorName: user!.name,
    );
    await _commit(
      '模拟检测',
      '${s.name} · ${record.serial} · ${failed ? '不合格' : '合格'}',
      (w) => w.inspections.add(record),
      targets: [recordTarget(record), stationTarget(s.id), recipeTarget(r.id)],
    );
    return record.id;
  }

  Future<void> review(String id, String verdict, String note) => _commit(
    '质量复核',
    '$id · ${verdict == 'pass' ? '放行' : '判退'} · ${note.trim()}',
    (w) {
      if (!['pass', 'reject'].contains(verdict) ||
          note.trim().length < 3 ||
          note.length > 2000) {
        throw StateError('请选择结果并填写 3–2000 字的复核依据');
      }
      final r = w.inspections.firstWhere((r) => r.id == id);
      if (r.archived) throw StateError('请先恢复已归档记录');
      r.review = verdict;
      r.note = note.trim();
      r.reviewer = user!.name;
      r.reviewedAt = DateTime.now();
    },
    elevated: true,
    targets: [recordTarget(data.inspections.firstWhere((r) => r.id == id))],
    changes: _reviewChanges(id, verdict, note),
  );
  List<AuditChange> _reviewChanges(String id, String verdict, String note) {
    final record = data.inspections.firstWhere((r) => r.id == id);
    String label(String? v) => v == null
        ? '未复核'
        : v == 'pass'
        ? '放行'
        : '判退';
    return _changes(
      {'review': label(record.review), 'note': record.note},
      {'review': label(verdict), 'note': note.trim()},
      const {'review': '复核结论', 'note': '复核依据'},
    );
  }

  Future<void> archive(Set<String> ids, bool archived) async {
    _require(elevated: true);
    final records = data.inspections.where((r) => ids.contains(r.id)).toList();
    if (ids.isEmpty || records.length != ids.length) {
      throw StateError('所选记录已发生变化，请重新选择');
    }
    final changed = records.where((r) => r.archived != archived).toList();
    if (changed.isEmpty) throw StateError('所选记录已处于目标状态');
    await _commit(
      archived ? '归档记录' : '恢复记录',
      '${changed.length} 条记录',
      (w) {
        if (archived &&
            w.inspections.any((r) => ids.contains(r.id) && r.pending)) {
          throw StateError('请先完成异常记录的复核');
        }
        for (final r in w.inspections.where((r) => ids.contains(r.id))) {
          r.archived = archived;
        }
      },
      elevated: true,
      targets: changed.map(recordTarget),
    );
  }

  String backup() {
    _require(elevated: true);
    return BackupDocument.encode(data);
  }

  Workspace parseBackup(String source) {
    final document = BackupDocument.parse(source);
    if (!document.readyToRestore) {
      throw const FormatException('旧备份缺少时区，请在恢复预览中选择时间解释方式');
    }
    return document.workspace;
  }

  Future<void> restoreDocument(
    BackupDocument document, {
    int? expectedRevision,
  }) {
    _require(owner: true);
    if (!document.readyToRestore) throw StateError('请先选择旧备份的时间解释方式');
    return restore(
      document.workspace,
      expectedRevision: expectedRevision,
      timeInterpretation: document.timeInterpretation,
    );
  }

  Future<void> restore(
    Workspace incoming, {
    int? expectedRevision,
    String? timeInterpretation,
  }) async {
    _require(owner: true);
    final point = RestorePointInfo.capture(data, user!.name);
    // Own the incoming objects so a preview or caller cannot mutate committed data.
    final restored = Workspace.fromJson(incoming.toJson());
    await _commit(
      '恢复备份',
      '导入 ${restored.inspections.length} 条记录；原操作日志保留'
          '${timeInterpretation == null ? '' : '；旧时间解释：$timeInterpretation'}',
      (w) {
        restored.validate();
        final audits = {
          for (final a in restored.audits) a.id: a,
          for (final a in w.audits) a.id: a,
        };
        w.recipes = restored.recipes;
        w.stations = restored.stations;
        w.inspections = restored.inspections;
        w.audits = audits.values.toList()..sort((a, b) => a.at.compareTo(b.at));
      },
      owner: true,
      expectedRevision: expectedRevision,
      onCommitted: () => restorePoint = point,
      accountChange: (tx) async {
        await StateStorage.write(tx, 'restorePoint', jsonEncode(data.toJson()));
        await StateStorage.write(
          tx,
          'restorePointMeta',
          jsonEncode(point.toJson()),
        );
      },
    );
  }

  Future<Workspace> readRestorePoint(String expectedId) async {
    _require(owner: true);
    final startedSession = session;
    if (restorePoint?.id != expectedId) throw StateError('还原点已更新，请重新打开预览');
    final source = await db.transaction(
      (tx) => StateStorage.read(tx, 'restorePoint'),
    );
    requireSession(startedSession, owner: true);
    if (restorePoint?.id != expectedId) throw StateError('还原点已更新，请重新打开预览');
    if (source == null) throw StateError('还没有可撤回的恢复操作');
    final previous = Workspace.fromJson(jsonDecode(source));
    previous.validate();
    return previous;
  }

  Future<void> undoRestore({
    int? expectedRevision,
    String? expectedPointId,
  }) async {
    _require(owner: true);
    final startedSession = session;
    final startedRevision = expectedRevision ?? revision;
    final pointId = expectedPointId ?? restorePoint?.id;
    if (pointId == null) throw StateError('还没有可撤回的恢复操作');
    final previous = await readRestorePoint(pointId);
    requireSession(startedSession, owner: true);
    await _commit(
      '撤回恢复',
      '业务数据已还原为上一次恢复前的状态',
      (w) {
        w.recipes = previous.recipes;
        w.stations = previous.stations;
        w.inspections = previous.inspections;
      },
      owner: true,
      expectedRevision: startedRevision,
      onCommitted: () => restorePoint = null,
      accountChange: (tx) async {
        await StateStorage.remove(tx, 'restorePoint');
        await StateStorage.remove(tx, 'restorePointMeta');
      },
    );
  }

  Future<void> clearExamples() => _commit(
    '清理示例',
    '移除模拟和示例记录，保留审计日志',
    (w) => w.inspections.removeWhere((r) => r.sample),
    owner: true,
    targets: data.inspections.where((r) => r.sample).map(recordTarget),
  );
  Future<void> loadExamples() {
    final seed = Workspace.seed();
    for (final r in seed.inspections) {
      r.id = uid();
    }
    return _commit(
      '添加示例',
      '补充 96 条示例检测记录',
      (w) {
        for (final r in seed.inspections) {
          r.stationId = w.stations[w.inspections.length % w.stations.length].id;
          w.inspections.add(r);
        }
      },
      owner: true,
      targets: seed.inspections.map(recordTarget),
    );
  }

  CsvSnapshot captureCsv(Iterable<Inspection> records) {
    _require(elevated: true);
    return CsvSnapshot(records, {for (final s in data.stations) s.id: s.name});
  }

  // Compatibility helper for small in-memory callers; UI exports use a worker.
  String csv(Iterable<Inspection> records) =>
      csvChunks(captureCsv(records)).join();

  Future<void> exportLogged(String kind, int count) =>
      _commit('导出数据', '$kind · $count 条记录', (_) {}, elevated: true);

  Future<ExportTicket> beginExport(
    String kind,
    int count, {
    Iterable<AuditTarget> targets = const [],
    String? reference,
  }) async {
    _require(elevated: true);
    if (_exports.isNotEmpty) throw StateError('请先完成当前文件导出');
    if (count < 0 || count > 100000) throw StateError('导出记录数无效');
    if (reference != null && reference.length > 255) {
      throw StateError('导出关联说明过长');
    }
    final ticket = ExportTicket._(
      uid(),
      user!,
      kind,
      count,
      session,
      targets,
      reference: reference,
    );
    await _commit(
      '开始导出',
      '$kind · ${kind == '恢复前原件' ? '原始存储' : '$count 条记录'}${reference == null ? '' : ' · $reference'} · 准备文件并等待保存结果',
      (_) {},
      elevated: true,
      targets: ticket.targets,
      operationId: ticket.id,
    );
    _exports[ticket.id] = ticket;
    return ticket;
  }

  Future<void> finishExport(
    ExportTicket ticket,
    ExportOutcome outcome, {
    int? fileBytes,
    String? fileSha256,
  }) async {
    // Waiting here serializes the audit with an in-flight business transaction.
    // The ticket's actor is fixed even if the session locked or another user logged in.
    while (writing) {
      await _writeFinished!.future;
    }
    if (!identical(_exports[ticket.id], ticket)) {
      throw StateError('导出操作已结束或不是本机发起');
    }
    writing = true;
    try {
      if (['LSB 备份', '恢复前原件', 'CSV'].contains(ticket.kind) &&
          outcome == ExportOutcome.saved &&
          (fileBytes == null ||
              fileBytes <= 0 ||
              fileBytes > maxArchiveBytes ||
              fileSha256 == null ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(fileSha256))) {
        throw StateError('缺少文件保存校验信息');
      }
      final receipt =
          ['JSON 备份', 'LSB 备份'].contains(ticket.kind) &&
              outcome == ExportOutcome.saved
          ? BackupReceipt(
              ticket.actor,
              ticket.id,
              DateTime.now(),
              ticket.count,
              format: ticket.kind == 'LSB 备份' ? 'LSB 2' : 'JSON',
              bytes: fileBytes,
              sha256: fileSha256,
            )
          : null;
      final action = switch (outcome) {
        ExportOutcome.saved => '导出数据',
        ExportOutcome.cancelled => '取消导出',
        ExportOutcome.failed => '导出未完成',
      };
      final result = switch (outcome) {
        ExportOutcome.saved =>
          ['LSB 备份', '恢复前原件', 'CSV'].contains(ticket.kind)
              ? '文件已保存并回读校验通过'
              : '文件选择器已确认保存',
        ExportOutcome.cancelled => '未保存文件',
        ExportOutcome.failed => '文件选择器未确认保存，请检查目标位置',
      };
      final next = Workspace.fromJson(data.toJson());
      next.audits.add(
        AuditEntry(
          uid(),
          ticket.actor,
          action,
          '${ticket.kind} · ${ticket.kind == '恢复前原件' ? '原始存储' : '${ticket.count} 条记录'}${ticket.reference == null ? '' : ' · ${ticket.reference}'} · $result',
          DateTime.now(),
          actorId: ticket.actorId,
          targets: ticket.targets,
          operationId: ticket.id,
          changes: ticket.kind == 'CSV' && outcome == ExportOutcome.saved
              ? [
                  AuditChange('文件字节数', '', '$fileBytes'),
                  AuditChange('SHA-256', '', fileSha256!),
                ]
              : const [],
        ),
      );
      next.validate();
      await db.transaction((tx) async {
        await StateStorage.write(tx, 'workspace', jsonEncode(next.toJson()));
        if (receipt != null) {
          await StateStorage.write(
            tx,
            'backupReceipt',
            jsonEncode(receipt.toJson()),
          );
        }
      });
      data = next;
      revision++;
      if (receipt != null) lastBackup = receipt;
    } finally {
      _exports.remove(ticket.id);
      writing = false;
    }
    notifyListeners();
  }
}
