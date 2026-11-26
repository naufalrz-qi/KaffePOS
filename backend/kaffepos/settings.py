"""Settings KaffePOS. Rahasia & koneksi dibaca dari environment atau backend/.env."""
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

_env_file = BASE_DIR / ".env"
if _env_file.exists():  # format KEY=VALUE per baris; utf-8-sig agar BOM dari editor Windows tidak ikut terbaca
    for _line in _env_file.read_text(encoding="utf-8-sig").splitlines():
        if "=" in _line and not _line.lstrip().startswith("#"):
            _key, _value = _line.split("=", 1)
            os.environ.setdefault(_key.strip(), _value.strip())

SECRET_KEY = os.environ["DJANGO_SECRET_KEY"]
DEBUG = os.environ.get("DJANGO_DEBUG") == "1"
ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1").split(",")

INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.staticfiles",
    "core",
    "catalog",
    "sales",
    "dashboard",
    "reports",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "core.tenancy.TenantMiddleware",
]

ROOT_URLCONF = "kaffepos.urls"
WSGI_APPLICATION = "kaffepos.wsgi.application"
TEMPLATES = [{
    "BACKEND": "django.template.backends.django.DjangoTemplates",
    "APP_DIRS": True,
    "OPTIONS": {"context_processors": [
        "django.template.context_processors.request",
        "django.contrib.auth.context_processors.auth",
    ]},
}]

DATABASES = {
    "default": {
        "ENGINE": "mssql",
        "NAME": os.environ.get("DB_NAME", "kaffepos"),
        "USER": os.environ.get("DB_USER", "kaffepos"),
        "PASSWORD": os.environ["DB_PASSWORD"],
        "HOST": os.environ.get("DB_HOST", "localhost"),
        "PORT": os.environ.get("DB_PORT", ""),
        "ATOMIC_REQUESTS": True,
        # Default Driver 18 (produksi). PC dev yang hanya punya Driver 17 mengisi DB_DRIVER di .env.
        "OPTIONS": {"driver": os.environ.get("DB_DRIVER", "ODBC Driver 18 for SQL Server"),
                    "extra_params": "TrustServerCertificate=yes"},
    }
}
CACHES = {"default": {"BACKEND": "django.core.cache.backends.db.DatabaseCache", "LOCATION": "django_cache"}}

AUTH_USER_MODEL = "core.User"
LANGUAGE_CODE = "id"
TIME_ZONE = "Asia/Jakarta"
USE_I18N = True
USE_TZ = True
STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
MIN_APP_VERSION = os.environ.get("MIN_APP_VERSION", "1.0.0")
LOGIN_URL = "login"
LOGIN_REDIRECT_URL = "home"
LOGOUT_REDIRECT_URL = "login"
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator", "OPTIONS": {"min_length": 10}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]
