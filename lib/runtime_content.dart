import 'service_transport.dart';
import 'presentation/presentation_config.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'collaboration_api.dart';
import 'ota_key.dart';
import 'runtime_defaults.dart';

class RuntimeContent extends ChangeNotifier {
  RuntimeContent();
  static final instance = RuntimeContent();
  static const _storage = FlutterSecureStorage();
  static const _cacheKey = 'linesight.public-config.v1';
  Map<String, dynamic> data = Map.of(defaultRuntimeContent);
  List<Map<String, dynamic>> get documents => (data['documents'] as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
  Map<String, dynamic> get report =>
      Map<String, dynamic>.from(data['report'] as Map);
  int get revision => data['revision'] as int;
  bool feature(String name) => (data['features'] as Map?)?[name] != false;
  bool _busy = false;

  static Future<Map<String, dynamic>> verify(
    List<int> bytes, {
    List<int>? publicKey,
    DateTime? now,
    int minimumRevision = 1,
  }) async {
    if (bytes.length > 256 * 1024) throw const FormatException('Config size');
    final outer = jsonDecode(utf8.decode(bytes)) as Map;
    final payload = base64Decode(outer['payload'] as String);
    final valid = await Ed25519().verify(
      payload,
      signature: Signature(
        base64Decode(outer['signature'] as String),
        publicKey: SimplePublicKey(
          publicKey ?? base64Decode(otaPublicKey),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) throw const FormatException('Config signature');
    final value = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    if (value['schema'] != 1 ||
        value['revision'] is! int ||
        value['revision'] < minimumRevision ||
        DateTime.parse(
          value['expires'] as String,
        ).isBefore(now ?? DateTime.now()) ||
        value['documents'] is! List ||
        (value['documents'] as List).length > 30 ||
        value['report'] is! Map) {
      throw const FormatException('Config schema');
    }
    if (value['features'] is! Map ||
        (value['features'] as Map).values.any((flag) => flag is! bool) ||
        value['special'] is! Map ||
        value['special']['title'] is! String ||
        (value['special']['title'] as String).length > 80 ||
        !RegExp(
          r'^#[a-fA-F0-9]{6}$',
        ).hasMatch('${value['special']['accent']}')) {
      throw const FormatException('Feature schema');
    }
    PresentationConfig.validate(value['presentation']);
    final ids = <String>{};
    for (final document in value['documents'] as List) {
      if (document is! Map ||
          !RegExp(r'^[a-z0-9-]{1,48}$').hasMatch('${document['id']}') ||
          !ids.add(document['id'] as String) ||
          document['title'] is! String ||
          document['code'] is! String ||
          document['version'] is! String ||
          [
            'title',
            'code',
            'version',
            'department',
            'scope',
            'disposition',
          ].any(
            (name) =>
                document[name] is! String ||
                (document[name] as String).length > 1000,
          ) ||
          document['preparation'] is! List ||
          (document['preparation'] as List).length > 30 ||
          (document['preparation'] as List).any(
            (row) =>
                row is! List ||
                row.length != 2 ||
                row.any((cell) => cell is! String || cell.length > 1000),
          ) ||
          document['sections'] is! List ||
          (document['sections'] as List).length > 20 ||
          !{
            'aluminum_housing_inspection.png',
            'changeover_checklist.png',
          }.contains(document['asset'])) {
        throw const FormatException('Document schema');
      }
      final itemIds = <String>{};
      for (final section in document['sections'] as List) {
        if (section is! Map ||
            section['title'] is! String ||
            section['items'] is! List ||
            (section['items'] as List).length > 100 ||
            (section['items'] as List).any(
              (row) =>
                  row is! List ||
                  row.length != 3 ||
                  row.any((cell) => cell is! String || cell.length > 1000),
            )) {
          throw const FormatException('Document rows');
        }
        for (final row in section['items'] as List) {
          if (!itemIds.add(row[0] as String)) {
            throw const FormatException('Duplicate check id');
          }
        }
      }
      if (document['image_url'] != null) assetUri(document);
    }
    for (final name in [
      'organization',
      'department',
      'signature',
      'document_code',
      'version',
    ]) {
      if (value['report'][name] is! String ||
          (value['report'][name] as String).length > 120) {
        throw const FormatException('Report branding');
      }
    }
    if (value['report']['image_url'] != null) assetUri(value['report']);
    return value;
  }

  static Uri assetUri(Map reference) {
    final origin = Uri.parse(defaultCollaborationApi);
    final uri = origin.resolve(reference['image_url'] as String);
    if (uri.scheme != 'https' ||
        uri.host != origin.host ||
        uri.port != origin.port ||
        !RegExp(r'^/content/[a-f0-9]{64}\.png$').hasMatch(uri.path) ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch('${reference['sha256']}')) {
      throw const FormatException('Asset origin or digest');
    }
    return uri;
  }

  static Future<Uint8List> _read(Uri uri, int limit) async {
    final client = serviceHttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200 || response.contentLength > limit) {
        throw const HttpException('Public content unavailable');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final part in response.timeout(const Duration(seconds: 15))) {
        bytes.add(part);
        if (bytes.length > limit) {
          throw const FormatException('Public content size');
        }
      }
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> initialize() async {
    try {
      final saved = await _storage.read(key: _cacheKey);
      if (saved != null) {
        final value = await verify(utf8.encode(saved));
        if (value['revision'] >= revision) data = value;
      }
    } catch (_) {
      /* Keep bundled content if a cache is absent or invalid. */
    }
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final raw = await _read(
        Uri.parse(defaultCollaborationApi).resolve('app-config/'),
        256 * 1024,
      );
      final value = await verify(raw, minimumRevision: revision);
      if (value['revision'] <= revision) return;
      await _storage.write(key: _cacheKey, value: utf8.decode(raw));
      data = value;
      notifyListeners();
    } catch (_) {
      /* Offline sessions keep the last verified content. */
    } finally {
      _busy = false;
    }
  }

  Future<Uint8List> image(Map reference, {required String fallback}) async {
    if (reference['image_url'] != null) {
      try {
        final uri = assetUri(reference);
        final digest = reference['sha256'] as String;
        final folder = Directory(
          '${Directory.systemTemp.path}/linesight-public-content',
        );
        await folder.create(recursive: true);
        final file = File('${folder.path}/$digest.png');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.length <= 8 * 1024 * 1024 &&
              sha256.convert(bytes).toString() == digest) {
            return bytes;
          }
        }
        final bytes = await _read(uri, 8 * 1024 * 1024);
        if (sha256.convert(bytes).toString() != digest) {
          throw const FormatException('Asset digest');
        }
        await file.writeAsBytes(bytes, flush: true);
        return bytes;
      } catch (_) {
        /* Bundled document remains available. */
      }
    }
    return (await rootBundle.load(fallback)).buffer.asUint8List();
  }
}
