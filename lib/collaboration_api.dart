import 'service_transport.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

const defaultCollaborationApi = String.fromEnvironment(
  'LINESIGHT_API_BASE_URL',
  defaultValue: 'https://99ai.pronhubcn.com/api/v1/',
);

class CollaborationSession {
  static String? token;
  static String? serviceUrl;
  static void clear() {
    token = null;
    serviceUrl = null;
  }
}

class CollaborationApiException implements Exception {
  final int status;
  final String message;
  final Map<String, dynamic>? details;
  const CollaborationApiException(this.status, this.message, {this.details});
  @override
  String toString() => message;
}

class CollaborationApi {
  final Uri baseUri;
  final String? token;
  CollaborationApi(String baseUrl, {this.token})
    : baseUri = _normalize(baseUrl);

  static Uri _normalize(String value) {
    final parsed = Uri.parse(value.trim());
    if (!parsed.hasScheme ||
        parsed.host.isEmpty ||
        !const {'http', 'https'}.contains(parsed.scheme)) {
      throw const FormatException('请输入有效的 HTTP 或 HTTPS 服务地址');
    }
    if (!kDebugMode && parsed.scheme != 'https') {
      throw const FormatException('团队服务需要使用 HTTPS');
    }
    final path = parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/';
    return parsed.replace(path: path);
  }

  Uri _uri(String path) => baseUri.resolve(path);

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    final client = serviceHttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, _uri(path));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set('X-LineSight-Features', 'workspace-bulletins-v1');
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (idempotencyKey != null) {
        req.headers.set('Idempotency-Key', idempotencyKey);
      }
      if (body != null) {
        final payload = utf8.encode(jsonEncode(body));
        req.headers.contentType = ContentType.json;
        req.contentLength = payload.length;
        req.add(payload);
      }
      final res = await req.close().timeout(const Duration(seconds: 25));
      final text = await utf8.decoder.bind(res).join();
      dynamic decoded;
      if (text.isNotEmpty) {
        try {
          decoded = jsonDecode(text);
        } catch (_) {
          decoded = text;
        }
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final message = decoded is Map && decoded.isNotEmpty
            ? '${decoded['detail'] ?? decoded.values.first}'
            : 'Request failed';
        throw CollaborationApiException(
          res.statusCode,
          message,
          details: decoded is Map ? Map<String, dynamic>.from(decoded) : null,
        );
      }
      return decoded;
    } on SocketException {
      throw const CollaborationApiException(0, '无法连接服务，请检查地址和网络后重试');
    } on HttpException {
      throw const CollaborationApiException(0, '连接中断，请重试');
    } on TimeoutException {
      throw const CollaborationApiException(0, '连接超时，请重试');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> register(
    String username,
    String password,
  ) async => Map<String, dynamic>.from(
    await request(
      'POST',
      'auth/register/',
      body: {'username': username, 'password': password},
    ),
  );
  Future<String> login(String username, String password) async =>
      (await request(
            'POST',
            'auth/login/',
            body: {'username': username, 'password': password},
          ))['access']
          as String;
  Future<List<Map<String, dynamic>>> workspaces() async =>
      (await request('GET', 'workspaces/')).cast<Map<String, dynamic>>();
  Future<List<Map<String, dynamic>>> members(int workspaceId) async =>
      (await request(
        'GET',
        'workspaces/$workspaceId/members/',
      )).cast<Map<String, dynamic>>();
  Future<void> changeMemberRole(
    int workspaceId,
    String username,
    String role,
  ) async => request(
    'PATCH',
    'workspaces/$workspaceId/members/${Uri.encodeComponent(username)}/',
    body: {'role': role},
  );
  Future<void> removeMember(int workspaceId, String username) async => request(
    'DELETE',
    'workspaces/$workspaceId/members/${Uri.encodeComponent(username)}/',
  );
  Future<void> leaveWorkspace(int workspaceId) async =>
      request('POST', 'workspaces/$workspaceId/leave/');
  Future<List<Map<String, dynamic>>> printerProfiles(int workspaceId) async =>
      (await request(
        'GET',
        'workspaces/$workspaceId/printer-profiles/',
      )).cast<Map<String, dynamic>>();
  Future<Map<String, dynamic>> savePrinterProfile(
    int workspaceId,
    Map<String, dynamic> profile,
  ) async => Map<String, dynamic>.from(
    await request(
      'POST',
      'workspaces/$workspaceId/printer-profiles/',
      body: profile,
    ),
  );
  Future<Map<String, dynamic>> legacyInspectionStats(int workspaceId) async =>
      Map<String, dynamic>.from(
        await request('GET', 'workspaces/$workspaceId/legacy-inspections/'),
      );
  Future<Map<String, dynamic>> importLegacyInspections(
    int workspaceId,
    List<Map<String, dynamic>> records, {
    required bool includeSamples,
    VoidCallback? authorizeLocal,
  }) async {
    var imported = 0, skipped = 0;
    var batch = <Map<String, dynamic>>[];
    var bytes = 0;
    Future<void> sendBatch() async {
      if (batch.isEmpty) return;
      authorizeLocal?.call();
      final result = Map<String, dynamic>.from(
        await request(
          'POST',
          'workspaces/$workspaceId/legacy-inspections/',
          body: {'records': batch, 'include_samples': includeSamples},
        ),
      );
      imported += result['imported'] as int;
      skipped += result['skipped'] as int;
      batch = [];
      bytes = 0;
    }

    for (final record in records) {
      final size = utf8.encode(jsonEncode(record)).length;
      if (size > 3 * 1024 * 1024) throw const FormatException('单条记录超过导入限制，未上传');
      if (batch.isNotEmpty && bytes + size > 3 * 1024 * 1024) await sendBatch();
      batch.add(record);
      bytes += size;
    }
    await sendBatch();
    return {'imported': imported, 'skipped': skipped};
  }

  Future<Map<String, dynamic>> createWorkspace(String name) async =>
      Map<String, dynamic>.from(
        await request('POST', 'workspaces/create/', body: {'name': name}),
      );
  Future<Map<String, dynamic>> redeem(String code) async =>
      Map<String, dynamic>.from(
        await request('POST', 'workspaces/redeem/', body: {'code': code}),
      );
  Future<String> invite(int workspaceId, String role) async =>
      (await request(
            'POST',
            'workspaces/$workspaceId/invite/',
            body: {'role': role},
          ))['code']
          as String;
  Future<List<Map<String, dynamic>>> jobs(int workspaceId) async =>
      (await request(
        'GET',
        'workspaces/$workspaceId/jobs/',
      )).cast<Map<String, dynamic>>();
  Future<Map<String, dynamic>> createJob(
    int workspaceId,
    Map<String, dynamic> fields,
    String requestId,
  ) async => Map<String, dynamic>.from(
    await request(
      'POST',
      'workspaces/$workspaceId/jobs/',
      body: fields,
      idempotencyKey: requestId,
    ),
  );
  Future<Map<String, dynamic>> updateJob(
    int workspaceId,
    String id,
    String status,
  ) async => Map<String, dynamic>.from(
    await request(
      'PATCH',
      'workspaces/$workspaceId/jobs/$id/',
      body: {'status': status},
    ),
  );
  Future<Map<String, dynamic>> qualityDecision(
    int workspaceId,
    String jobId, {
    required String verdict,
    String note = '',
    String assignee = '',
  }) async => Map<String, dynamic>.from(
    await request(
      'POST',
      'workspaces/$workspaceId/jobs/$jobId/inspection/',
      body: {'verdict': verdict, 'note': note, 'assignee': assignee},
    ),
  );
  Future<void> createException(
    int workspaceId,
    String jobId,
    String note, {
    String assignee = '',
  }) async => request(
    'POST',
    'workspaces/$workspaceId/jobs/$jobId/exceptions/',
    body: {'note': note, 'assignee': assignee},
  );
  Future<void> resolveException(
    int workspaceId,
    int caseId,
    String resolution,
    String nextStatus,
  ) async => request(
    'POST',
    'workspaces/$workspaceId/exceptions/$caseId/resolve/',
    body: {'resolution': resolution, 'next_status': nextStatus},
  );

  Future<void> uploadImage(
    int workspaceId,
    String jobId,
    String fileName,
    List<int> bytes,
  ) async {
    final boundary = 'LineSight${DateTime.now().microsecondsSinceEpoch}';
    final client = serviceHttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(
        _uri('workspaces/$workspaceId/jobs/$jobId/evidence/'),
      );
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      req.headers.set(
        'Idempotency-Key',
        sha256
            .convert(utf8.encode('$jobId:${sha256.convert(bytes)}'))
            .toString(),
      );
      final header = utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="image"; filename="${fileName.replaceAll('"', '')}"\r\nContent-Type: application/octet-stream\r\n\r\n',
      );
      final footer = utf8.encode('\r\n--$boundary--\r\n');
      req.contentLength = header.length + bytes.length + footer.length;
      req.add(header);
      req.add(bytes);
      req.add(footer);
      final res = await req.close().timeout(const Duration(seconds: 60));
      final text = await utf8.decoder.bind(res).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final data = text.isEmpty ? null : jsonDecode(text);
        throw CollaborationApiException(
          res.statusCode,
          data is Map
              ? '${data['detail'] ?? 'Upload failed'}'
              : 'Upload failed',
        );
      }
    } on SocketException {
      throw const CollaborationApiException(0, '上传失败，检查连接后可重试');
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> preview(
    int workspaceId,
    String jobId,
    int evidenceId,
  ) async {
    final client = serviceHttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(
        _uri(
          'workspaces/$workspaceId/jobs/$jobId/evidence/$evidenceId/preview/',
        ),
      );
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final res = await req.close().timeout(const Duration(seconds: 25));
      final bytes = await res.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw CollaborationApiException(res.statusCode, '无法打开图片证据');
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> original(
    int workspaceId,
    String jobId,
    int evidenceId,
  ) async {
    final client = serviceHttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(
        _uri(
          'workspaces/$workspaceId/jobs/$jobId/evidence/$evidenceId/original/',
        ),
      );
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final res = await req.close().timeout(const Duration(seconds: 25));
      final bytes = await res.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw CollaborationApiException(res.statusCode, '无法打开图片证据');
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }
}
