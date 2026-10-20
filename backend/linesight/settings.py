"""Tenant scoped LineSight service. All secrets are loaded from the service environment."""

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
APP_DATA = Path(os.environ.get("LINESIGHT_DATA_DIR", "/srv/linesight/shared/data"))
APP_MEDIA = Path(os.environ.get("LINESIGHT_MEDIA_DIR", "/srv/linesight/shared/media"))
APP_STATIC = Path(os.environ.get("LINESIGHT_STATIC_DIR", "/srv/linesight/shared/static"))

SECRET_KEY = os.environ["LINESIGHT_DJANGO_SECRET"]
DEBUG = False
ALLOWED_HOSTS = [
    item.strip()
    for item in os.environ.get(
        "LINESIGHT_ALLOWED_HOSTS",
        "127.0.0.1,localhost,47.111.81.94,*.linesight.internal",
    ).split(",")
    if item.strip()
]
APPEND_SLASH = True

SHARED_APPS = (
    "django_tenants",
    "workspace_registry.apps.WorkspaceRegistryConfig",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.sites",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "django.contrib.admin",
    "tenant_users.tenants",
    "tenant_users.permissions",
    "accounts.apps.AccountsConfig",
)

TENANT_APPS = (
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.sites",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "django.contrib.admin",
    "allauth",
    "allauth.account",
    "allauth.headless",
    "allauth.mfa",
    "allauth.usersessions",
    "django_otp",
    "django_otp.plugins.otp_totp",
    "django_otp.plugins.otp_static",
    "rest_framework",
    "simple_history",
    "helpdesk",
    "quality.apps.QualityConfig",
    "production.apps.ProductionConfig",
    "inspection.apps.InspectionConfig",
    "django_q",
)

INSTALLED_APPS = list(SHARED_APPS) + [app for app in TENANT_APPS if app not in SHARED_APPS]
TENANT_MODEL = "workspace_registry.Workspace"
TENANT_DOMAIN_MODEL = "workspace_registry.WorkspaceDomain"
TENANT_USERS_DOMAIN = "linesight.internal"
AUTH_USER_MODEL = "accounts.Account"
DATABASE_ROUTERS = ("django_tenants.routers.TenantSyncRouter",)
DATABASES = {
    "default": {
        "ENGINE": "django_tenants.postgresql_backend",
        "NAME": os.environ.get("LINESIGHT_DB_NAME", "linesight"),
        "USER": os.environ.get("LINESIGHT_DB_USER", "linesight"),
        "PASSWORD": os.environ["LINESIGHT_DB_PASSWORD"],
        "HOST": os.environ.get("LINESIGHT_DB_HOST", "127.0.0.1"),
        "PORT": os.environ.get("LINESIGHT_DB_PORT", "5432"),
        "CONN_MAX_AGE": 60,
        "OPTIONS": {"connect_timeout": 5, "application_name": "linesight-api"},
    }
}

MIDDLEWARE = (
    "django_tenants.middleware.main.TenantMainMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "allauth.usersessions.middleware.UserSessionsMiddleware",
    "django.middleware.locale.LocaleMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "tenant_users.tenants.middleware.TenantAccessMiddleware",
    "allauth.account.middleware.AccountMiddleware",
    "django_otp.middleware.OTPMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "simple_history.middleware.HistoryRequestMiddleware",
)

ROOT_URLCONF = "linesight.urls"
WSGI_APPLICATION = "linesight.wsgi.application"
ASGI_APPLICATION = "linesight.asgi.application"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
LANGUAGE_CODE = "zh-hans"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True
SITE_ID = 1

STATIC_URL = "/static/"
STATIC_ROOT = APP_STATIC
MEDIA_URL = "/private-media/"
MEDIA_ROOT = APP_MEDIA
FILE_UPLOAD_MAX_MEMORY_SIZE = 2 * 1024 * 1024
DATA_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024 + 1024 * 1024
DATA_UPLOAD_MAX_NUMBER_FILES = 1
SESSION_COOKIE_SECURE = True
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
CSRF_COOKIE_SECURE = True
CSRF_COOKIE_HTTPONLY = True
CSRF_COOKIE_SAMESITE = "Lax"
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = True
SECURE_HSTS_SECONDS = 31_536_000
SECURE_HSTS_INCLUDE_SUBDOMAINS = False
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "same-origin"
CSRF_TRUSTED_ORIGINS = ["https://47.111.81.94"]

AUTHENTICATION_BACKENDS = (
    "tenant_users.permissions.backend.UserBackend",
    "allauth.account.auth_backends.AuthenticationBackend",
)
ACCOUNT_USER_MODEL_USERNAME_FIELD = "username"
ACCOUNT_LOGIN_METHODS = {"username"}
ACCOUNT_SIGNUP_FIELDS = ["username*", "password1*", "password2*"]
ACCOUNT_EMAIL_VERIFICATION = "none"
ACCOUNT_UNIQUE_EMAIL = False
ACCOUNT_PREVENT_ENUMERATION = True
ACCOUNT_RATE_LIMITS = {"login": "5/m/key,10/m/ip", "signup": "3/h/ip"}
ACCOUNT_LOGOUT_ON_PASSWORD_CHANGE = True
HEADLESS_ONLY = True
HEADLESS_CLIENTS = ("app",)
HEADLESS_JWT_ALGORITHM = "RS256"
HEADLESS_JWT_PRIVATE_KEY = os.environ["LINESIGHT_JWT_PRIVATE_KEY"]
HEADLESS_JWT_ACCESS_TOKEN_EXPIRES_IN = 300
HEADLESS_JWT_REFRESH_TOKEN_EXPIRES_IN = 86400
HEADLESS_JWT_STATEFUL_VALIDATION_ENABLED = True
HEADLESS_JWT_ROTATE_REFRESH_TOKEN = True
HEADLESS_JWT_AUTHORIZATION_HEADER_SCHEME = "Bearer"
HEADLESS_TOKEN_STRATEGY = "allauth.headless.tokens.strategies.jwt.JWTTokenStrategy"
USERSESSIONS_TRACK_ACTIVITY = True
MFA_SUPPORTED_TYPES = ["totp", "recovery_codes"]
MFA_TRUST_ENABLED = False

SOCIALACCOUNT_ENABLED = False
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "allauth.headless.contrib.rest_framework.authentication.JWTTokenAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {"anon": "30/minute", "user": "120/minute"},
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
}

Q_CLUSTER = {
    "name": "linesight",
    "orm": "default",
    "workers": 1,
    "recycle": 100,
    "timeout": 30,
    "retry": 60,
    "ack_failures": True,
    "max_attempts": 2,
    "save_limit": 1000,
}

PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.Argon2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2SHA1PasswordHasher",
    "django.contrib.auth.hashers.BCryptSHA256PasswordHasher",
]
PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator", "OPTIONS": {"min_length": 12}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]
DEFAULT_PASSWORD_VALIDATORS = PASSWORD_VALIDATORS
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "root": {"handlers": ["console"], "level": "INFO"},
    "loggers": {
        "django.request": {"handlers": ["console"], "level": "WARNING", "propagate": False},
        "django.security": {"handlers": ["console"], "level": "WARNING", "propagate": False},
    },
}

