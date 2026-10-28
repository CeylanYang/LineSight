import 'dart:async';
import 'dart:io';

const _serviceHost = '99ai.pronhubcn.com';
const _recoveryHost = '47.111.81.94';

typedef ServiceSocketConnector =
    Future<ConnectionTask<Socket>> Function(String host, int port, bool secure);

Future<ConnectionTask<Socket>> _connect(
  String host,
  int port,
  bool secure,
) async => secure
    ? SecureSocket.startConnect(host, port)
    : Socket.startConnect(host, port);

/// Retries only the TLS connection, before any HTTP headers/body are sent.
/// Both endpoints use normal CA + hostname verification. The HTTP URI/Host
/// remains canonical, including when the trusted recovery address is used.
class ServiceConnections {
  final ServiceSocketConnector connector;
  const ServiceConnections({this.connector = _connect});

  Future<ConnectionTask<Socket>> call(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    if (proxyHost != null) return connector(proxyHost, proxyPort!, false);
    final secure = uri.scheme == 'https';
    if (!secure ||
        uri.host != _serviceHost ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty) {
      return connector(uri.host, uri.port, secure);
    }
    ConnectionTask<Socket>? active;
    var cancelled = false;
    Future<Socket> attempt(String host, Duration timeout) async {
      if (cancelled) throw const SocketException('Connection cancelled');
      final task = await connector(host, 443, true);
      active = task;
      if (cancelled) task.cancel();
      return task.socket.timeout(
        timeout,
        onTimeout: () {
          task.cancel();
          throw TimeoutException('Service connection timed out');
        },
      );
    }

    Future<Socket> establish() async {
      try {
        return await attempt(_serviceHost, const Duration(seconds: 5));
      } on HandshakeException {
        // The recovery connection still verifies its own certificate.
      } on SocketException {
        if (cancelled) rethrow;
      } on TimeoutException {
        if (cancelled) rethrow;
      }
      return attempt(_recoveryHost, const Duration(seconds: 4));
    }

    return ConnectionTask.fromSocket(establish(), () {
      cancelled = true;
      active?.cancel();
    });
  }
}

HttpClient serviceHttpClient() =>
    HttpClient()..connectionFactory = const ServiceConnections().call;

/// Browser authorization stays on the public domain. Native AppAuth discovery
/// and token exchange use a fixed TLS relay whose discovery issuer is the same
/// canonical realm, preserving AppAuth's issuer, nonce and PKCE validation.
String? cloudDiscoveryUrl(String issuer) =>
    issuer == 'https://$_serviceHost/sso/realms/linesight'
    ? 'https://$_recoveryHost/_linesight/identity/discovery'
    : null;
