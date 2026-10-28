# What If I Bought — correct upstream integration

Repository: https://github.com/mamawai/wtfibought

Pinned revision: `d99fd9bae3564a2630880a3a8f52fcd0dfee7bdb` (MIT).
The earlier `../whatifibought/` directory records a different same-name project
selected by mistake. It is retained for rollback, not used as the intended UI.

The original React desktop/mobile views and CSS are preserved. Changes in
`deployment.patch` mount the application under `/linesight/whatif/`, bootstrap
the existing LineSight identity, and use the existing SSO gateway for logout.
`LinesightSsoController.java` and `LinesightAuthBoundary.java` are the isolated
server-side deployment adapter. They verify Keycloak signature, issuer, expiry,
audience `wiib` and client `linesight-whatif`; bind by immutable subject; refuse
username collisions; and close all upstream local-login/registration routes.
No existing password is changed or copied. Native WIIB passwords remain null.
Keycloak 26's standard `basic` client scope is required to include `sub` in the
access token. `provision.py --sso-only` updates these standard SSO settings
without restarting databases/services. Unchanged Redis configuration is not
restarted by provisioning.

## Rebuild and deploy

1. Check out the pinned upstream revision and apply `deployment.patch`.
2. Copy the two Java adapters into
   `wiib-sim/src/main/java/com/mawai/wiibsim/config/`.
3. Build web with Node 22: `npm ci --no-audit --no-fund`, then `npm run build`
   in `wiib-web`. Include upstream LICENSE as `dist/LICENSE.txt`; archive dist
   contents as `web.tar.gz`.
4. Archive the patched root pom, LICENSE, common/quant/feed/sim/agent modules and SQL as
   `source.tar.gz`. `build-server.py` builds with Java 25 and Maven 3.9.16.
   Its toolchain metadata is supplied in `linux-jdk.json`; the JDK SHA-256 is
   `68982529869257d0ee6b824ec5aa270ff8b118bb438670da0b97ebdab178d7fb`.
5. `provision.py` creates an isolated PostgreSQL database/role and Redis, adds
   an access-token audience to the existing Keycloak client, and reserves id 1
   for the existing `lsuser01` subject. All other user IDs start at 100.
   Back up `/etc/linesight/wiib.env` privately before cutover. It is generated
   once, mode 0600; rerunning must not rotate its keys/passwords.
6. `install-services.py` installs loopback-only, limited systemd JVM services.
   `deploy-web.py` adds a loopback Caddy site on 3009. It backs up the live
   Caddyfile and preserves existing app, mail, identity and OTA routes.
7. Verify dependencies and login; `deploy-web.py --cutover` switches only the
   stock OAuth2 Proxy upstream from 3008 to 3009, passes its signed access token
   to the adapter, and configures Keycloak logout. Run `verify-browser.cjs`.

Host directory `/opt/linesight-extras/wtfibought-144`; staging
`/var/tmp/linesight-wtf144`; private rollback files
`/var/backups/linesight/wtf144`. Services are `linesight-wiib-{feed,sim,agent}`
and `linesight-wiib-redis`. Existing `linesight-whatif-auth` remains the SSO
gateway. The former Next server on 3008 is stopped/disabled after validation;
its files and service definition remain for rollback.
To roll back, restore `whatif-auth.cfg.before`, start `linesight-whatif`, and
restart the authentication gateway. Do not restore old identity databases or
rotate APK/OTA signing keys.

## Operational limits

The host has about 2 GB RAM, much less than upstream's full Compose resource
settings. JVMs have small heaps and pools; whale address collection is disabled.
The optional Python 3.13 factor-mining service is not deployed and its routes
return 503. Model/news/testnet secrets are not invented or purchased. The
official Binance public-data host supplies reachable spot REST and WebSocket
data; futures egress must be checked independently and is currently failing.
Do not replace unavailable quotes with fabricated values.

Private credentials are backed up under the operator's
`LineSight-private/wtfibought-v1` directory, never in this checkout or web root.
See acceptance evidence for the final live status and actual checks passed.
