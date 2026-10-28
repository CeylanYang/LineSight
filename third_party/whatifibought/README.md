# WhatIfIBought original UI and LineSight SSO

> Historical wrong-project deployment. The user's screenshots identify
> `mamawai/wtfibought`, not this same-name repository. Keep this directory only
> for audit/rollback; use `../wtfibought/` for the corrected deployment.

Upstream: https://github.com/devinjudson/WhatIfIBought
Commit: b79f3013cfeb5412508f8d79a2eb31242bc730da

The desktop/mobile homepage, Outfit font, CSS, investment form, charts and stock
route now match upstream. `linesight.patch` contains only subpath URLs, Next 15
async searchParams compatibility and build/dependency settings. No FMP or OpenAI
key is configured: upstream's own sample-data fallback is retained.

- Website: https://99ai.pronhubcn.com/linesight/
- Stocks: https://99ai.pronhubcn.com/linesight/whatif
- Login/account: https://99ai.pronhubcn.com/login
- Issuer: https://99ai.pronhubcn.com/sso/realms/linesight
- Public registration is disabled in Keycloak, `/register` and the legacy API.

Authentication uses unmodified [OAuth2 Proxy 7.15.5](https://github.com/oauth2-proxy/oauth2-proxy)
and Keycloak 26.8.1, authorization code + S256 PKCE. The confidential
`linesight-whatif` client uses existing realm/users/passwords. Its only redirect
is `/linesight/whatif/oauth2/callback`. No separate account database or password
copying is introduced. Admin-created usernames authorize access; placeholder
team emails are not treated as proof of email ownership. The encrypted session
cookie is Secure/HttpOnly and scoped to the stock path.

Services bind loopback: Next :3008, OAuth2 Proxy :3108, Keycloak :8081. Caddy
forces the domain/IP forwarding host. Legacy apps keep their issuing host for
refresh/logout. API verification accepts only explicit realm aliases, mapping
them to permanent identities, and retains signature/audience/client checks and
live introspection at the issuing host.

Production: `/opt/linesight-extras/whatif-original-142b/site`,
`/opt/linesight-extras/oauth2-proxy-7.15.5/whatif-auth.cfg`,
`/etc/linesight/whatif-auth.env` (0600), `linesight-whatif.service` and
`linesight-whatif-auth.service`. Private local recovery copy:
`C:/Users/29668/LineSight-private/whatif-sso-v1/whatif-auth.env`.
Original config/backend backup: `/var/backups/linesight/stock142/20261025T032448Z`.
Passwords and subjects are preserved; the new client is additive.

`deploy-original.py` is a guarded first-cutover script with original-hash
preconditions; do not rerun on a migrated installation. `deploy.sh` is historical
build 8085 only. Build by applying the patch to the pinned upstream and running
`npm install --legacy-peer-deps; npm run build` (Node 22). Package
`.next/standalone` as `site/`, with `.next/static` and `public/` copied into it.
Verify OAuth2 Proxy against its upstream release SHA-256 before installing.

`verify.py` checks domain discovery, authentication gates and closed public
registration without credentials. Browser acceptance at 390/1440 px, existing
team login, browser SSO, form/results/chart, native PKCE, identity preservation
and refresh evidence are under `acceptance/stock142-batch`.

Upstream has no explicit LICENSE file at this commit. This directory contains
integration patch/config/scripts, not the upstream source distribution.
