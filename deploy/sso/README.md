# LineSight cloud identity

Keycloak 26.8.1 and PostgreSQL 17 run under Podman Compose, managed by
`linesight-identity.service`. Keycloak is Apache-2.0 licensed:
https://github.com/keycloak/keycloak. The Android app uses AppAuth authorization
code + PKCE S256 through `flutter_appauth`, and secure token storage through
`flutter_secure_storage`. Normal accounts have no password grant.

The production issuer is `https://47.111.81.94/sso/realms/linesight`. Caddy exposes
`/sso/*` and forwards to loopback port 8081. PostgreSQL has no public port.

Generate private inputs once using `tool/prepare_keycloak.py`. Never regenerate
the live realm or credentials as an implicit deploy step. Inputs under
`.artifact-work/sso/` are ignored. `demo-build.json` is passed with
`--dart-define-from-file`; it contains only the isolated shared demo identity,
never the realm administrator, database password, or API client secret.

Clients: `linesight-android` is a public native PKCE client, `linesight-demo` is a
public direct-grant client for the shared demo user, `linesight-api` is the
confidential introspection client. Both app clients receive the API audience.
The API validates RS256 signatures, issuer, audience, authorized party, expiry
and current introspection on every request. Provider outages return 503 rather
than silently accepting tokens or reporting false password failures.

User subject mappings are permanent. Self-service linking by username/email is
forbidden. `migrate_legacy_cloud.py` imports trusted Argon2 representations and
binds provider subjects to existing database users. Resuming an interrupted
import requires the exact original credential representation on the host;
matching a username alone never authorizes a link.

`deploy_cloud_identity.py` backs up source, environment and SQLite, stops the
API, adopts the old syncdb schema with `--fake-initial`, runs forward migrations,
provisions identities, verifies every original row/column, enables OIDC and
checks health using the public Host header. Failures restore all three backups.
Backups are private under `/var/backups/linesight/identity/api-<UTC timestamp>`.
Provider provisioning is resumable after API rollback. A provider database
backup must accompany future provider upgrades; do not delete its named volume.

Verification scripts: `verify_keycloak.py`, `verify_legacy_password_import.py`,
`verify_cloud_api.py`, `verify_live_workflow.py`. They do not print credentials or
tokens. API probes create isolated acceptance workspaces; their provider test
identity is deleted after verification. Workflow probes use only the demo team.

Remaining operational setup: SMTP password-reset delivery, scheduled provider
database backups with a restore rehearsal, and final release upgrade checks.
Hosted authenticated password changes use Keycloak's UPDATE_PASSWORD action.
