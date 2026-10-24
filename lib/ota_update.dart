import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_patcher/flutter_patcher.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'collaboration_api.dart';
import 'ota_key.dart';
import 'runtime_errors.dart';

const otaTrack = String.fromEnvironment(
  'LINESIGHT_OTA_TRACK',
  defaultValue: 'preview',
);
const otaRevision = String.fromEnvironment(
  'LINESIGHT_OTA_REVISION',
  defaultValue: '0',
);

/// Signed bytes are verified before parsing; metadata binds both code and target.
class OtaManifest {
  final Map<String, dynamic> data;
  OtaManifest._(this.data);
  int get sequence => data['sequence'] as int;
  String get version => 'ota-$sequence';
  String get digest => data['sha256'] as String;
  int get size => data['size'] as int;
  bool get rollback => data['action'] == 'rollback';

  static Future<OtaManifest> verify(
    List<int> envelope, {
    required List<int> publicKey,
    required String track,
    required int base,
    required String abi,
    required int minimumSequence,
    DateTime? now,
  }) async {
    if (envelope.length > 16384) throw const FormatException('manifest size');
    final outer = jsonDecode(utf8.decode(envelope)) as Map<String, dynamic>;
    final bytes = base64Decode(outer['payload'] as String);
    final valid = await Ed25519().verify(
      bytes,
      signature: Signature(
        base64Decode(outer['signature'] as String),
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!valid) throw const FormatException('manifest signature');
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (data['schema'] != 1 ||
        data['track'] != track ||
        data['base'] != base ||
        data['abi'] != abi ||
        data['sequence'] is! int ||
        (data['sequence'] as int) <= minimumSequence ||
        !{'patch', 'rollback'}.contains(data['action']) ||
        DateTime.parse(
          data['expires'] as String,
        ).isBefore(now ?? DateTime.now())) {
      throw const FormatException('manifest target or sequence');
    }
    if (data['action'] == 'patch' &&
        (data['sha256'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['sha256'] as String) ||
            data['size'] is! int ||
            (data['size'] as int) < 1 ||
            (data['size'] as int) > 64 * 1024 * 1024)) {
      throw const FormatException('payload metadata');
    }
    return OtaManifest._(data);
  }
}

enum OtaStatus {
  idle,
  checking,
  downloading,
  current,
  ready,
  offline,
  rejected,
  unavailable,
}

class OtaUpdates extends ChangeNotifier {
  OtaUpdates._();
  static final instance = OtaUpdates._();
  static const _storage = FlutterSecureStorage();
  OtaStatus status = OtaStatus.idle;
  String? runningPatch, pendingPatch;
  DateTime? checkedAt;
  int? base;
  String? abi;
  bool _busy = false;
  bool _initialized = false;
  double? progress;

  Future<void> initialize() async {
    if (_initialized || !Platform.isAndroid || !kReleaseMode) {
      return;
    }
    _initialized = true;
    try {
      await FlutterPatcher.init(maxCrashCount: 1);
      base = await FlutterPatcher.appVersionCode;
      abi = await FlutterPatcher.deviceAbi;
      runningPatch = await FlutterPatcher.currentVersion;
    } catch (_) {
      status = OtaStatus.unavailable;
    } finally {
      // flutter_patcher installs boot hooks that send error.toString() to
      // Android. Preserve its rollback signal without forwarding private data.
      sanitizeInstalledRuntimeErrorHandlers();
    }
  }

  Future<Uint8List> _read(Uri uri, int limit, {bool payload = false}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      if (uri.scheme != 'https') throw const FormatException('HTTPS required');
      final req = await client.getUrl(uri);
      req.followRedirects = false;
      final response = await req.close().timeout(const Duration(seconds: 20));
      if (!payload && response.statusCode == 204) return Uint8List(0);
      if (response.statusCode != 200 || response.contentLength > limit) {
        throw const HttpException('OTA unavailable');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        if (bytes.length + chunk.length > limit) {
          throw const FormatException('payload size');
        }
        bytes.add(chunk);
        if (payload) {
          progress = bytes.length / limit;
          notifyListeners();
        }
      }
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> check() async {
    if (_busy) return;
    if (!Platform.isAndroid || !kReleaseMode) {
      status = OtaStatus.unavailable;
      notifyListeners();
      return;
    }
    _busy = true;
    status = OtaStatus.checking;
    progress = null;
    notifyListeners();
    try {
      await initialize();
      if (base == null || abi == null) throw StateError('OTA unavailable');
      final root = Uri.parse(
        defaultCollaborationApi,
      ).resolve('ota/$otaTrack/$base/$abi/');
      final envelope = await _read(root.resolve('manifest.json'), 16384);
      if (envelope.isEmpty) {
        status = pendingPatch != null ? OtaStatus.ready : OtaStatus.current;
        return;
      }
      final sequenceKey = 'linesight.ota.$otaTrack.$base.sequence';
      final seen =
          int.tryParse(await _storage.read(key: sequenceKey) ?? '') ?? 0;
      // Repeated signed manifests are normal. Still verify them, then no-op.
      final manifest = await OtaManifest.verify(
        envelope,
        publicKey: base64Decode(otaPublicKey),
        track: otaTrack,
        base: base!,
        abi: abi!,
        minimumSequence: -1,
      );
      if (manifest.sequence <= seen) {
        status = pendingPatch != null ? OtaStatus.ready : OtaStatus.current;
        return;
      }
      if (manifest.rollback) {
        await FlutterPatcher.rollback();
      } else {
        final blocked = await FlutterPatcher.blacklist;
        if (blocked.any((entry) => entry.version == manifest.version)) {
          status = OtaStatus.rejected;
          return;
        }
        status = OtaStatus.downloading;
        notifyListeners();
        final bytes = await _read(
          root.resolve('${manifest.digest}.so'),
          manifest.size,
          payload: true,
        );
        if (bytes.length != manifest.size ||
            hashes.sha256.convert(bytes).toString() != manifest.digest) {
          throw const FormatException('payload digest');
        }
        final result = await FlutterPatcher.applyPatchBytes(
          bytes,
          version: manifest.version,
          targetVersionCode: base,
        );
        if (!result.ok) throw StateError('patch installation rejected');
      }
      await _storage.write(key: sequenceKey, value: '${manifest.sequence}');
      pendingPatch = manifest.rollback ? '0' : manifest.version;
      status = OtaStatus.ready;
    } on FormatException {
      status = OtaStatus.rejected;
    } catch (_) {
      status = OtaStatus.offline;
    } finally {
      checkedAt = DateTime.now();
      _busy = false;
      notifyListeners();
    }
  }
}
