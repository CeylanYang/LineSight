"""Generate official Keycloak realm/config in an ignored staging directory.

Does not deploy, overwrite an identity DB or print passwords. The demo credential
file is a build input for the explicitly authorized shared demo account only.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
from urllib.parse import urlsplit


def realm_document(demo_password, api_secret=None):
    audience = {
        "name": "linesight-api-audience", "protocol": "openid-connect",
        "protocolMapper": "oidc-audience-mapper", "consentRequired": False,
        "config": {"included.custom.audience": "linesight-api", "id.token.claim": "false",
                   "access.token.claim": "true"},
    }
    return {
        "realm": "linesight", "enabled": True, "displayName": "LineSight",
        "sslRequired": "external", "registrationAllowed": False,
        "registrationEmailAsUsername": False, "resetPasswordAllowed": True,
        "loginWithEmailAllowed": True, "duplicateEmailsAllowed": False,
        "bruteForceProtected": True, "failureFactor": 5,
        "accessTokenLifespan": 300, "ssoSessionIdleTimeout": 1800,
        "ssoSessionMaxLifespan": 28800, "revokeRefreshToken": True,
        "refreshTokenMaxReuse": 0,
        "internationalizationEnabled": True,
        "supportedLocales": ["en", "zh-CN"], "defaultLocale": "zh-CN",
        "roles": {"realm": [{"name": "demo"}]},
        "clients": [
            {"clientId": "linesight-api", "name": "LineSight API",
             "protocol": "openid-connect", "publicClient": False,
             "secret": api_secret or secrets.token_urlsafe(36),
             "standardFlowEnabled": False, "directAccessGrantsEnabled": False,
             "serviceAccountsEnabled": False},
            {"clientId": "linesight-android", "name": "LineSight",
             "protocol": "openid-connect", "publicClient": True,
             "standardFlowEnabled": True, "directAccessGrantsEnabled": False,
             "implicitFlowEnabled": False, "serviceAccountsEnabled": False,
             "redirectUris": ["com.linesight.app:/oauthredirect"],
             "attributes": {"pkce.code.challenge.method": "S256",
                            "post.logout.redirect.uris": "com.linesight.app:/oauthredirect"},
             "protocolMappers": [audience]},
            {"clientId": "linesight-demo", "name": "LineSight Demo",
             "protocol": "openid-connect", "publicClient": True,
             "standardFlowEnabled": False, "directAccessGrantsEnabled": True,
             "implicitFlowEnabled": False, "serviceAccountsEnabled": False,
             "protocolMappers": [audience]},
        ],
        "users": [{"username": "linesight.demo", "enabled": True,
                   "firstName": "LineSight", "lastName": "Demo",
                   "email": "demo@linesight.invalid", "emailVerified": True,
                   "realmRoles": ["demo"], "requiredActions": [],
                   "credentials": [{"type": "password", "value": demo_password,
                                    "temporary": False}]}],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path(".artifact-work/sso"))
    parser.add_argument("--public-url", default="https://99ai.pronhubcn.com/sso")
    args = parser.parse_args()
    parsed = urlsplit(args.public_url)
    if parsed.scheme != "https" or not parsed.netloc or parsed.path != "/sso" or parsed.query or parsed.fragment:
        parser.error("public URL must be an HTTPS origin with /sso path")
    output = args.output.resolve()
    if output.exists():
        parser.error("output exists; do not regenerate or rotate live credentials implicitly")
    output.mkdir(parents=True)
    os.chmod(output, 0o700)
    (output / "realm").mkdir()
    password = "LineSightDemo-" + secrets.token_urlsafe(18)
    api_secret = secrets.token_urlsafe(36)
    env = {"KEYCLOAK_PUBLIC_URL": args.public_url,
           "KEYCLOAK_DB_PASSWORD": secrets.token_urlsafe(36),
           "KEYCLOAK_ADMIN_USERNAME": "identity-admin",
           "KEYCLOAK_ADMIN_PASSWORD": secrets.token_urlsafe(36),
           "LINESIGHT_OIDC_CLIENT_SECRET": api_secret}
    (output / "identity.env").write_text("".join(f"{k}={v}\n" for k, v in env.items()), encoding="utf-8")
    (output / "realm/linesight-realm.json").write_text(json.dumps(realm_document(password, api_secret), ensure_ascii=False, indent=2), encoding="utf-8")
    (output / "demo-build.json").write_text(json.dumps({
        "LINESIGHT_API_BASE_URL": "https://99ai.pronhubcn.com/api/v1/",
        "LINESIGHT_OIDC_ISSUER": args.public_url + "/realms/linesight",
        "LINESIGHT_DEMO_USERNAME": "linesight.demo", "LINESIGHT_DEMO_PASSWORD": password,
    }, indent=2), encoding="utf-8")
    for file in (output / "identity.env", output / "realm/linesight-realm.json", output / "demo-build.json"):
        os.chmod(file, 0o600)
    shutil.copy2(Path(__file__).resolve().parents[1] / "deploy/sso/compose.yaml", output / "compose.yaml")
    print("Keycloak staging prepared. Passwords were written to private build inputs, not console output.")


if __name__ == "__main__":
    main()
