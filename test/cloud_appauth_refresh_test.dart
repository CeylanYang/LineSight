import 'dart:convert';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'cloud_account_test.dart' show MemoryVault;

class FailingRefreshAppAuth extends FlutterAppAuth {
  final FlutterAppAuthPlatformException failure;
  FailingRefreshAppAuth(this.failure);
  @override
  Future<TokenResponse> token(TokenRequest request) async => throw failure;
}

void main() {
  for (final legacy in <Object?>[
    'private-error-token',
    {'error': 'private-error-token'},
    null,
  ]) {
    final kind = legacy.runtimeType;
    test(
      'AppAuth revoked refresh with $kind legacy details requests login',
      () async {
        final vault = MemoryVault()
          ..value = jsonEncode(
            CloudTokens(
              'access',
              'refresh',
              'linesight-android',
              DateTime.now().subtract(const Duration(minutes: 1)),
            ).toJson(),
          );
        final identity = KeycloakIdentityGateway(
          appAuth: FailingRefreshAppAuth(
            FlutterAppAuthPlatformException(
              code: 'token_failed',
              legacyDetails: legacy,
              platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
                error: FlutterAppAuthOAuthError.invalidGrant,
                errorDescription: 'private-error-token',
              ),
            ),
          ),
        );
        final account = CloudAccount(vault: vault, identity: identity);
        addTearDown(account.dispose);
        await account.restore();
        expect(account.signedIn, isFalse);
        expect(vault.value, isNull);
        expect(account.error, '登录已过期，请重新登录');
        expect(account.error, isNot(contains('private-error-token')));
        expect(account.jobs, isEmpty);
      },
    );

    test(
      'AppAuth network failure with $kind legacy details preserves session',
      () async {
        final vault = MemoryVault()
          ..value = jsonEncode(
            CloudTokens(
              'access',
              'refresh',
              'linesight-android',
              DateTime.now().subtract(const Duration(minutes: 1)),
            ).toJson(),
          );
        final previous = vault.value;
        final identity = KeycloakIdentityGateway(
          appAuth: FailingRefreshAppAuth(
            FlutterAppAuthPlatformException(
              code: 'network_error',
              legacyDetails: legacy,
              platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
                rootCauseDebugDescription: 'private-error-token',
              ),
            ),
          ),
        );
        final account = CloudAccount(vault: vault, identity: identity);
        addTearDown(account.dispose);
        await account.restore();
        expect(account.signedIn, isTrue);
        expect(vault.value, previous);
        expect(account.error, '无法恢复登录，请检查网络后重试');
        expect(account.workspaceFailure, isA<CollaborationApiException>());
        expect(
          (account.workspaceFailure as CollaborationApiException).status,
          0,
        );
        expect(account.error, isNot(contains('private-error-token')));
      },
    );
  }
}
