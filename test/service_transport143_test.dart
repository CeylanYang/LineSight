import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/service_transport.dart';

class _Socket implements Socket {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const domain = '99ai.pronhubcn.com';
  const recovery = '47.111.81.94';

  test(
    'TLS failure retries only connection and preserves canonical URI',
    () async {
      final calls = <String>[];
      final socket = _Socket();
      final factory = ServiceConnections(
        connector: (host, port, secure) async {
          calls.add('$host:$port:$secure');
          return ConnectionTask.fromSocket(
            host == domain
                ? Future<Socket>(() => throw const HandshakeException('reset'))
                : Future<Socket>.value(socket),
            () {},
          );
        },
      );
      final uri = Uri.parse('https://$domain/api/v1/workspaces/');
      final task = await factory.call(uri, null, null);
      expect(await task.socket, same(socket));
      expect(calls, ['$domain:443:true', '$recovery:443:true']);
      expect(uri.host, domain);
    },
  );

  test('healthy primary does not use recovery', () async {
    final calls = <String>[];
    final factory = ServiceConnections(
      connector: (host, port, secure) async {
        calls.add(host);
        return ConnectionTask.fromSocket(
          Future<Socket>.value(_Socket()),
          () {},
        );
      },
    );
    await (await factory.call(Uri.https(domain, '/'), null, null)).socket;
    expect(calls, [domain]);
  });

  test(
    'custom hosts, ports and HTTP never receive recovery credentials',
    () async {
      for (final address in [
        'https://attacker.invalid/api/',
        'https://$domain.attacker.invalid/api/',
        'https://$domain:8443/api/',
        'http://$domain/api/',
        'https://user:password@$domain/api/',
      ]) {
        final calls = <String>[];
        final factory = ServiceConnections(
          connector: (host, port, secure) async {
            calls.add(host);
            return ConnectionTask.fromSocket(
              Future<Socket>(() => throw const SocketException('unreachable')),
              () {},
            );
          },
        );
        final task = await factory.call(Uri.parse(address), null, null);
        await expectLater(task.socket, throwsA(isA<SocketException>()));
        expect(calls, [Uri.parse(address).host]);
      }
    },
  );

  test('failed recovery remains an error with no further retry', () async {
    final calls = <String>[];
    final factory = ServiceConnections(
      connector: (host, port, secure) async {
        calls.add(host);
        return ConnectionTask.fromSocket(
          Future<Socket>(
            () => throw const HandshakeException('invalid certificate'),
          ),
          () {},
        );
      },
    );
    final task = await factory.call(Uri.https(domain, '/'), null, null);
    await expectLater(task.socket, throwsA(isA<HandshakeException>()));
    expect(calls, [domain, recovery]);
  });

  test('cancelling a pending primary never starts recovery', () async {
    final calls = <String>[];
    final pending = Completer<Socket>();
    final factory = ServiceConnections(
      connector: (host, port, secure) async {
        calls.add(host);
        return ConnectionTask.fromSocket(pending.future, () {
          if (!pending.isCompleted) {
            pending.completeError(const SocketException('cancelled'));
          }
        });
      },
    );
    final task = await factory.call(Uri.https(domain, '/'), null, null);
    task.cancel();
    await expectLater(task.socket, throwsA(isA<SocketException>()));
    expect(calls, [domain]);
  });

  test('explicit proxy keeps its own connection route', () async {
    final calls = <String>[];
    final factory = ServiceConnections(
      connector: (host, port, secure) async {
        calls.add('$host:$port:$secure');
        return ConnectionTask.fromSocket(
          Future<Socket>.value(_Socket()),
          () {},
        );
      },
    );
    await (await factory.call(
      Uri.https(domain, '/'),
      'proxy.test',
      8080,
    )).socket;
    expect(calls, ['proxy.test:8080:false']);
  });

  test('native discovery relay is fixed to the canonical production realm', () {
    expect(
      cloudDiscoveryUrl('https://$domain/sso/realms/linesight'),
      'https://$recovery/_linesight/identity/discovery',
    );
    for (final issuer in [
      'https://$recovery/sso/realms/linesight',
      'https://$domain.attacker.invalid/sso/realms/linesight',
      'https://custom.invalid/realm',
    ]) {
      expect(cloudDiscoveryUrl(issuer), isNull);
    }
  });
}
