import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/collaboration_api.dart';

void main() {
  test(
    'empty JSON and HTML errors retain their HTTP status for recovery',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = request.uri.path.contains('empty')
            ? 403
            : 502;
        request.response.write(
          request.uri.path.contains('empty')
              ? '{}'
              : '<html>gateway private detail</html>',
        );
        await request.response.close();
      });
      final api = CollaborationApi('http://127.0.0.1:${server.port}/');
      for (final entry in {'empty/': 403, 'gateway/': 502}.entries) {
        await expectLater(
          api.request('GET', entry.key),
          throwsA(
            isA<CollaborationApiException>().having(
              (e) => e.status,
              'status',
              entry.value,
            ),
          ),
        );
      }
    },
  );
}
