# M0–M1 Fondasi & Sync Backend — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backend Django di SQL Server yang punya data master per tenant, dashboard owner untuk mengelola outlet/menu/staf/device, serta API aktivasi device, snapshot master, dan push event shift/kas/penjualan. Semuanya teruji otomatis.

**Architecture:** Satu project Django (`backend/`). Data usaha mewarisi `TenantScoped`, sehingga query lewat `objects` otomatis difilter per tenant dan gagal jika tidak ada tenant aktif. API mobile memakai Django Ninja dengan token device (Bearer). Dashboard memakai view generik Django + template + Pico.css tanpa proses build. Perubahan data master menaikkan `Tenant.master_version` lewat sinyal.

**Tech Stack:** Python 3.14, Django 5.2 LTS, mssql-django (pyodbc + ODBC Driver 17 yang sudah terpasang), django-ninja, pytest + pytest-django, SQL Server 2022 lokal (dev).

**Spec:** `docs/PRD.md` (v0.3) dan `docs/DESAIN-TEKNIS.md` (v0.1). Baca keduanya sebelum mulai.

## Global Constraints

- Python **3.14** (`py -3.14`), Django **>=5.2.8,<5.3**, mssql-django **>=2.0**, django-ninja **>=1.4**.
- Semua perintah backend dijalankan di **PowerShell dari `D:\App\KaffePOS\backend`** dengan `.\.venv\Scripts\python.exe` (alias `python` global mengarah ke Microsoft Store).
- Test: `.\.venv\Scripts\python.exe -m pytest`. Database test `test_kaffepos` di-reuse; tambahkan `--create-db` jika skemanya rusak.
- Database dev: SQL Server lokal `localhost` (instance `MSSQLSERVER`), database `kaffepos`, login `kaffepos`. Produksi nanti SQL Server 2025 Express.
- **Jangan** memakai fitur khusus database: trigger, unique/index bersyarat, kolom JSON yang di-query, fungsi zona waktu database, atau unique pada kolom yang boleh NULL (desain §4).
- Semua primary key memakai UUIDv7 (`uuid.uuid7`). Uang = integer Rupiah. Persentase = basis poin (1000 = 10%).
- Model data usaha mewarisi `core.tenancy.TenantScoped`. `all_tenants` hanya boleh dipakai di auth API dan job.
- Teks UI & pesan error dalam Bahasa Indonesia.
- Commit di akhir setiap task. Pesan commit diakhiri trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Cakupan

**Masuk rencana ini:** PRD A-01 (nama usaha & footer struk), A-02, A-03 (role & akses halaman master), A-04, M-01 s/d M-05, sisi server K-27/K-29 (status device & `server_time`); desain §3, §4 (core, catalog, sales), §5 (`device/activate`, `sync/master`, `sync/push` untuk 5 jenis event), §7.1, §7.5.

**Tidak masuk (rencana berikutnya):** loyalty & event `member.registered`/`card.issued` (M3), app Flutter (M2), laporan & audit log (M4), deploy staging (menunggu PRD Q2 hosting & Q5 domain), QR untuk kode aktivasi device (M2), gambar QRIS, foto produk, dan pilihan metode bayar per usaha M-06 (M2).

**Penyesuaian kecil dari desain** (sudah diselaraskan di DESAIN-TEKNIS.md):
- Request `device/activate` tidak memuat `device_name`, karena nama device diatur owner di dashboard.
- Snapshot M1 belum memuat `card_base_url`, `resend_since`, `qris_image_url`, `image_url`; `stamp_rule` masih `null`. Semuanya ditambahkan di M2/M3.
- Default "void butuh PIN manager" per tipe outlet diganti dengan petunjuk di form. Owner yang memilih.

## Struktur File

```
.gitignore
shared/totals_cases.json              test vector rumus total (dipakai juga oleh Dart di M2)
backend/
├─ requirements.txt, manage.py, pytest.ini, .env (tidak di-commit)
├─ kaffepos/settings.py, urls.py, wsgi.py
├─ core/
│  ├─ models.py      Tenant, User, Outlet, Device, token_hash()
│  ├─ tenancy.py     tenant aktif (contextvars), TenantScoped, TenantManager, TenantMiddleware
│  ├─ master.py      sinyal kenaikan Tenant.master_version
│  ├─ pins.py        hash PIN staf yang bisa diverifikasi offline di HP
│  ├─ ratelimit.py   hit(), client_ip()
│  └─ management/commands/setup_tenant.py
├─ catalog/models.py Category, ModifierGroup, ModifierOption, Product
├─ sales/
│  ├─ models.py      Shift, CashMovement, Sale, SaleItem, SaleItemModifier, Payment
│  └─ totals.py      compute_totals() — rumus total integer
├─ api/
│  ├─ api.py         NinjaAPI, ApiError, DeviceAuth, endpoint activate/master/push
│  ├─ snapshot.py    build_snapshot(device)
│  └─ push.py        process_event() + handler per jenis event
├─ dashboard/
│  ├─ views.py       OwnerRequired, Login, Home, view device
│  ├─ forms.py       LoginForm, StaffForm
│  ├─ crud.py        crud() — daftar/tambah/ubah generik
│  ├─ urls.py
│  └─ templates/dashboard/  base, login, home, list, form, device_list, device_detail
└─ tests/            conftest.py + test_*.py
```

---

### Task 1: Repo, environment, dan kerangka Django di SQL Server

**Files:**
- Create: `.gitignore`
- Create: `backend/requirements.txt`, `backend/manage.py`, `backend/pytest.ini`
- Create: `backend/kaffepos/__init__.py`, `backend/kaffepos/settings.py`, `backend/kaffepos/urls.py`, `backend/kaffepos/wsgi.py`
- Create: `backend/core/__init__.py`, `backend/core/apps.py`, `backend/core/models.py`, `backend/core/migrations/__init__.py`
- Create (tidak di-commit): `backend/.env`
- Test: `backend/tests/test_core.py`

**Interfaces:**
- Produces: `core.models.Tenant` (`id` UUIDv7, `name`, `receipt_footer`, `master_version`, `next_device_no`) dan `core.models.User` (AbstractUser + `id` UUIDv7, `tenant` FK nullable, `role` = `User.Role.OWNER | MANAGER | CASHIER`, `display_name`, `pin_hash`, `can_discount`). Settings membaca `backend/.env`.

- [ ] **Step 1: Inisialisasi git**

```powershell
cd D:\App\KaffePOS
git init -b main
git config user.email
```
Jika `git config user.email` kosong, isi dulu identitas git dengan nama & email kamu sendiri (`git config --global user.name …` dan `git config --global user.email …`).

Buat `.gitignore`:
```
__pycache__/
*.pyc
.venv/
.pytest_cache/
backend/.env
backend/staticfiles/
```

- [ ] **Step 2: Virtualenv & dependensi**

`backend/requirements.txt`:
```
Django>=5.2.8,<5.3
mssql-django>=2.0
django-ninja>=1.4
tzdata
pytest>=8
pytest-django>=4.9
```
```powershell
cd D:\App\KaffePOS\backend
py -3.14 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```
Expected: diakhiri `Successfully installed … Django-5.2.… mssql-django-2.…`.

- [ ] **Step 3: Buat `.env` dan database dev**

Login & database ini dibuat di instance SQL Server lokal. Role `dbcreator` diperlukan supaya pytest bisa membuat `test_kaffepos`.
```powershell
.\.venv\Scripts\python.exe -c "import secrets; pw='Aa1'+secrets.token_urlsafe(24); open('.env','w').write(f'DJANGO_SECRET_KEY={secrets.token_urlsafe(50)}\nDJANGO_DEBUG=1\nDB_NAME=kaffepos\nDB_USER=kaffepos\nDB_PASSWORD={pw}\nDB_HOST=localhost\n')"
$pw = (Get-Content .env | Where-Object { $_ -like 'DB_PASSWORD=*' }) -replace '^DB_PASSWORD=', ''
sqlcmd -S localhost -E -b -Q "CREATE LOGIN kaffepos WITH PASSWORD = N'$pw'; ALTER SERVER ROLE dbcreator ADD MEMBER kaffepos; CREATE DATABASE kaffepos; ALTER DATABASE kaffepos SET READ_COMMITTED_SNAPSHOT ON; ALTER AUTHORIZATION ON DATABASE::kaffepos TO kaffepos;"
```
Expected: `sqlcmd` selesai tanpa pesan error (exit code 0).

PC dev ini hanya punya ODBC Driver 17, jadi tambahkan juga baris ini ke `.env` (tanpa baris ini Django mencari Driver 18):
```powershell
Add-Content -Path .env -Value "DB_DRIVER=ODBC Driver 17 for SQL Server" -Encoding ascii
```

- [ ] **Step 4: Kerangka Django**

`backend/manage.py`:
```python
#!/usr/bin/env python
import os
import sys

if __name__ == "__main__":
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "kaffepos.settings")
    from django.core.management import execute_from_command_line

    execute_from_command_line(sys.argv)
```

`backend/kaffepos/__init__.py`, `backend/core/__init__.py`, `backend/core/migrations/__init__.py`, dan `backend/core/models.py`: file kosong.

`backend/kaffepos/wsgi.py`:
```python
import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "kaffepos.settings")
application = get_wsgi_application()
```

`backend/kaffepos/urls.py`:
```python
urlpatterns = []
```

`backend/core/apps.py`:
```python
from django.apps import AppConfig


class CoreConfig(AppConfig):
    name = "core"
```

`backend/kaffepos/settings.py`:
```python
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
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
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
```

`backend/pytest.ini`:
```ini
[pytest]
DJANGO_SETTINGS_MODULE = kaffepos.settings
testpaths = tests
addopts = -q --reuse-db
```

- [ ] **Step 5: Tulis test yang gagal**

`backend/tests/test_core.py`:
```python
from core.models import Tenant, User


def test_tenant_and_user_use_uuid7(db):
    tenant = Tenant.objects.create(name="Kopi Uji")
    user = User.objects.create_user(username="budi", password="rahasia-123", tenant=tenant, display_name="Budi")
    assert tenant.id.version == 7 and user.id.version == 7
    assert User.objects.get(username="budi").tenant == tenant
```

- [ ] **Step 6: Jalankan, pastikan gagal**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_core.py`
Expected: ERROR saat setup Django, `AUTH_USER_MODEL refers to model 'core.User' that has not been installed`.

- [ ] **Step 7: Implementasi model**

`backend/core/models.py`:
```python
import uuid

from django.contrib.auth.models import AbstractUser, UserManager
from django.db import models


class Tenant(models.Model):
    """Satu usaha kopi. Sekarang hanya satu baris; struktur siap SaaS (PRD A-02)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid7, editable=False)
    name = models.CharField("Nama usaha", max_length=120)
    receipt_footer = models.CharField("Footer struk", max_length=200, blank=True)
    master_version = models.BigIntegerField(default=1, editable=False)
    next_device_no = models.PositiveIntegerField(default=1, editable=False)

    def __str__(self):
        return self.name


class User(AbstractUser):
    class Role(models.TextChoices):
        OWNER = "OWNER", "Owner"
        MANAGER = "MANAGER", "Manager"
        CASHIER = "CASHIER", "Kasir"

    id = models.UUIDField(primary_key=True, default=uuid.uuid7, editable=False)
    tenant = models.ForeignKey(Tenant, on_delete=models.PROTECT, null=True, blank=True, editable=False)
    role = models.CharField("Peran", max_length=10, choices=Role.choices, default=Role.CASHIER)
    display_name = models.CharField("Nama", max_length=80)
    pin_hash = models.CharField(max_length=128, blank=True, editable=False)
    can_discount = models.BooleanField("Boleh beri diskon", default=False)

    objects = UserManager()

    class Meta(AbstractUser.Meta):
        default_manager_name = "objects"
```

- [ ] **Step 8: Buat migrasi, jalankan test**

```powershell
.\.venv\Scripts\python.exe manage.py makemigrations core
.\.venv\Scripts\python.exe -m pytest tests/test_core.py
```
Expected: `1 passed`. Run pertama membuat `test_kaffepos` dan butuh ±20 detik.

- [ ] **Step 9: Migrasi database dev**

```powershell
.\.venv\Scripts\python.exe manage.py migrate
.\.venv\Scripts\python.exe manage.py createcachetable
.\.venv\Scripts\python.exe manage.py check
```
Expected: `System check identified no issues (0 silenced).`

- [ ] **Step 10: Commit**

```powershell
git add ..\.gitignore requirements.txt manage.py pytest.ini kaffepos core tests
git commit -m "chore: kerangka Django + SQL Server dengan user custom" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Scoping tenant, Outlet, dan Device

**Files:**
- Create: `backend/core/tenancy.py`
- Modify: `backend/core/models.py` (ganti seluruh isi)
- Modify: `backend/kaffepos/settings.py` (MIDDLEWARE)
- Create: `backend/tests/conftest.py`
- Test: `backend/tests/test_tenancy.py`

**Interfaces:**
- Consumes: `Tenant`, `User` (Task 1).
- Produces:
  - `core.tenancy`: `NoTenant`, `current_tenant_id()`, `activate_tenant(tenant_id)`, `tenant_context(tenant_id)` (context manager), `TenantManager`, `TenantScoped` (abstract: FK `tenant`, manager `objects` ber-tenant, `all_tenants` tanpa filter), `TenantMiddleware`.
  - `core.models`: `Outlet` (+ `Outlet.Type.OUTLET | MOBILE`), `Device` (`number` otomatis, `issue_activation_code() -> str`), `token_hash(token) -> str`, M2M `User.outlets`, manager `User.in_tenant`.
  - Fixture pytest: `tenant`, `tctx` (tenant aktif), `outlet`.

- [ ] **Step 1: Tulis fixture & test yang gagal**

`backend/tests/conftest.py`:
```python
import pytest

from core.models import Outlet, Tenant
from core.tenancy import tenant_context


@pytest.fixture
def tenant(db):
    return Tenant.objects.create(name="Kopi Uji")


@pytest.fixture
def tctx(tenant):
    """Tenant aktif selama test (seperti saat request dashboard/API)."""
    with tenant_context(tenant.id):
        yield tenant


@pytest.fixture
def outlet(tctx):
    return Outlet.objects.create(code="GRB01", name="Gerobak Sudirman")
```

`backend/tests/test_tenancy.py`:
```python
import pytest
from django.utils import timezone

from core.models import Device, Outlet, Tenant
from core.tenancy import NoTenant, tenant_context


def test_query_without_tenant_fails_closed(db):
    with pytest.raises(NoTenant):
        list(Outlet.objects.all())


def test_objects_only_sees_active_tenant(db):
    a, b = Tenant.objects.create(name="A"), Tenant.objects.create(name="B")
    with tenant_context(a.id):
        Outlet.objects.create(code="A1", name="Outlet A")
    with tenant_context(b.id):
        Outlet.objects.create(code="B1", name="Outlet B")
        assert [o.code for o in Outlet.objects.all()] == ["B1"]
    assert Outlet.all_tenants.count() == 2


def test_device_numbers_increase_and_are_never_reused(tctx, outlet):
    first = Device.objects.create(outlet=outlet, name="HP 1")
    first.delete()
    second = Device.objects.create(outlet=outlet, name="HP 2")
    assert (first.number, second.number) == (1, 2)


def test_activation_code_is_crockford_and_expires(tctx, outlet):
    device = Device.objects.create(outlet=outlet, name="HP 1")
    code = device.issue_activation_code()
    assert len(code) == 8 and not set(code) & set("ILOU")
    assert device.activation_expires_at > timezone.now()
```

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_tenancy.py`
Expected: ERROR `ModuleNotFoundError: No module named 'core.tenancy'`.

- [ ] **Step 3: Implementasi scoping tenant**

`backend/core/tenancy.py`:
```python
"""Scoping data per tenant (desain §3.2). Query lewat `objects` tanpa tenant aktif = error (fail closed)."""
import contextvars
from contextlib import contextmanager

from django.db import models

_current = contextvars.ContextVar("kaffepos_tenant_id", default=None)


class NoTenant(Exception):
    pass


def current_tenant_id():
    tenant_id = _current.get()
    if tenant_id is None:
        raise NoTenant("Tidak ada tenant aktif untuk query ini")
    return tenant_id


def activate_tenant(tenant_id):
    """Set tenant aktif sampai request selesai. TenantMiddleware yang mereset nilainya."""
    _current.set(tenant_id)


@contextmanager
def tenant_context(tenant_id):
    token = _current.set(tenant_id)
    try:
        yield
    finally:
        _current.reset(token)


class TenantManager(models.Manager):
    def get_queryset(self):
        return super().get_queryset().filter(tenant_id=current_tenant_id())


class TenantScoped(models.Model):
    tenant = models.ForeignKey("core.Tenant", on_delete=models.PROTECT, related_name="+", editable=False)

    objects = TenantManager()
    all_tenants = models.Manager()

    class Meta:
        abstract = True

    def save(self, *args, **kwargs):
        if self.tenant_id is None:
            self.tenant_id = current_tenant_id()
        super().save(*args, **kwargs)


class TenantMiddleware:
    """Setiap request dimulai dengan tenant = tenant user dashboard (atau kosong). Auth API boleh
    menggantinya lewat activate_tenant(); semua nilai direset saat request selesai."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        user = request.user
        with tenant_context(user.tenant_id if user.is_authenticated else None):
            return self.get_response(request)
```

Di `backend/kaffepos/settings.py`, tambahkan baris terakhir di daftar `MIDDLEWARE` (harus setelah `AuthenticationMiddleware`):
```python
    "core.tenancy.TenantMiddleware",
```

- [ ] **Step 4: Implementasi Outlet & Device**

Ganti seluruh isi `backend/core/models.py`:
```python
import hashlib
import secrets
import uuid
from datetime import timedelta

from django.contrib.auth.models import AbstractUser, UserManager
from django.core.exceptions import ValidationError
from django.db import models
from django.db.models import F
from django.utils import timezone

from .tenancy import TenantManager, TenantScoped, current_tenant_id

TIMEZONES = [("Asia/Jakarta", "WIB"), ("Asia/Makassar", "WITA"), ("Asia/Jayapura", "WIT")]
ROUNDING_UNITS = [(0, "Tanpa pembulatan"), (100, "Rp100"), (500, "Rp500"), (1000, "Rp1.000")]
CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"  # Crockford base32: tanpa I, L, O, U


def token_hash(token: str) -> str:
    """Server hanya menyimpan SHA-256 dari token device, bukan tokennya."""
    return hashlib.sha256(token.encode()).hexdigest()


class Tenant(models.Model):
    """Satu usaha kopi. Sekarang hanya satu baris; struktur siap SaaS (PRD A-02)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid7, editable=False)
    name = models.CharField("Nama usaha", max_length=120)
    receipt_footer = models.CharField("Footer struk", max_length=200, blank=True)
    master_version = models.BigIntegerField(default=1, editable=False)
    next_device_no = models.PositiveIntegerField(default=1, editable=False)

    def __str__(self):
        return self.name


class User(AbstractUser):
    class Role(models.TextChoices):
        OWNER = "OWNER", "Owner"
        MANAGER = "MANAGER", "Manager"
        CASHIER = "CASHIER", "Kasir"

    id = models.UUIDField(primary_key=True, default=uuid.uuid7, editable=False)
    tenant = models.ForeignKey(Tenant, on_delete=models.PROTECT, null=True, blank=True, editable=False)
    role = models.CharField("Peran", max_length=10, choices=Role.choices, default=Role.CASHIER)
    display_name = models.CharField("Nama", max_length=80)
    pin_hash = models.CharField(max_length=128, blank=True, editable=False)
    can_discount = models.BooleanField("Boleh beri diskon", default=False)
    outlets = models.ManyToManyField("core.Outlet", blank=True, related_name="+", verbose_name="Outlet")

    objects = UserManager()
    in_tenant = TenantManager()

    class Meta(AbstractUser.Meta):
        default_manager_name = "objects"


class Outlet(TenantScoped):
    class Type(models.TextChoices):
        OUTLET = "OUTLET", "Outlet tetap"
        MOBILE = "MOBILE", "Keliling"

    id = models.UUIDField(primary_key=True, default=uuid.uuid7, editable=False)
    code = models.CharField("Kode", max_length=10)
    name = models.CharField("Nama", max_length=80)
    type = models.CharField("Tipe", max_length=6, choices=Type.choices, default=Type.MOBILE)
    timezone = models.CharField("Zona waktu", max_length=40, choices=TIMEZONES, default="Asia/Jakarta")
    tax_enabled = models.BooleanField("Pakai pajak", default=False)
    tax_rate_bp = models.PositiveIntegerField("Tarif pajak (basis poin, 1000 = 10%)", default=1000)
    tax_inclusive = models.BooleanField("Harga sudah termasuk pajak", default=True)
    rounding_unit = models.PositiveIntegerField("Pembulatan total (ke bawah)", choices=ROUNDING_UNITS, default=0)
    void_needs_manager = models.BooleanField(
        "Void butuh PIN manager", default=False,
        help_text="Aktifkan untuk outlet tetap; biarkan mati untuk gerobak keliling (rider bekerja sendiri).")
    receipt_header = models.CharField("Header struk", max_length=200, blank=True)
    receipt_footer = models.CharField("Footer struk", max_length=200, blank=True)
    is_active = models.BooleanField("Aktif", default=True)

    class Meta:
        ordering = ["code"]
        constraints = [models.UniqueConstraint(fields=["tenant", "code"], name="uniq_outlet_code_per_tenant")]

    def __str__(self):
        return f"{self.code} — {self.name}"

    def clean(self):
        # Form tidak memuat `tenant`, jadi constraint di atas tidak ikut divalidasi form. Cek manual per tenant.
        if Outlet.objects.filter(code=self.code).exclude(pk=self.pk).exists():
            raise ValidationError({"code": "Kode sudah dipakai outlet lain."})


class Device(TenantScoped):
    id = models.UUIDField(primary_key=True, default=uuid.uuid7, editable=False)
    outlet = models.ForeignKey(Outlet, on_delete=models.PROTECT, verbose_name="Outlet")
    number = models.PositiveIntegerField("Nomor", editable=False)
    name = models.CharField("Nama", max_length=60)
    activation_code = models.CharField(max_length=8, blank=True, db_index=True, editable=False)
    activation_expires_at = models.DateTimeField(null=True, editable=False)
    token_hash = models.CharField(max_length=64, blank=True, db_index=True, editable=False)
    activated_at = models.DateTimeField(null=True, editable=False)
    revoked_at = models.DateTimeField(null=True, editable=False)
    last_sync_at = models.DateTimeField(null=True, editable=False)
    pending_count = models.PositiveIntegerField(default=0, editable=False)
    app_version = models.CharField(max_length=20, blank=True, editable=False)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["tenant", "number"], name="uniq_device_number_per_tenant")]

    def save(self, *args, **kwargs):
        if self._state.adding and not self.number:
            # Nomor device unik per tenant dan tidak pernah dipakai ulang (bagian dari nomor struk).
            tenant_id = self.tenant_id or current_tenant_id()
            Tenant.objects.filter(pk=tenant_id).update(next_device_no=F("next_device_no") + 1)
            self.number = Tenant.objects.get(pk=tenant_id).next_device_no - 1
        super().save(*args, **kwargs)

    def issue_activation_code(self) -> str:
        # ponytail: tanpa cek bentrok; 32^8 kombinasi dan hanya berlaku 15 menit
        self.activation_code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(8))
        self.activation_expires_at = timezone.now() + timedelta(minutes=15)
        self.save(update_fields=["activation_code", "activation_expires_at"])
        return self.activation_code
```

- [ ] **Step 5: Migrasi & jalankan test**

```powershell
.\.venv\Scripts\python.exe manage.py makemigrations core
.\.venv\Scripts\python.exe -m pytest tests/test_tenancy.py tests/test_core.py
```
Expected: `5 passed`.

- [ ] **Step 6: Commit**

```powershell
git add core kaffepos/settings.py tests
git commit -m "feat: scoping tenant fail-closed, outlet, dan device" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Katalog menu dan versi master data

**Files:**
- Create: `backend/catalog/__init__.py` (kosong), `backend/catalog/migrations/__init__.py` (kosong), `backend/catalog/models.py`
- Create: `backend/core/master.py`
- Modify: `backend/core/apps.py`, `backend/core/models.py` (method `Tenant.save`), `backend/kaffepos/settings.py` (INSTALLED_APPS)
- Test: `backend/tests/test_master_version.py`

**Interfaces:**
- Consumes: `TenantScoped` (Task 2), `Tenant`, `User`, `Outlet`.
- Produces: `catalog.models.Category`, `ModifierGroup`, `ModifierOption` (FK `group`, related_name `options`), `Product` (FK `category`, M2M `modifier_groups`, M2M `available_outlets` di mana kosong = semua outlet), `core.master.bump(tenant_id)`. `Tenant.save()` tidak pernah menimpa `master_version`/`next_device_no`.

- [ ] **Step 1: Tulis test yang gagal**

`backend/tests/test_master_version.py`:
```python
from catalog.models import Category, Product
from core.models import Tenant, User


def version(tenant):
    return Tenant.objects.get(pk=tenant.pk).master_version


def test_save_m2m_and_delete_bump_version(tctx, outlet):
    v0 = version(tctx)
    kopi = Category.objects.create(name="Kopi")
    product = Product.objects.create(category=kopi, name="Es Kopi Susu", price=18000)
    v1 = version(tctx)
    assert v1 > v0
    product.available_outlets.add(outlet)
    v2 = version(tctx)
    assert v2 > v1
    product.delete()
    assert version(tctx) > v2


def test_login_timestamp_does_not_bump_version(tctx):
    kasir = User.objects.create_user(username="kasir1", tenant=tctx, display_name="Kasir 1")
    v = version(tctx)
    kasir.save(update_fields=["last_login"])
    assert version(tctx) == v


def test_saving_stale_tenant_keeps_counters(tctx):
    stale = Tenant.objects.get(pk=tctx.pk)
    Category.objects.create(name="Kopi")  # versi di database naik, objek `stale` tidak tahu
    fresh = version(tctx)
    stale.name = "Kopi Baru"
    stale.save()
    assert version(tctx) == fresh + 1  # tidak mundur ke nilai basi, lalu naik karena profil berubah
```

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_master_version.py`
Expected: ERROR `ModuleNotFoundError: No module named 'catalog'`.

- [ ] **Step 3: Implementasi katalog**

`backend/catalog/models.py`:
```python
import uuid

from django.db import models

from core.tenancy import TenantScoped


class Category(TenantScoped):
    id = models.UUIDField(primary_key=True, default=uuid.uuid7, editable=False)
    name = models.CharField("Nama", max_length=60)
    sort = models.PositiveSmallIntegerField("Urutan", default=0)
    is_active = models.BooleanField("Aktif", default=True)

    class Meta:
        ordering = ["sort", "name"]

    def __str__(self):
        return self.name


class ModifierGroup(TenantScoped):
    id = models.UUIDField(primary_key=True, default=uuid.uuid7, editable=False)
    name = models.CharField("Nama", max_length=40)
    required = models.BooleanField("Wajib dipilih", default=False)
    multi = models.BooleanField("Boleh pilih banyak", default=False)
    sort = models.PositiveSmallIntegerField("Urutan", default=0)

    class Meta:
        ordering = ["sort", "name"]

    def __str__(self):
        return self.name


class ModifierOption(TenantScoped):
    id = models.UUIDField(primary_key=True, default=uuid.uuid7, editable=False)
    group = models.ForeignKey(ModifierGroup, on_delete=models.CASCADE, related_name="options", verbose_name="Grup")
    name = models.CharField("Nama", max_length=40)
    price_delta = models.PositiveIntegerField("Tambahan harga", default=0)
    sort = models.PositiveSmallIntegerField("Urutan", default=0)
    is_active = models.BooleanField("Aktif", default=True)

    class Meta:
        ordering = ["sort", "name"]

    def __str__(self):
        return self.name


class Product(TenantScoped):
    id = models.UUIDField(primary_key=True, default=uuid.uuid7, editable=False)
    category = models.ForeignKey(Category, on_delete=models.PROTECT, verbose_name="Kategori")
    name = models.CharField("Nama", max_length=80)
    price = models.PositiveIntegerField("Harga")
    earns_stamp = models.BooleanField("Dapat stamp", default=True)
    modifier_groups = models.ManyToManyField(ModifierGroup, blank=True, related_name="+", verbose_name="Grup modifier")
    available_outlets = models.ManyToManyField(
        "core.Outlet", blank=True, related_name="+", verbose_name="Tersedia di outlet",
        help_text="Kosongkan = tersedia di semua outlet.")
    sort = models.PositiveSmallIntegerField("Urutan", default=0)
    is_active = models.BooleanField("Aktif", default=True)

    class Meta:
        ordering = ["sort", "name"]

    def __str__(self):
        return self.name
```

Di `backend/kaffepos/settings.py`, tambahkan `"catalog",` di akhir `INSTALLED_APPS`.

- [ ] **Step 4: Implementasi versi master**

`backend/core/master.py`:
```python
"""Naikkan Tenant.master_version setiap kali data master berubah, supaya HP mengunduh ulang snapshot
(desain §3.4). Jangan pakai QuerySet.update()/bulk_update() pada model master: keduanya tidak memicu sinyal."""
from django.apps import apps
from django.db.models import F
from django.db.models.signals import m2m_changed, post_delete, post_save

MASTER_MODELS = [
    "core.Tenant", "core.Outlet", "core.User",
    "catalog.Category", "catalog.ModifierGroup", "catalog.ModifierOption", "catalog.Product",
]
MASTER_M2M = [("core.User", "outlets"), ("catalog.Product", "modifier_groups"), ("catalog.Product", "available_outlets")]


def bump(tenant_id):
    apps.get_model("core.Tenant").objects.filter(pk=tenant_id).update(master_version=F("master_version") + 1)


def _tenant_id(instance):
    return instance.pk if instance._meta.label == "core.Tenant" else instance.tenant_id


def _on_save(sender, instance, update_fields=None, **kwargs):
    if update_fields and set(update_fields) <= {"last_login"}:
        return
    if _tenant_id(instance):
        bump(_tenant_id(instance))


def _on_delete(sender, instance, **kwargs):
    if _tenant_id(instance):
        bump(_tenant_id(instance))


def _on_m2m(sender, instance, action, **kwargs):
    if action.startswith("post_") and instance.tenant_id:
        bump(instance.tenant_id)


def connect():
    for label in MASTER_MODELS:
        model = apps.get_model(label)
        post_save.connect(_on_save, sender=model, dispatch_uid=f"master-save-{label}")
        post_delete.connect(_on_delete, sender=model, dispatch_uid=f"master-delete-{label}")
    for label, field in MASTER_M2M:
        through = getattr(apps.get_model(label), field).through
        m2m_changed.connect(_on_m2m, sender=through, dispatch_uid=f"master-m2m-{label}.{field}")
```

Ganti isi `backend/core/apps.py`:
```python
from django.apps import AppConfig


class CoreConfig(AppConfig):
    name = "core"

    def ready(self):
        from . import master

        master.connect()
```

Di `backend/core/models.py`, di dalam `class Tenant`, tambahkan tepat di bawah field `next_device_no` (di atas `def __str__`):
```python
    COUNTERS = ("master_version", "next_device_no")

    def save(self, *args, **kwargs):
        # Counter hanya boleh berubah lewat UPDATE atomik (F()); save() biasa tidak boleh menimpanya
        # dengan nilai basi dari memori.
        if not self._state.adding and kwargs.get("update_fields") is None:
            kwargs["update_fields"] = [f.name for f in self._meta.concrete_fields
                                       if not f.primary_key and f.name not in self.COUNTERS]
        super().save(*args, **kwargs)
```

- [ ] **Step 5: Migrasi & jalankan test**

```powershell
.\.venv\Scripts\python.exe manage.py makemigrations catalog
.\.venv\Scripts\python.exe -m pytest
```
Expected: `8 passed`.

- [ ] **Step 6: Commit**

```powershell
git add catalog core kaffepos/settings.py tests
git commit -m "feat: katalog menu dan versi master data otomatis" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Rumus total transaksi dan test vector bersama

**Files:**
- Create: `shared/totals_cases.json`
- Create: `backend/sales/__init__.py` (kosong), `backend/sales/totals.py`
- Test: `backend/tests/test_totals.py`

**Interfaces:**
- Produces: `sales.totals.half_up(a: int, b: int) -> int`, dan `sales.totals.compute_totals(items, order_discount, tax_enabled, tax_rate_bp, tax_inclusive, rounding_unit) -> {"subtotal", "tax_total", "rounding", "total"}`. `items` berisi dict dengan `unit_price`, `qty`, `discount`, `modifiers` (list dict `price_delta`); key lain diabaikan. Item reward dikirim dengan `unit_price` 0. File `shared/totals_cases.json` juga dipakai test Dart di M2.

- [ ] **Step 1: Tulis test vector & test yang gagal**

`shared/totals_cases.json` (hasilnya sudah diverifikasi saat menulis desain §7.1):
```json
[
  {"name": "2x es kopi susu + large, tanpa pajak",
   "input": {"items": [{"unit_price": 18000, "qty": 2, "discount": 0, "modifiers": [{"price_delta": 5000}]}],
             "order_discount": 0, "tax_enabled": false, "tax_rate_bp": 0, "tax_inclusive": false, "rounding_unit": 0},
   "expected": {"subtotal": 46000, "tax_total": 0, "rounding": 0, "total": 46000}},
  {"name": "pajak eksklusif 10%",
   "input": {"items": [{"unit_price": 18000, "qty": 2, "discount": 0, "modifiers": [{"price_delta": 5000}]}],
             "order_discount": 0, "tax_enabled": true, "tax_rate_bp": 1000, "tax_inclusive": false, "rounding_unit": 0},
   "expected": {"subtotal": 46000, "tax_total": 4600, "rounding": 0, "total": 50600}},
  {"name": "diskon item, pajak 11% half-up, bulat ke bawah Rp100",
   "input": {"items": [{"unit_price": 15000, "qty": 1, "discount": 1450, "modifiers": []}],
             "order_discount": 0, "tax_enabled": true, "tax_rate_bp": 1100, "tax_inclusive": false, "rounding_unit": 100},
   "expected": {"subtotal": 13550, "tax_total": 1491, "rounding": -41, "total": 15000}},
  {"name": "pajak inklusif 10%",
   "input": {"items": [{"unit_price": 18000, "qty": 1, "discount": 0, "modifiers": []}],
             "order_discount": 0, "tax_enabled": true, "tax_rate_bp": 1000, "tax_inclusive": true, "rounding_unit": 0},
   "expected": {"subtotal": 18000, "tax_total": 1636, "rounding": 0, "total": 18000}},
  {"name": "item reward (harga 0) + modifier berbayar",
   "input": {"items": [{"unit_price": 0, "qty": 1, "discount": 0, "modifiers": [{"price_delta": 5000}]},
                       {"unit_price": 18000, "qty": 1, "discount": 0, "modifiers": [{"price_delta": 0}]}],
             "order_discount": 0, "tax_enabled": false, "tax_rate_bp": 0, "tax_inclusive": false, "rounding_unit": 0},
   "expected": {"subtotal": 23000, "tax_total": 0, "rounding": 0, "total": 23000}},
  {"name": "diskon transaksi lalu pajak eksklusif 10%",
   "input": {"items": [{"unit_price": 18000, "qty": 2, "discount": 0, "modifiers": [{"price_delta": 5000}]}],
             "order_discount": 6000, "tax_enabled": true, "tax_rate_bp": 1000, "tax_inclusive": false, "rounding_unit": 0},
   "expected": {"subtotal": 46000, "tax_total": 4000, "rounding": 0, "total": 44000}}
]
```

`backend/tests/test_totals.py`:
```python
import json
from pathlib import Path

import pytest

from sales.totals import compute_totals

CASES = json.loads((Path(__file__).resolve().parents[2] / "shared" / "totals_cases.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
def test_totals_match_shared_vectors(case):
    assert compute_totals(**case["input"]) == case["expected"]
```

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_totals.py`
Expected: ERROR `ModuleNotFoundError: No module named 'sales.totals'`.

- [ ] **Step 3: Implementasi**

`backend/sales/totals.py`:
```python
"""Rumus total transaksi (desain §7.1). HARUS identik dengan versi Dart di app kasir;
keduanya diuji dengan shared/totals_cases.json. Hanya integer, tanpa float."""


def half_up(a: int, b: int) -> int:
    """Pembagian integer, setengah dibulatkan ke atas (a >= 0, b > 0)."""
    return (2 * a + b) // (2 * b)


def compute_totals(items, order_discount, tax_enabled, tax_rate_bp, tax_inclusive, rounding_unit):
    subtotal = sum(
        (i["unit_price"] + sum(m["price_delta"] for m in i["modifiers"])) * i["qty"] - i["discount"]
        for i in items
    )
    net = subtotal - order_discount
    if not tax_enabled:
        tax = 0
    elif tax_inclusive:
        tax = half_up(net * tax_rate_bp, 10000 + tax_rate_bp)
    else:
        tax = half_up(net * tax_rate_bp, 10000)
    before = net + tax if tax_enabled and not tax_inclusive else net
    total = before // rounding_unit * rounding_unit if rounding_unit else before  # selalu ke bawah
    return {"subtotal": subtotal, "tax_total": tax, "rounding": total - before, "total": total}
```

- [ ] **Step 4: Jalankan test**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_totals.py`
Expected: `6 passed`.

- [ ] **Step 5: Commit**

```powershell
git add ..\shared sales tests/test_totals.py
git commit -m "feat: rumus total integer + test vector bersama" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: API dasar dan aktivasi device

**Files:**
- Create: `backend/core/ratelimit.py`
- Create: `backend/api/__init__.py` (kosong), `backend/api/api.py`
- Modify: `backend/kaffepos/urls.py`
- Test: `backend/tests/test_api_device.py`

**Interfaces:**
- Consumes: `Device`, `token_hash` (Task 2).
- Produces:
  - `core.ratelimit.hit(key: str, window_seconds: int) -> int` dan `client_ip(request) -> str`.
  - `api.api.api` (NinjaAPI, di-mount di `/api/v1/`), `ApiError(status, code, message)` yang menghasilkan `{"error": code, "message": message}`. Error validasi request → 400 `invalid_request`.
  - `POST /api/v1/device/activate`.

- [ ] **Step 1: Tulis test yang gagal**

`backend/tests/test_api_device.py`:
```python
import json

from core.models import Device


def post(client, url, body):
    return client.post(url, data=json.dumps(body), content_type="application/json")


def test_activation_returns_token_once(client, tctx, outlet):
    device = Device.objects.create(outlet=outlet, name="HP 1")
    code = device.issue_activation_code()
    r = post(client, "/api/v1/device/activate", {"code": code.lower(), "app_version": "1.0.0"})
    assert r.status_code == 200
    body = r.json()
    assert body["device"] == {"id": str(device.id), "number": device.number}
    assert body["outlet"]["code"] == "GRB01" and len(body["token"]) >= 40
    again = post(client, "/api/v1/device/activate", {"code": code})
    assert again.status_code == 400 and again.json()["error"] == "invalid_code"


def test_activation_is_rate_limited_per_ip(client, db):
    for _ in range(10):
        post(client, "/api/v1/device/activate", {"code": "XXXXXXXX"})
    r = post(client, "/api/v1/device/activate", {"code": "XXXXXXXX"})
    assert r.status_code == 429 and r.json()["error"] == "rate_limited"


def test_malformed_body_is_invalid_request(client, db):
    r = post(client, "/api/v1/device/activate", {"kode": "salah-nama-field"})
    assert r.status_code == 400 and r.json()["error"] == "invalid_request"
```

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_api_device.py`
Expected: FAIL, ketiga test mendapat 404 karena URL belum ada.

- [ ] **Step 3: Implementasi rate-limit**

`backend/core/ratelimit.py`:
```python
"""Rate-limit sederhana di atas cache Django. DatabaseCache berlaku lintas worker tanpa Redis."""
from django.core.cache import cache


def hit(key: str, window_seconds: int) -> int:
    """Catat satu kejadian untuk `key`; kembalikan jumlah kejadian dalam jendela waktu ini."""
    # ponytail: get+set DatabaseCache tidak atomik, jadi hitungan bisa meleset sedikit saat ramai; cukup untuk rate-limit
    cache.add(key, 0, window_seconds)
    try:
        return cache.incr(key)
    except ValueError:  # key kedaluwarsa di antara add() dan incr()
        cache.set(key, 1, window_seconds)
        return 1


def client_ip(request) -> str:
    """IP klien. Di belakang Caddy, alamat asli = nilai TERAKHIR X-Forwarded-For (ditambahkan Caddy)."""
    forwarded = request.META.get("HTTP_X_FORWARDED_FOR")
    return forwarded.split(",")[-1].strip() if forwarded else request.META.get("REMOTE_ADDR", "")
```

- [ ] **Step 4: Implementasi API & aktivasi**

`backend/api/api.py`:
```python
"""API mobile /api/v1 (desain teknis §5)."""
import secrets

from django.utils import timezone
from ninja import NinjaAPI, Schema
from ninja.errors import ValidationError as NinjaValidationError

from core.models import Device, token_hash
from core.ratelimit import client_ip, hit

api = NinjaAPI(title="KaffePOS API", version="1", urls_namespace="api_v1")


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message


@api.exception_handler(ApiError)
def on_api_error(request, exc):
    return api.create_response(request, {"error": exc.code, "message": exc.message}, status=exc.status)


@api.exception_handler(NinjaValidationError)
def on_validation_error(request, exc):
    return api.create_response(request, {"error": "invalid_request", "message": str(exc.errors)[:500]}, status=400)


class ActivateIn(Schema):
    code: str
    app_version: str = ""


@api.post("/device/activate", auth=None)
def activate(request, payload: ActivateIn):
    if hit(f"activate:{client_ip(request)}", 3600) > 10:
        raise ApiError(429, "rate_limited", "Terlalu banyak percobaan aktivasi, coba lagi nanti")
    code = payload.code.strip().upper()
    device = (Device.all_tenants.select_related("outlet")
              .filter(activation_code=code, activated_at__isnull=True, revoked_at__isnull=True,
                      activation_expires_at__gt=timezone.now())
              .first()) if len(code) == 8 else None
    if device is None:
        raise ApiError(400, "invalid_code", "Kode aktivasi salah, kedaluwarsa, atau sudah dipakai")
    token = secrets.token_urlsafe(32)
    device.token_hash, device.activation_code = token_hash(token), ""
    device.activated_at, device.app_version = timezone.now(), payload.app_version[:20]
    device.save()
    return {"token": token,
            "device": {"id": str(device.id), "number": device.number},
            "outlet": {"id": str(device.outlet_id), "code": device.outlet.code, "name": device.outlet.name}}
```

Ganti isi `backend/kaffepos/urls.py`:
```python
from django.urls import path

from api.api import api

urlpatterns = [path("api/v1/", api.urls)]
```

- [ ] **Step 5: Jalankan test**

Run: `.\.venv\Scripts\python.exe -m pytest`
Expected: `17 passed`.

- [ ] **Step 6: Commit**

```powershell
git add api core/ratelimit.py kaffepos/urls.py tests/test_api_device.py
git commit -m "feat: API v1 dan aktivasi device dengan rate-limit" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: PIN staf, autentikasi device, dan snapshot master

**Files:**
- Create: `backend/core/pins.py`, `backend/api/snapshot.py`
- Modify: `backend/api/api.py`, `backend/kaffepos/settings.py` (`MIN_APP_VERSION`), `backend/tests/conftest.py` (fixture `device`, `auth`)
- Test: `backend/tests/test_api_master.py`

**Interfaces:**
- Consumes: `ApiError`, `api` (Task 5); katalog (Task 3); `activate_tenant` (Task 2).
- Produces:
  - `core.pins.make_pin(pin: str) -> str` (format `pbkdf2_sha256$20000$<salt>$<base64>`, ditolak `ValueError` jika bukan 6 digit) dan `check_pin(pin, encoded) -> bool`.
  - `api.api.DeviceAuth` / `device_auth`: `request.auth` = objek `Device`, tenant aktif ter-set. Token kosong/salah → 401 `invalid_token`; dicabut → 401 `device_revoked`.
  - `api.snapshot.build_snapshot(device) -> dict`.
  - `GET /api/v1/sync/master?version=N`.
  - Fixture: `device`, `auth` (dict header Django test client: `HTTP_AUTHORIZATION`, `HTTP_X_APP_VERSION`).

- [ ] **Step 1: Tulis fixture & test yang gagal**

Tambahkan di `backend/tests/conftest.py` (import di atas, fixture di bawah):
```python
from django.utils import timezone

from core.models import Device, token_hash


@pytest.fixture
def device(outlet):
    return Device.objects.create(outlet=outlet, name="HP Kasir 1")


@pytest.fixture
def auth(device):
    """Header Authorization untuk device yang sudah aktif."""
    token = f"token-uji-{device.id.hex}"
    device.token_hash, device.activated_at = token_hash(token), timezone.now()
    device.save()
    return {"HTTP_AUTHORIZATION": f"Bearer {token}", "HTTP_X_APP_VERSION": "1.0.0"}
```

`backend/tests/test_api_master.py`:
```python
import pytest
from django.utils import timezone

from catalog.models import Category, ModifierGroup, ModifierOption, Product
from core.models import Outlet, Tenant, User
from core.pins import check_pin, make_pin


def test_pin_hash_format_and_check():
    encoded = make_pin("123456")
    assert encoded.startswith("pbkdf2_sha256$20000$")
    assert check_pin("123456", encoded) and not check_pin("654321", encoded)


def test_pin_must_be_six_digits():
    with pytest.raises(ValueError):
        make_pin("12a456")


def test_unknown_or_missing_token_rejected(client, db):
    assert client.get("/api/v1/sync/master", HTTP_AUTHORIZATION="Bearer salah").json()["error"] == "invalid_token"
    r = client.get("/api/v1/sync/master")
    assert r.status_code == 401 and r.json()["error"] == "invalid_token"


def test_revoked_device_rejected(client, device, auth):
    device.revoked_at = timezone.now()
    device.save()
    r = client.get("/api/v1/sync/master", **auth)
    assert r.status_code == 401 and r.json()["error"] == "device_revoked"


def test_snapshot_only_contains_this_outlet(client, tctx, outlet, device, auth):
    other = Outlet.objects.create(code="OUT02", name="Outlet Lain", type=Outlet.Type.OUTLET)
    kopi = Category.objects.create(name="Kopi")
    size = ModifierGroup.objects.create(name="Ukuran", required=True)
    ModifierOption.objects.create(group=size, name="Large", price_delta=5000)
    es_kopi = Product.objects.create(category=kopi, name="Es Kopi Susu", price=18000)
    es_kopi.modifier_groups.add(size)
    tubruk = Product.objects.create(category=kopi, name="Kopi Tubruk", price=10000)
    tubruk.available_outlets.add(other)  # hanya di outlet lain
    andi = User.objects.create_user(username="andi", tenant=tctx, display_name="Andi", pin_hash=make_pin("111111"))
    andi.outlets.add(outlet)
    User.objects.create_user(username="sinta", tenant=tctx, display_name="Sinta")  # tidak punya akses outlet ini

    body = client.get("/api/v1/sync/master?version=0", **auth).json()

    snap = body["snapshot"]
    assert body["changed"] is True
    assert [p["name"] for p in snap["products"]] == ["Es Kopi Susu"]
    assert snap["products"][0]["modifier_group_ids"] == [str(size.id)]
    assert [(o["name"], o["price_delta"]) for o in snap["modifier_groups"][0]["options"]] == [("Large", 5000)]
    assert [s["name"] for s in snap["staff"]] == ["Andi"]
    assert check_pin("111111", snap["staff"][0]["pin_hash"])
    assert snap["outlet"]["code"] == "GRB01" and snap["device"]["number"] == device.number


def test_unchanged_version_returns_no_snapshot(client, tctx, device, auth):
    v = Tenant.objects.get(pk=tctx.pk).master_version
    body = client.get(f"/api/v1/sync/master?version={v}", **auth).json()
    assert body == {"changed": False, "version": v, "server_time": body["server_time"]}
    device.refresh_from_db()
    assert device.last_sync_at is not None
```

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_api_master.py`
Expected: ERROR `ModuleNotFoundError: No module named 'core.pins'`.

- [ ] **Step 3: Implementasi PIN**

`backend/core/pins.py`:
```python
"""PIN staf untuk app kasir. Diverifikasi OFFLINE di HP, jadi formatnya harus bisa dihitung ulang di Dart:
pbkdf2_sha256$<iterasi>$<salt>$<base64(PBKDF2-HMAC-SHA256(pin, salt UTF-8, iterasi, 32 byte))>."""
from django.contrib.auth.hashers import PBKDF2PasswordHasher, check_password

# Kenop kalibrasi: verifikasi di HP termurah harus < 300 ms (desain §3.3).
# Hash lama tetap valid karena jumlah iterasi tersimpan di dalam hash.
PIN_ITERATIONS = 20_000


def make_pin(pin: str) -> str:
    if len(pin) != 6 or not pin.isdigit():
        raise ValueError("PIN harus 6 digit angka")
    hasher = PBKDF2PasswordHasher()
    return hasher.encode(pin, hasher.salt(), iterations=PIN_ITERATIONS)


def check_pin(pin: str, encoded: str) -> bool:
    return bool(encoded) and check_password(pin, encoded)
```

- [ ] **Step 4: Implementasi snapshot**

`backend/api/snapshot.py`:
```python
"""Snapshot master data untuk satu device (desain §5). HP mengganti snapshot lamanya secara utuh."""
from django.conf import settings
from django.db.models import Q

from catalog.models import Category, ModifierGroup, Product
from core.models import User

PAYMENT_METHODS = ["CASH", "QRIS", "TRANSFER", "EWALLET"]


def build_snapshot(device):
    outlet, tenant = device.outlet, device.tenant
    staff = (User.in_tenant.filter(is_active=True)
             .filter(Q(role=User.Role.OWNER) | Q(outlets=outlet)).distinct())
    products = (Product.objects.filter(is_active=True, category__is_active=True)
                .filter(Q(available_outlets=None) | Q(available_outlets=outlet)).distinct()
                .prefetch_related("modifier_groups"))
    return {
        "min_app_version": settings.MIN_APP_VERSION,
        "business": {"name": tenant.name, "receipt_footer": tenant.receipt_footer},
        "outlet": {
            "id": str(outlet.id), "code": outlet.code, "name": outlet.name, "type": outlet.type,
            "timezone": outlet.timezone, "tax_enabled": outlet.tax_enabled,
            "tax_rate_bp": outlet.tax_rate_bp, "tax_inclusive": outlet.tax_inclusive,
            "rounding_unit": outlet.rounding_unit, "void_needs_manager": outlet.void_needs_manager,
            "receipt_header": outlet.receipt_header, "receipt_footer": outlet.receipt_footer,
        },
        "device": {"id": str(device.id), "number": device.number},
        "staff": [{"id": str(u.id), "name": u.display_name, "role": u.role,
                   "pin_hash": u.pin_hash, "can_discount": u.can_discount} for u in staff],
        "categories": [{"id": str(c.id), "name": c.name, "sort": c.sort}
                       for c in Category.objects.filter(is_active=True)],
        "products": [{"id": str(p.id), "category_id": str(p.category_id), "name": p.name,
                      "price": p.price, "earns_stamp": p.earns_stamp, "sort": p.sort,
                      "modifier_group_ids": [str(g.id) for g in p.modifier_groups.all()]}
                     for p in products],
        "modifier_groups": [{"id": str(g.id), "name": g.name, "required": g.required,
                             "multi": g.multi, "sort": g.sort,
                             "options": [{"id": str(o.id), "name": o.name, "price_delta": o.price_delta}
                                         for o in g.options.all() if o.is_active]}
                            for g in ModifierGroup.objects.prefetch_related("options")],
        "payment_methods": PAYMENT_METHODS,
        "stamp_rule": None,  # diisi di rencana M3 (loyalty)
    }
```

Di `backend/kaffepos/settings.py`, tambahkan di akhir file:
```python
MIN_APP_VERSION = os.environ.get("MIN_APP_VERSION", "1.0.0")
```

- [ ] **Step 5: Implementasi auth device & endpoint master**

Di `backend/api/api.py`, ganti blok import paling atas:
```python
"""API mobile /api/v1 (desain teknis §5)."""
import secrets

from django.utils import timezone
from ninja import NinjaAPI, Schema
from ninja.errors import AuthenticationError
from ninja.errors import ValidationError as NinjaValidationError
from ninja.security import HttpBearer

from core.models import Device, Tenant, token_hash
from core.ratelimit import client_ip, hit
from core.tenancy import activate_tenant

from .snapshot import build_snapshot
```

Tambahkan tepat di bawah fungsi `on_validation_error`:
```python
@api.exception_handler(AuthenticationError)
def on_missing_token(request, exc):
    return api.create_response(request, {"error": "invalid_token", "message": "Token device wajib diisi"}, status=401)


class DeviceAuth(HttpBearer):
    def authenticate(self, request, token):
        device = (Device.all_tenants.select_related("outlet", "tenant")
                  .filter(token_hash=token_hash(token)).first())
        if device is None:
            raise ApiError(401, "invalid_token", "Token device tidak dikenal")
        if device.revoked_at:
            raise ApiError(401, "device_revoked", "Device sudah dicabut")
        activate_tenant(device.tenant_id)
        return device


device_auth = DeviceAuth()
```

Tambahkan di akhir file:
```python
def master_version(device) -> int:
    return Tenant.objects.values_list("master_version", flat=True).get(pk=device.tenant_id)


@api.get("/sync/master", auth=device_auth)
def sync_master(request, version: int = 0):
    device = request.auth
    current = master_version(device)  # dibaca SEBELUM data, jadi tidak ada perubahan yang terlewat (desain §5)
    Device.all_tenants.filter(pk=device.pk).update(last_sync_at=timezone.now())
    body = {"changed": current != version, "version": current, "server_time": timezone.now()}
    if body["changed"]:
        body["snapshot"] = build_snapshot(device)
    return body
```

- [ ] **Step 6: Jalankan test**

Run: `.\.venv\Scripts\python.exe -m pytest`
Expected: `23 passed`.

- [ ] **Step 7: Commit**

```powershell
git add api core/pins.py kaffepos/settings.py tests
git commit -m "feat: PIN staf, auth device, dan snapshot master" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Model penjualan dan push event shift & kas

**Files:**
- Create: `backend/sales/models.py`, `backend/sales/migrations/__init__.py` (kosong)
- Create: `backend/api/push.py`
- Modify: `backend/api/api.py`, `backend/kaffepos/settings.py` (INSTALLED_APPS)
- Test: `backend/tests/test_api_push.py`

**Interfaces:**
- Consumes: `device_auth`, `master_version`, `api` (Task 6); `TenantScoped` (Task 2).
- Produces:
  - `sales.models`: `Shift` (FK `cash_movements`/`sales` lewat related_name), `CashMovement` (`CashMovement.Direction.IN | OUT`), `Sale` (`Sale.Status.COMPLETED | VOIDED`, related_name `items`, `payments`), `SaleItem` (related_name `modifiers`), `SaleItemModifier`, `Payment` (`Payment.Method.CASH | QRIS | TRANSFER | EWALLET`).
  - `api.push`: `Retry`, `Reject`, `local_time(dt, tz)`, `staff_for(device, staff_id)`, `shift_for(device, shift_id)`, `expected_cash(shift) -> int`, `HANDLERS: dict[str, callable]`, `process_event(device, event_id, type_, data) -> {"id", "status", "reason"?}`.
  - `POST /api/v1/sync/push`.

- [ ] **Step 1: Tulis test yang gagal**

`backend/tests/test_api_push.py`:
```python
import json
import uuid

import pytest
from django.utils import timezone

from core.models import Device, User
from sales.models import CashMovement, Sale, Shift

NOW = "2026-11-19T03:00:00Z"  # = 10:00 WIB


def push(client, auth, *events, pending_after=0):
    body = {"pending_after": pending_after,
            "events": [{"id": str(uuid.uuid4()), "type": t, "data": d} for t, d in events]}
    r = client.post("/api/v1/sync/push", data=json.dumps(body), content_type="application/json", **auth)
    assert r.status_code == 200, r.content
    return [x["status"] for x in r.json()["results"]], r.json()


@pytest.fixture
def kasir(tctx, outlet):
    user = User.objects.create_user(username="andi", tenant=tctx, display_name="Andi")
    user.outlets.add(outlet)
    return user


def shift_opened(shift_id, kasir, cash=100000):
    return ("shift.opened", {"shift_id": str(shift_id), "staff_id": str(kasir.id),
                             "opened_at": NOW, "opening_cash": cash})


def cash_moved(shift_id, kasir, amount=15000, direction="OUT", move_id=None):
    return ("cash.moved", {"id": str(move_id or uuid.uuid4()), "shift_id": str(shift_id),
                           "staff_id": str(kasir.id), "at": NOW, "direction": direction,
                           "amount": amount, "note": "es batu"})


def shift_closed(shift_id, kasir, counted):
    return ("shift.closed", {"shift_id": str(shift_id), "staff_id": str(kasir.id),
                             "closed_at": NOW, "counted_cash": counted})


def test_shift_open_is_idempotent_and_uses_local_date(client, auth, kasir):
    sid = uuid.uuid4()
    assert push(client, auth, shift_opened(sid, kasir))[0] == ["ok"]
    assert push(client, auth, shift_opened(sid, kasir))[0] == ["duplicate"]
    assert Shift.objects.get(pk=sid).business_date.isoformat() == "2026-11-19"


def test_cash_before_shift_is_retried_then_accepted(client, auth, kasir):
    sid, mid = uuid.uuid4(), uuid.uuid4()
    assert push(client, auth, cash_moved(sid, kasir, move_id=mid))[0] == ["retry"]
    assert push(client, auth, shift_opened(sid, kasir), cash_moved(sid, kasir, move_id=mid))[0] == ["ok", "ok"]
    assert CashMovement.objects.get(pk=mid).amount == 15000


def test_invalid_payload_is_rejected_with_field_name(client, auth, kasir):
    statuses, body = push(client, auth, shift_opened(uuid.uuid4(), kasir, cash=-5))
    assert statuses == ["rejected"] and "opening_cash" in body["results"][0]["reason"]


def test_unknown_event_type_is_rejected(client, auth):
    assert push(client, auth, ("member.teleported", {}))[0] == ["rejected"]


def test_shift_close_computes_expected_cash(client, auth, kasir):
    sid = uuid.uuid4()
    statuses, _ = push(client, auth, shift_opened(sid, kasir, cash=100000), cash_moved(sid, kasir, 15000),
                       shift_closed(sid, kasir, counted=80000))
    assert statuses == ["ok", "ok", "ok"]
    shift = Shift.objects.get(pk=sid)
    assert (shift.expected_cash, shift.counted_cash) == (85000, 80000)
    assert push(client, auth, shift_closed(sid, kasir, counted=80000))[0] == ["duplicate"]


def test_push_updates_device_status(client, auth, device):
    push(client, auth, pending_after=7)
    device.refresh_from_db()
    assert (device.pending_count, device.app_version) == (7, "1.0.0") and device.last_sync_at


def test_more_than_100_events_is_invalid_request(client, auth):
    body = {"events": [{"id": str(uuid.uuid4()), "type": "x", "data": {}} for _ in range(101)]}
    r = client.post("/api/v1/sync/push", data=json.dumps(body), content_type="application/json", **auth)
    assert r.status_code == 400 and r.json()["error"] == "invalid_request"
```

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_api_push.py`
Expected: ERROR `ModuleNotFoundError: No module named 'sales.models'`.

- [ ] **Step 3: Implementasi model penjualan**

`backend/sales/models.py`:
```python
"""Data transaksi dari HP (desain §4). ID dibuat di HP; detail transaksi adalah snapshot master."""
import uuid

from django.conf import settings
from django.db import models

from core.tenancy import TenantScoped

USER = settings.AUTH_USER_MODEL


class Shift(TenantScoped):
    id = models.UUIDField(primary_key=True)
    outlet = models.ForeignKey("core.Outlet", on_delete=models.PROTECT, related_name="+")
    device = models.ForeignKey("core.Device", on_delete=models.PROTECT, related_name="+")
    staff = models.ForeignKey(USER, on_delete=models.PROTECT, related_name="+")
    opened_at = models.DateTimeField()
    opening_cash = models.BigIntegerField()
    business_date = models.DateField()
    closed_at = models.DateTimeField(null=True)
    counted_cash = models.BigIntegerField(null=True)
    expected_cash = models.BigIntegerField(null=True)
    received_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [models.Index(fields=["tenant", "business_date"])]


class CashMovement(TenantScoped):
    class Direction(models.TextChoices):
        IN = "IN", "Kas masuk"
        OUT = "OUT", "Kas keluar"

    id = models.UUIDField(primary_key=True)
    shift = models.ForeignKey(Shift, on_delete=models.PROTECT, related_name="cash_movements")
    staff = models.ForeignKey(USER, on_delete=models.PROTECT, related_name="+")
    at = models.DateTimeField()
    direction = models.CharField(max_length=3, choices=Direction.choices)
    amount = models.BigIntegerField()
    note = models.CharField(max_length=120, blank=True)


class Sale(TenantScoped):
    class Status(models.TextChoices):
        COMPLETED = "COMPLETED", "Selesai"
        VOIDED = "VOIDED", "Dibatalkan"

    id = models.UUIDField(primary_key=True)
    outlet = models.ForeignKey("core.Outlet", on_delete=models.PROTECT, related_name="+")
    device = models.ForeignKey("core.Device", on_delete=models.PROTECT, related_name="+")
    shift = models.ForeignKey(Shift, on_delete=models.PROTECT, related_name="sales")
    staff = models.ForeignKey(USER, on_delete=models.PROTECT, related_name="+")
    receipt_no = models.CharField(max_length=40, db_index=True)
    created_at = models.DateTimeField()
    received_at = models.DateTimeField(auto_now_add=True)
    business_date = models.DateField()
    local_hour = models.PositiveSmallIntegerField()
    customer_label = models.CharField(max_length=40, blank=True)
    member_ref = models.CharField(max_length=40, blank=True)  # kode/no HP mentah; ditautkan ke Member di M3
    subtotal = models.BigIntegerField()
    discount_total = models.BigIntegerField(default=0)
    discount_reason = models.CharField(max_length=120, blank=True)
    tax_total = models.BigIntegerField(default=0)
    rounding = models.BigIntegerField(default=0)
    total = models.BigIntegerField()
    tax_enabled = models.BooleanField()
    tax_rate_bp = models.PositiveIntegerField()
    tax_inclusive = models.BooleanField()
    rounding_unit = models.PositiveIntegerField()
    status = models.CharField(max_length=9, choices=Status.choices, default=Status.COMPLETED)
    voided_at = models.DateTimeField(null=True)
    voided_by = models.ForeignKey(USER, on_delete=models.PROTECT, null=True, related_name="+")
    void_approved_by = models.ForeignKey(USER, on_delete=models.PROTECT, null=True, related_name="+")
    void_reason = models.CharField(max_length=120, blank=True)
    flags = models.CharField(max_length=120, blank=True)

    class Meta:
        indexes = [models.Index(fields=["tenant", "business_date", "outlet"])]


class SaleItem(TenantScoped):
    id = models.UUIDField(primary_key=True)
    sale = models.ForeignKey(Sale, on_delete=models.CASCADE, related_name="items")
    product_id = models.UUIDField()  # snapshot: sengaja tanpa FK
    name = models.CharField(max_length=80)
    category_name = models.CharField(max_length=60, blank=True)
    qty = models.PositiveIntegerField()
    unit_price = models.BigIntegerField()
    modifiers_total = models.BigIntegerField(default=0)
    discount = models.BigIntegerField(default=0)
    line_total = models.BigIntegerField()
    is_reward = models.BooleanField(default=False)
    earns_stamp = models.BooleanField(default=False)
    note = models.CharField(max_length=120, blank=True)


class SaleItemModifier(TenantScoped):
    id = models.UUIDField(primary_key=True, default=uuid.uuid7, editable=False)
    sale_item = models.ForeignKey(SaleItem, on_delete=models.CASCADE, related_name="modifiers")
    option_id = models.UUIDField()  # snapshot: sengaja tanpa FK
    group_name = models.CharField(max_length=40)
    name = models.CharField(max_length=40)
    price_delta = models.BigIntegerField()


class Payment(TenantScoped):
    class Method(models.TextChoices):
        CASH = "CASH", "Tunai"
        QRIS = "QRIS", "QRIS"
        TRANSFER = "TRANSFER", "Transfer"
        EWALLET = "EWALLET", "E-wallet"

    id = models.UUIDField(primary_key=True)
    sale = models.ForeignKey(Sale, on_delete=models.CASCADE, related_name="payments")
    method = models.CharField(max_length=8, choices=Method.choices)
    amount = models.BigIntegerField()
    tendered = models.BigIntegerField(null=True)
    change_amount = models.BigIntegerField(null=True)
    reference = models.CharField(max_length=60, blank=True)
```

Di `backend/kaffepos/settings.py`, tambahkan `"sales",` di akhir `INSTALLED_APPS`.

- [ ] **Step 4: Implementasi pemroses event**

`backend/api/push.py`:
```python
"""Proses event outbox dari HP (desain §5).

Setiap event idempotent lewat kunci entitasnya. Penjualan tidak pernah ditolak karena aturan bisnis:
`Reject` hanya untuk data rusak/akses salah, `Retry` untuk ketergantungan yang belum diterima.
"""
from datetime import datetime
from typing import Literal
from uuid import UUID
from zoneinfo import ZoneInfo

from django.db import IntegrityError, transaction
from django.db.models import Sum
from pydantic import AwareDatetime, BaseModel, Field, ValidationError

from core.models import User
from sales.models import CashMovement, Payment, Sale, Shift


class Retry(Exception):
    pass


class Reject(Exception):
    pass


def local_time(dt: datetime, tz: str) -> datetime:
    return dt.astimezone(ZoneInfo(tz))


def staff_for(device, staff_id):
    staff = User.objects.filter(pk=staff_id, tenant_id=device.tenant_id).first()
    if staff is None:
        raise Reject("unknown_staff")
    return staff


def shift_for(device, shift_id):
    shift = Shift.objects.filter(pk=shift_id).first()
    if shift is None:
        raise Retry("shift_unknown")
    if shift.device_id != device.id:
        raise Reject("forbidden")
    return shift


def expected_cash(shift) -> int:
    """Modal + tunai dari penjualan yang tidak di-void + kas masuk − kas keluar (desain §7.5)."""
    cash_sales = (Payment.objects
                  .filter(sale__shift=shift, sale__status=Sale.Status.COMPLETED, method=Payment.Method.CASH)
                  .aggregate(total=Sum("amount"))["total"] or 0)
    moves = dict(shift.cash_movements.values_list("direction").annotate(total=Sum("amount")))
    return shift.opening_cash + cash_sales + moves.get("IN", 0) - moves.get("OUT", 0)


class ShiftOpened(BaseModel):
    shift_id: UUID
    staff_id: UUID
    opened_at: AwareDatetime
    opening_cash: int = Field(ge=0)


def shift_opened(device, data):
    d = ShiftOpened.model_validate(data)
    if Shift.objects.filter(pk=d.shift_id).exists():
        return "duplicate"
    Shift.objects.create(id=d.shift_id, outlet_id=device.outlet_id, device=device,
                         staff=staff_for(device, d.staff_id), opened_at=d.opened_at,
                         opening_cash=d.opening_cash,
                         business_date=local_time(d.opened_at, device.outlet.timezone).date())
    return "ok"


class CashMoved(BaseModel):
    id: UUID
    shift_id: UUID
    staff_id: UUID
    at: AwareDatetime
    direction: Literal["IN", "OUT"]
    amount: int = Field(gt=0)
    note: str = Field("", max_length=120)


def cash_moved(device, data):
    d = CashMoved.model_validate(data)
    if CashMovement.objects.filter(pk=d.id).exists():
        return "duplicate"
    CashMovement.objects.create(id=d.id, shift=shift_for(device, d.shift_id),
                                staff=staff_for(device, d.staff_id), at=d.at,
                                direction=d.direction, amount=d.amount, note=d.note)
    return "ok"


class ShiftClosed(BaseModel):
    shift_id: UUID
    staff_id: UUID
    closed_at: AwareDatetime
    counted_cash: int = Field(ge=0)


def shift_closed(device, data):
    d = ShiftClosed.model_validate(data)
    shift = shift_for(device, d.shift_id)
    if shift.closed_at:
        return "duplicate"
    staff_for(device, d.staff_id)
    shift.closed_at, shift.counted_cash = d.closed_at, d.counted_cash
    shift.expected_cash = expected_cash(shift)
    shift.save(update_fields=["closed_at", "counted_cash", "expected_cash"])
    return "ok"


HANDLERS = {
    "shift.opened": shift_opened,
    "cash.moved": cash_moved,
    "shift.closed": shift_closed,
}


def process_event(device, event_id, type_, data) -> dict:
    result = {"id": str(event_id)}
    handler = HANDLERS.get(type_)
    if handler is None:
        return result | {"status": "rejected", "reason": f"unknown_type: {type_}"}
    try:
        with transaction.atomic():  # savepoint per event: satu event gagal tidak membatalkan event lain
            return result | {"status": handler(device, data)}
    except Retry as e:
        return result | {"status": "retry", "reason": str(e)}
    except Reject as e:
        return result | {"status": "rejected", "reason": str(e)}
    except ValidationError as e:
        field = ".".join(str(part) for part in e.errors()[0]["loc"])
        return result | {"status": "rejected", "reason": f"invalid_payload: {field}"}
    except IntegrityError:  # event yang sama sedang diproses request lain (sync foreground & background)
        return result | {"status": "duplicate"}
```

- [ ] **Step 5: Implementasi endpoint push**

Di `backend/api/api.py`, lakukan tiga perubahan import (baris import lain tetap):
- tambahkan `from uuid import UUID` tepat di bawah `import secrets`;
- ubah `from ninja import NinjaAPI, Schema` menjadi `from ninja import Field, NinjaAPI, Schema`;
- tambahkan `from .push import process_event` tepat di atas `from .snapshot import build_snapshot`.

Tambahkan di akhir file:
```python
class EventIn(Schema):
    id: UUID
    type: str
    data: dict


class PushIn(Schema):
    pending_after: int = Field(0, ge=0)
    events: list[EventIn] = Field(max_length=100)


@api.post("/sync/push", auth=device_auth)
def sync_push(request, payload: PushIn):
    device = request.auth
    results = [process_event(device, e.id, e.type, e.data) for e in payload.events]
    Device.all_tenants.filter(pk=device.pk).update(
        last_sync_at=timezone.now(), pending_count=payload.pending_after,
        app_version=request.headers.get("X-App-Version", "")[:20])
    return {"results": results, "server_time": timezone.now(), "master_version": master_version(device)}
```

- [ ] **Step 6: Migrasi & jalankan test**

```powershell
.\.venv\Scripts\python.exe manage.py makemigrations sales
.\.venv\Scripts\python.exe -m pytest
```
Expected: `30 passed`.

- [ ] **Step 7: Commit**

```powershell
git add api sales kaffepos/settings.py tests/test_api_push.py
git commit -m "feat: model penjualan dan push event shift & kas" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Event penjualan dan void

**Files:**
- Modify: `backend/api/push.py`
- Test: `backend/tests/test_api_push.py` (tambah test)

**Interfaces:**
- Consumes: `compute_totals` (Task 4), `shift_for`, `staff_for`, `local_time`, `HANDLERS` (Task 7).
- Produces: handler `sale.completed` dan `sale.voided`. Flag penjualan: `total_mismatch`, `duplicate_receipt_no`, `clock_ahead` (dipisah koma di `Sale.flags`). Void yang datang sebelum penjualannya → `retry: sale_unknown`.

- [ ] **Step 1: Tulis test yang gagal**

Tambahkan di akhir `backend/tests/test_api_push.py`:
```python
def sale_event(sale_id, shift_id, kasir, total=46000, receipt="GRB01-1-261119-0001"):
    return ("sale.completed", {
        "sale_id": str(sale_id), "shift_id": str(shift_id), "staff_id": str(kasir.id),
        "receipt_no": receipt, "created_at": NOW, "customer_label": "Budi",
        "member": {"phone": "+6281234567890"},
        "pricing": {"tax_enabled": False, "tax_rate_bp": 0, "tax_inclusive": False, "rounding_unit": 0},
        "items": [{"id": str(uuid.uuid4()), "product_id": str(uuid.uuid4()), "name": "Es Kopi Susu",
                   "category_name": "Kopi", "qty": 2, "unit_price": 18000, "discount": 0,
                   "earns_stamp": True, "is_reward": False, "note": "",
                   "modifiers": [{"option_id": str(uuid.uuid4()), "group_name": "Ukuran",
                                  "name": "Large", "price_delta": 5000}]}],
        "order_discount": 0, "discount_reason": None,
        "subtotal": 46000, "tax_total": 0, "rounding": 0, "total": total,
        "payments": [{"id": str(uuid.uuid4()), "method": "CASH", "amount": 46000,
                      "tendered": 50000, "change": 4000, "reference": None}]})


def sale_voided(sale_id, kasir):
    return ("sale.voided", {"sale_id": str(sale_id), "staff_id": str(kasir.id), "approved_by_id": None,
                            "voided_at": NOW, "reason": "salah input"})


def test_sale_is_stored_once_with_snapshot(client, auth, kasir):
    sid, sale_id = uuid.uuid4(), uuid.uuid4()
    assert push(client, auth, shift_opened(sid, kasir), sale_event(sale_id, sid, kasir))[0] == ["ok", "ok"]
    assert push(client, auth, sale_event(sale_id, sid, kasir))[0] == ["duplicate"]
    sale = Sale.objects.get(pk=sale_id)
    assert (sale.total, sale.flags, sale.local_hour, sale.member_ref) == (46000, "", 10, "+6281234567890")
    item = sale.items.get()
    assert (item.line_total, item.modifiers.get().name) == (46000, "Large")
    assert sale.payments.get().change_amount == 4000


def test_wrong_total_is_accepted_and_flagged(client, auth, kasir):
    sid, sale_id = uuid.uuid4(), uuid.uuid4()
    push(client, auth, shift_opened(sid, kasir), sale_event(sale_id, sid, kasir, total=40000))
    assert Sale.objects.get(pk=sale_id).flags == "total_mismatch"


def test_duplicate_receipt_number_is_flagged(client, auth, kasir):
    sid, first, second = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    push(client, auth, shift_opened(sid, kasir), sale_event(first, sid, kasir), sale_event(second, sid, kasir))
    assert Sale.objects.get(pk=second).flags == "duplicate_receipt_no"


def test_void_is_idempotent_and_excluded_from_expected_cash(client, auth, kasir):
    sid, keep, cancel = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    statuses, _ = push(client, auth, shift_opened(sid, kasir),
                       sale_event(keep, sid, kasir, receipt="R-1"), sale_event(cancel, sid, kasir, receipt="R-2"),
                       sale_voided(cancel, kasir), shift_closed(sid, kasir, counted=146000))
    assert statuses == ["ok"] * 5
    assert Sale.objects.get(pk=cancel).status == Sale.Status.VOIDED
    assert Shift.objects.get(pk=sid).expected_cash == 146000  # modal 100.000 + tunai 46.000
    assert push(client, auth, sale_voided(cancel, kasir))[0] == ["duplicate"]


def test_void_before_sale_is_retried(client, auth, kasir):
    assert push(client, auth, sale_voided(uuid.uuid4(), kasir))[0] == ["retry"]


def test_shift_of_another_device_is_forbidden(client, auth, kasir, outlet):
    other = Device.objects.create(outlet=outlet, name="HP lain")
    sid = uuid.uuid4()
    Shift.objects.create(id=sid, outlet=outlet, device=other, staff=kasir, opened_at=timezone.now(),
                         opening_cash=0, business_date=timezone.localdate())
    statuses, body = push(client, auth, sale_event(uuid.uuid4(), sid, kasir))
    assert statuses == ["rejected"] and body["results"][0]["reason"] == "forbidden"
```

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_api_push.py`
Expected: FAIL. Test baru mendapat status `rejected` (`unknown_type: sale.completed`) di tempat yang mengharapkan `ok`/`retry`.

- [ ] **Step 3: Implementasi**

Di `backend/api/push.py`, ubah import menjadi:
```python
from datetime import datetime, timedelta
from typing import Literal
from uuid import UUID
from zoneinfo import ZoneInfo

from django.db import IntegrityError, transaction
from django.db.models import Sum
from django.utils import timezone
from pydantic import AwareDatetime, BaseModel, Field, ValidationError

from core.models import User
from sales.models import CashMovement, Payment, Sale, SaleItem, SaleItemModifier, Shift
from sales.totals import compute_totals
```

Tambahkan tepat di atas baris `HANDLERS = {`:
```python
class ModifierIn(BaseModel):
    option_id: UUID
    group_name: str = Field(max_length=40)
    name: str = Field(max_length=40)
    price_delta: int = Field(ge=0)


class ItemIn(BaseModel):
    id: UUID
    product_id: UUID
    name: str = Field(max_length=80)
    category_name: str = Field("", max_length=60)
    qty: int = Field(gt=0)
    unit_price: int = Field(ge=0)  # item reward dikirim dengan unit_price 0
    discount: int = Field(0, ge=0)
    earns_stamp: bool = False
    is_reward: bool = False
    note: str = Field("", max_length=120)
    modifiers: list[ModifierIn] = []


class PaymentIn(BaseModel):
    id: UUID
    method: Literal["CASH", "QRIS", "TRANSFER", "EWALLET"]
    amount: int = Field(ge=0)
    tendered: int | None = Field(None, ge=0)
    change: int | None = Field(None, ge=0)
    reference: str | None = Field(None, max_length=60)


class PricingIn(BaseModel):
    tax_enabled: bool
    tax_rate_bp: int = Field(ge=0, le=10000)
    tax_inclusive: bool
    rounding_unit: Literal[0, 100, 500, 1000]


class MemberRefIn(BaseModel):
    code: str | None = Field(None, max_length=40)
    phone: str | None = Field(None, max_length=40)


class SaleCompleted(BaseModel):
    sale_id: UUID
    shift_id: UUID
    staff_id: UUID
    receipt_no: str = Field(max_length=40)
    created_at: AwareDatetime
    customer_label: str = Field("", max_length=40)
    member: MemberRefIn | None = None
    pricing: PricingIn
    items: list[ItemIn] = Field(min_length=1)
    order_discount: int = Field(0, ge=0)
    discount_reason: str | None = Field(None, max_length=120)
    subtotal: int
    tax_total: int
    rounding: int
    total: int
    payments: list[PaymentIn] = Field(min_length=1)


def sale_completed(device, data):
    d = SaleCompleted.model_validate(data)
    if Sale.objects.filter(pk=d.sale_id).exists():
        return "duplicate"
    shift = shift_for(device, d.shift_id)
    calc = compute_totals([i.model_dump() for i in d.items], d.order_discount, **d.pricing.model_dump())
    flags = []
    if calc != {"subtotal": d.subtotal, "tax_total": d.tax_total, "rounding": d.rounding, "total": d.total}:
        flags.append("total_mismatch")
    if Sale.objects.filter(receipt_no=d.receipt_no).exists():
        flags.append("duplicate_receipt_no")
    if d.created_at > timezone.now() + timedelta(minutes=5):
        flags.append("clock_ahead")
    sale = Sale.objects.create(
        id=d.sale_id, outlet_id=device.outlet_id, device=device, shift=shift,
        staff=staff_for(device, d.staff_id), receipt_no=d.receipt_no, created_at=d.created_at,
        business_date=shift.business_date,
        local_hour=local_time(d.created_at, device.outlet.timezone).hour,
        customer_label=d.customer_label,
        member_ref=(d.member.code or d.member.phone or "") if d.member else "",
        subtotal=d.subtotal, discount_total=sum(i.discount for i in d.items) + d.order_discount,
        discount_reason=d.discount_reason or "", tax_total=d.tax_total, rounding=d.rounding,
        total=d.total, flags=",".join(flags), **d.pricing.model_dump())
    for i in d.items:
        modifiers_total = sum(m.price_delta for m in i.modifiers)
        item = SaleItem.objects.create(
            id=i.id, sale=sale, product_id=i.product_id, name=i.name, category_name=i.category_name,
            qty=i.qty, unit_price=i.unit_price, modifiers_total=modifiers_total, discount=i.discount,
            line_total=(i.unit_price + modifiers_total) * i.qty - i.discount,
            is_reward=i.is_reward, earns_stamp=i.earns_stamp, note=i.note)
        for m in i.modifiers:
            SaleItemModifier.objects.create(sale_item=item, option_id=m.option_id, group_name=m.group_name,
                                            name=m.name, price_delta=m.price_delta)
    for p in d.payments:
        Payment.objects.create(id=p.id, sale=sale, method=p.method, amount=p.amount, tendered=p.tendered,
                               change_amount=p.change, reference=p.reference or "")
    return "ok"


class SaleVoided(BaseModel):
    sale_id: UUID
    staff_id: UUID
    approved_by_id: UUID | None = None
    voided_at: AwareDatetime
    reason: str = Field(min_length=1, max_length=120)


def sale_voided(device, data):
    d = SaleVoided.model_validate(data)
    sale = Sale.objects.filter(pk=d.sale_id).first()
    if sale is None:
        raise Retry("sale_unknown")
    if sale.device_id != device.id:
        raise Reject("forbidden")
    if sale.status == Sale.Status.VOIDED:
        return "duplicate"
    sale.status, sale.voided_at, sale.void_reason = Sale.Status.VOIDED, d.voided_at, d.reason
    sale.voided_by = staff_for(device, d.staff_id)
    sale.void_approved_by = staff_for(device, d.approved_by_id) if d.approved_by_id else None
    sale.save(update_fields=["status", "voided_at", "void_reason", "voided_by", "void_approved_by"])
    return "ok"
```

Ganti blok `HANDLERS` menjadi:
```python
HANDLERS = {
    "shift.opened": shift_opened,
    "cash.moved": cash_moved,
    "sale.completed": sale_completed,
    "sale.voided": sale_voided,
    "shift.closed": shift_closed,
}
```

- [ ] **Step 4: Jalankan test**

Run: `.\.venv\Scripts\python.exe -m pytest`
Expected: `36 passed`.

- [ ] **Step 5: Commit**

```powershell
git add api/push.py tests/test_api_push.py
git commit -m "feat: event penjualan & void dengan flag, tanpa menolak penjualan" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Login dashboard dan layout dasar

**Files:**
- Create: `backend/dashboard/__init__.py` (kosong), `backend/dashboard/forms.py`, `backend/dashboard/views.py`, `backend/dashboard/urls.py`
- Create: `backend/dashboard/templates/dashboard/base.html`, `login.html`, `home.html`
- Modify: `backend/kaffepos/settings.py`, `backend/kaffepos/urls.py`, `backend/tests/conftest.py` (fixture `owner`, `owner_client`)
- Test: `backend/tests/test_dashboard_auth.py`

**Interfaces:**
- Consumes: `hit`, `client_ip` (Task 5); `TenantMiddleware` (Task 2).
- Produces: `dashboard.views.OwnerRequired` (mixin: login + role OWNER, selain itu 403), `Login`, `Home`; `dashboard.forms.LoginForm`. Nama URL: `login`, `logout`, `home`. Fixture: `owner` (password `rahasia-123`, display_name `Pak Owner`), `owner_client`.

- [ ] **Step 1: Tulis fixture & test yang gagal**

Tambahkan di `backend/tests/conftest.py`:
```python
from core.models import User


@pytest.fixture
def owner(tctx):
    return User.objects.create_user(username="owner", password="rahasia-123", tenant=tctx,
                                    role=User.Role.OWNER, display_name="Pak Owner")


@pytest.fixture
def owner_client(client, owner):
    client.force_login(owner)
    return client
```

`backend/tests/test_dashboard_auth.py`:
```python
from core.models import User


def test_owner_can_log_in(client, owner):
    r = client.post("/login/", {"username": "owner", "password": "rahasia-123"})
    assert r.status_code == 302
    assert "Pak Owner" in client.get("/").content.decode()


def test_cashier_cannot_log_in(client, tctx):
    User.objects.create_user(username="kasir", password="rahasia-123", tenant=tctx, display_name="Kasir")
    r = client.post("/login/", {"username": "kasir", "password": "rahasia-123"})
    assert r.status_code == 200 and "tidak punya akses" in r.content.decode()


def test_login_blocked_after_five_failures(client, owner):
    for _ in range(5):
        client.post("/login/", {"username": "owner", "password": "salah"})
    r = client.post("/login/", {"username": "owner", "password": "rahasia-123"})
    assert r.status_code == 200 and "Terlalu banyak percobaan" in r.content.decode()


def test_home_requires_login(client, db):
    assert client.get("/").status_code == 302
```

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_dashboard_auth.py`
Expected: FAIL (404 untuk `/login/` dan `/`).

- [ ] **Step 3: Implementasi form & view**

`backend/dashboard/forms.py`:
```python
from django import forms
from django.contrib.auth.forms import AuthenticationForm
from django.core.cache import cache

from core.models import User
from core.ratelimit import client_ip, hit

LOGIN_LIMIT, LOGIN_WINDOW = 5, 15 * 60


class LoginForm(AuthenticationForm):
    def clean(self):
        key = f"login:{self.data.get('username', '')}:{client_ip(self.request)}"
        if (cache.get(key) or 0) >= LOGIN_LIMIT:
            raise forms.ValidationError("Terlalu banyak percobaan gagal. Coba lagi 15 menit lagi.")
        try:
            return super().clean()
        except forms.ValidationError:
            hit(key, LOGIN_WINDOW)  # hanya kegagalan yang dihitung
            raise

    def confirm_login_allowed(self, user):
        super().confirm_login_allowed(user)
        if user.tenant_id is None or user.role not in (User.Role.OWNER, User.Role.MANAGER):
            raise forms.ValidationError("Akun ini tidak punya akses dashboard.", code="no_access")
```

`backend/dashboard/views.py`:
```python
from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.contrib.auth.views import LoginView
from django.views.generic import TemplateView

from core.models import User

from .forms import LoginForm


class OwnerRequired(LoginRequiredMixin, UserPassesTestMixin):
    """Halaman kelola data master hanya untuk owner. Akses manager untuk laporan menyusul di M4."""

    def test_func(self):
        return self.request.user.role == User.Role.OWNER


class Login(LoginView):
    template_name = "dashboard/login.html"
    form_class = LoginForm


class Home(LoginRequiredMixin, TemplateView):
    template_name = "dashboard/home.html"
```

`backend/dashboard/urls.py`:
```python
from django.contrib.auth.views import LogoutView
from django.urls import path

from . import views

urlpatterns = [
    path("login/", views.Login.as_view(), name="login"),
    path("logout/", LogoutView.as_view(), name="logout"),
    path("", views.Home.as_view(), name="home"),
]
```

Ganti isi `backend/kaffepos/urls.py`:
```python
from django.urls import include, path

from api.api import api

urlpatterns = [
    path("api/v1/", api.urls),
    path("", include("dashboard.urls")),
]
```

Di `backend/kaffepos/settings.py`, tambahkan `"dashboard",` di akhir `INSTALLED_APPS`, lalu tambahkan di akhir file:
```python
LOGIN_URL = "login"
LOGIN_REDIRECT_URL = "home"
LOGOUT_REDIRECT_URL = "login"
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator", "OPTIONS": {"min_length": 10}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]
```

- [ ] **Step 4: Template**

`backend/dashboard/templates/dashboard/base.html`:
```html
<!doctype html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{% block title %}KaffePOS{% endblock %}</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css">
</head>
<body>
<main class="container">
  {% if user.is_authenticated %}
  <nav>
    <ul><li><strong>KaffePOS</strong></li></ul>
    <ul>
      <li><a href="{% url 'home' %}">Beranda</a></li>
      <li><form method="post" action="{% url 'logout' %}">{% csrf_token %}<button class="outline">Keluar</button></form></li>
    </ul>
  </nav>
  {% endif %}
  {% block content %}{% endblock %}
</main>
</body>
</html>
```

`backend/dashboard/templates/dashboard/login.html`:
```html
{% extends "dashboard/base.html" %}
{% block content %}
<article style="max-width: 420px; margin: 4rem auto">
  <h2>Masuk</h2>
  <form method="post">{% csrf_token %}
    {{ form.as_div }}
    <button type="submit">Masuk</button>
  </form>
</article>
{% endblock %}
```

`backend/dashboard/templates/dashboard/home.html`:
```html
{% extends "dashboard/base.html" %}
{% block content %}
<h2>Halo, {{ user.display_name }}</h2>
<p>Ringkasan penjualan menyusul di M4. Kelola data master lewat menu di atas.</p>
{% endblock %}
```

- [ ] **Step 5: Jalankan test**

Run: `.\.venv\Scripts\python.exe -m pytest`
Expected: `40 passed`.

- [ ] **Step 6: Commit**

```powershell
git add dashboard kaffepos tests
git commit -m "feat: login dashboard dengan pembatasan role & rate-limit" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Dashboard data master (outlet, kategori, modifier, produk)

**Files:**
- Create: `backend/dashboard/crud.py`
- Create: `backend/dashboard/templates/dashboard/list.html`, `form.html`
- Modify: `backend/dashboard/urls.py`, `backend/dashboard/templates/dashboard/base.html`
- Test: `backend/tests/test_dashboard_crud.py`

**Interfaces:**
- Consumes: `OwnerRequired` (Task 9); model katalog (Task 3); `Outlet` (Task 2).
- Produces: `dashboard.crud.crud(model_cls, form_fields, columns, prefix, title, manager="objects", form_cls=None) -> list[URLPattern]` dengan nama URL `{prefix}_list`, `{prefix}_create`, `{prefix}_update`. Prefix yang dipakai: `outlet`, `kategori`, `modifier`, `opsi`, `produk`.

- [ ] **Step 1: Tulis test yang gagal**

`backend/tests/test_dashboard_crud.py`:
```python
from catalog.models import Category, ModifierGroup, Product
from core.models import Outlet, Tenant, User
from core.tenancy import tenant_context


def test_owner_creates_outlet_and_duplicate_code_is_rejected(owner_client):
    data = {"code": "GRB02", "name": "Gerobak Kuningan", "type": "MOBILE", "timezone": "Asia/Jakarta",
            "tax_rate_bp": 1000, "rounding_unit": 0}
    assert owner_client.post("/outlet/baru/", data).status_code == 302
    r = owner_client.post("/outlet/baru/", data)
    assert r.status_code == 200 and "Kode sudah dipakai" in r.content.decode()
    assert Outlet.objects.filter(code="GRB02").count() == 1


def test_product_form_only_offers_own_categories(owner_client, tctx):
    Category.objects.create(name="Kopi")
    other = Tenant.objects.create(name="Usaha Lain")
    with tenant_context(other.id):
        Category.objects.create(name="Kategori Rahasia")
    html = owner_client.get("/produk/baru/").content.decode()
    assert "Kopi" in html and "Kategori Rahasia" not in html


def test_owner_creates_product_with_modifier_group(owner_client, tctx):
    kopi = Category.objects.create(name="Kopi")
    size = ModifierGroup.objects.create(name="Ukuran", required=True)
    r = owner_client.post("/produk/baru/", {"category": kopi.pk, "name": "Es Kopi Susu", "price": 18000,
                                            "earns_stamp": "on", "modifier_groups": [size.pk],
                                            "sort": 1, "is_active": "on"})
    assert r.status_code == 302
    assert list(Product.objects.get(name="Es Kopi Susu").modifier_groups.all()) == [size]
    assert "Es Kopi Susu" in owner_client.get("/produk/").content.decode()


def test_manager_cannot_open_master_data_pages(client, tctx):
    manager = User.objects.create_user(username="mgr", password="rahasia-123", tenant=tctx,
                                       role=User.Role.MANAGER, display_name="Mgr")
    client.force_login(manager)
    assert client.get("/produk/").status_code == 403
```

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_dashboard_crud.py`
Expected: FAIL (404 untuk `/outlet/baru/`, `/produk/…`).

- [ ] **Step 3: Implementasi CRUD generik**

`backend/dashboard/crud.py`:
```python
"""Halaman daftar/tambah/ubah generik untuk data master. Semua query lewat manager ber-tenant,
jadi objek usaha lain otomatis 404 dan tidak muncul di pilihan form."""
from django.urls import path, reverse_lazy
from django.views.generic import CreateView, ListView, UpdateView

from .views import OwnerRequired


def display(obj, field):
    getter = getattr(obj, f"get_{field}_display", None)
    value = getter() if getter else getattr(obj, field)
    if isinstance(value, bool):
        return "Ya" if value else "Tidak"
    return value


def crud(model_cls, form_fields, columns, prefix, title, manager="objects", form_cls=None):
    def scoped():
        return getattr(model_cls, manager).all()

    class List(OwnerRequired, ListView):
        template_name = "dashboard/list.html"

        def get_queryset(self):
            return scoped()

        def get_context_data(self, **kwargs):
            ctx = super().get_context_data(**kwargs)
            ctx.update(
                title=title, prefix=prefix,
                headers=[model_cls._meta.get_field(c).verbose_name for c in columns],
                rows=[(o.pk, [display(o, c) for c in columns]) for o in ctx["object_list"]],
            )
            return ctx

    class Edit(OwnerRequired):
        model = model_cls
        fields = None if form_cls else form_fields
        form_class = form_cls
        template_name = "dashboard/form.html"
        success_url = reverse_lazy(f"{prefix}_list")
        extra_context = {"title": title}

        def get_queryset(self):
            return scoped()

    class Create(Edit, CreateView):
        pass

    class Update(Edit, UpdateView):
        pass

    return [
        path(f"{prefix}/", List.as_view(), name=f"{prefix}_list"),
        path(f"{prefix}/baru/", Create.as_view(), name=f"{prefix}_create"),
        path(f"{prefix}/<uuid:pk>/", Update.as_view(), name=f"{prefix}_update"),
    ]
```

`backend/dashboard/templates/dashboard/list.html`:
```html
{% extends "dashboard/base.html" %}
{% block content %}
<h2>{{ title }}</h2>
<p><a href="{% url prefix|add:'_create' %}" role="button">Tambah</a></p>
<table>
  <thead><tr>{% for h in headers %}<th>{{ h|capfirst }}</th>{% endfor %}<th></th></tr></thead>
  <tbody>
  {% for pk, cells in rows %}
    <tr>{% for c in cells %}<td>{{ c }}</td>{% endfor %}<td><a href="{% url prefix|add:'_update' pk %}">Ubah</a></td></tr>
  {% empty %}
    <tr><td colspan="99">Belum ada data.</td></tr>
  {% endfor %}
  </tbody>
</table>
{% endblock %}
```

`backend/dashboard/templates/dashboard/form.html`:
```html
{% extends "dashboard/base.html" %}
{% block content %}
<h2>{{ title }}</h2>
<form method="post">{% csrf_token %}
  {{ form.as_div }}
  <button type="submit">Simpan</button>
</form>
{% endblock %}
```

Ganti isi `backend/dashboard/urls.py`:
```python
from django.contrib.auth.views import LogoutView
from django.urls import path

from catalog.models import Category, ModifierGroup, ModifierOption, Product
from core.models import Outlet

from . import views
from .crud import crud

urlpatterns = [
    path("login/", views.Login.as_view(), name="login"),
    path("logout/", LogoutView.as_view(), name="logout"),
    path("", views.Home.as_view(), name="home"),
    *crud(Outlet, ["code", "name", "type", "timezone", "tax_enabled", "tax_rate_bp", "tax_inclusive",
                   "rounding_unit", "void_needs_manager", "receipt_header", "receipt_footer", "is_active"],
          ["code", "name", "type", "is_active"], "outlet", "Outlet & Gerobak"),
    *crud(Category, ["name", "sort", "is_active"], ["name", "sort", "is_active"], "kategori", "Kategori"),
    *crud(ModifierGroup, ["name", "required", "multi", "sort"], ["name", "required", "multi"],
          "modifier", "Grup Modifier"),
    *crud(ModifierOption, ["group", "name", "price_delta", "sort", "is_active"],
          ["group", "name", "price_delta", "is_active"], "opsi", "Opsi Modifier"),
    *crud(Product, ["category", "name", "price", "earns_stamp", "modifier_groups", "available_outlets",
                    "sort", "is_active"], ["name", "category", "price", "is_active"], "produk", "Produk"),
]
```

Di `backend/dashboard/templates/dashboard/base.html`, ganti baris `<li><a href="{% url 'home' %}">Beranda</a></li>` menjadi:
```html
      <li><a href="{% url 'home' %}">Beranda</a></li>
      {% if user.role == "OWNER" %}
      <li><a href="{% url 'outlet_list' %}">Outlet</a></li>
      <li><a href="{% url 'kategori_list' %}">Kategori</a></li>
      <li><a href="{% url 'produk_list' %}">Produk</a></li>
      <li><a href="{% url 'modifier_list' %}">Modifier</a></li>
      <li><a href="{% url 'opsi_list' %}">Opsi</a></li>
      {% endif %}
```

- [ ] **Step 4: Jalankan test**

Run: `.\.venv\Scripts\python.exe -m pytest`
Expected: `44 passed`.

- [ ] **Step 5: Commit**

```powershell
git add dashboard tests/test_dashboard_crud.py
git commit -m "feat: dashboard kelola outlet, kategori, modifier, produk" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Dashboard staf (PIN & password) dan device (kode aktivasi & cabut)

**Files:**
- Modify: `backend/dashboard/forms.py` (tambah `StaffForm`), `backend/dashboard/views.py` (tambah view device), `backend/dashboard/urls.py`, `backend/dashboard/templates/dashboard/base.html`
- Create: `backend/dashboard/templates/dashboard/device_list.html`, `device_detail.html`
- Test: `backend/tests/test_dashboard_staff_device.py`

**Interfaces:**
- Consumes: `crud()` (Task 10), `make_pin`/`check_pin` (Task 6), `Device.issue_activation_code()` (Task 2), `User.in_tenant` (Task 2).
- Produces: `dashboard.forms.StaffForm`; view `DeviceList`, `DeviceCreate`, `DeviceDetail` (POST `revoke` mencabut device, POST lain membuat kode baru jika device belum aktif). Nama URL: `staf_list`, `staf_create`, `staf_update`, `device_list`, `device_create`, `device_detail`.

- [ ] **Step 1: Tulis test yang gagal**

`backend/tests/test_dashboard_staff_device.py`:
```python
from core.models import Device, Tenant, User
from core.pins import check_pin


def test_create_cashier_with_pin(owner_client, outlet):
    r = owner_client.post("/staf/baru/", {"display_name": "Andi", "username": "andi", "role": "CASHIER",
                                          "outlets": [outlet.pk], "is_active": "on", "pin": "123456"})
    assert r.status_code == 302
    andi = User.objects.get(username="andi")
    assert check_pin("123456", andi.pin_hash) and not andi.has_usable_password()
    assert andi.tenant_id == outlet.tenant_id and list(andi.outlets.all()) == [outlet]


def test_new_manager_requires_password(owner_client):
    r = owner_client.post("/staf/baru/", {"display_name": "Mgr", "username": "mgr", "role": "MANAGER",
                                          "is_active": "on", "pin": "222222"})
    assert r.status_code == 200 and "butuh password" in r.content.decode()


def test_staff_list_hides_other_tenants(owner_client):
    other = Tenant.objects.create(name="Usaha Lain")
    User.objects.create_user(username="orang-lain", tenant=other, display_name="Orang Lain")
    html = owner_client.get("/staf/").content.decode()
    assert "Pak Owner" in html and "Orang Lain" not in html


def test_device_shows_activation_code_and_can_be_revoked(owner_client, outlet):
    r = owner_client.post("/device/baru/", {"name": "HP Gerobak 1", "outlet": outlet.pk})
    device = Device.objects.get(name="HP Gerobak 1")
    assert r.status_code == 302 and device.activation_code in owner_client.get(r.url).content.decode()
    owner_client.post(f"/device/{device.pk}/", {"revoke": "1"})
    device.refresh_from_db()
    assert device.revoked_at is not None
    assert "Dicabut" in owner_client.get("/device/").content.decode()
```

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_dashboard_staff_device.py`
Expected: FAIL (404 untuk `/staf/…` dan `/device/…`).

- [ ] **Step 3: Implementasi form staf**

Di `backend/dashboard/forms.py`, tambahkan import:
```python
from django.contrib.auth.password_validation import validate_password

from core.pins import make_pin
from core.tenancy import current_tenant_id
```
dan tambahkan di akhir file:
```python
class StaffForm(forms.ModelForm):
    pin = forms.CharField(label="PIN app kasir (6 digit)", required=False, min_length=6, max_length=6,
                          help_text="Wajib untuk staf baru. Kosongkan jika tidak diubah.")
    new_password = forms.CharField(label="Password dashboard", required=False, widget=forms.PasswordInput,
                                   help_text="Hanya untuk owner/manager. Kosongkan jika tidak diubah.")

    class Meta:
        model = User
        fields = ["display_name", "username", "role", "outlets", "can_discount", "is_active"]

    def clean_pin(self):
        pin = self.cleaned_data["pin"]
        if pin and not pin.isdigit():
            raise forms.ValidationError("PIN harus 6 digit angka.")
        if not pin and not self.instance.pin_hash:
            raise forms.ValidationError("PIN wajib untuk staf baru.")
        return pin

    def clean(self):
        cleaned = super().clean()
        password = cleaned.get("new_password")
        has_password = not self.instance._state.adding and self.instance.has_usable_password()
        if cleaned.get("role") in (User.Role.OWNER, User.Role.MANAGER) and not (password or has_password):
            self.add_error("new_password", "Owner/manager butuh password untuk login dashboard.")
        if password:
            try:
                validate_password(password)
            except forms.ValidationError as e:
                self.add_error("new_password", e)
        return cleaned

    def save(self, commit=True):
        user = super().save(commit=False)
        user.tenant_id = current_tenant_id()
        if self.cleaned_data["pin"]:
            user.pin_hash = make_pin(self.cleaned_data["pin"])
        if self.cleaned_data["new_password"]:
            user.set_password(self.cleaned_data["new_password"])
        elif self.instance._state.adding:
            user.set_unusable_password()
        if commit:
            user.save()
            self.save_m2m()
        return user
```

- [ ] **Step 4: Implementasi view device**

Di `backend/dashboard/views.py`, ganti blok import menjadi:
```python
from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.contrib.auth.views import LoginView
from django.shortcuts import redirect
from django.urls import reverse
from django.utils import timezone
from django.views.generic import CreateView, DetailView, ListView, TemplateView

from core.models import Device, User

from .forms import LoginForm
```
dan tambahkan di akhir file:
```python
class DeviceList(OwnerRequired, ListView):
    template_name = "dashboard/device_list.html"

    def get_queryset(self):
        return Device.objects.select_related("outlet").order_by("number")


class DeviceCreate(OwnerRequired, CreateView):
    model = Device
    fields = ["name", "outlet"]
    template_name = "dashboard/form.html"
    extra_context = {"title": "Device baru"}

    def form_valid(self, form):
        response = super().form_valid(form)
        self.object.issue_activation_code()
        return response

    def get_success_url(self):
        return reverse("device_detail", args=[self.object.pk])


class DeviceDetail(OwnerRequired, DetailView):
    model = Device
    template_name = "dashboard/device_detail.html"

    def post(self, request, pk):
        device = self.get_object()
        if "revoke" in request.POST:
            device.revoked_at = timezone.now()
            device.save(update_fields=["revoked_at"])
        elif device.activated_at is None and device.revoked_at is None:
            device.issue_activation_code()
        return redirect("device_detail", pk=pk)
```

`backend/dashboard/templates/dashboard/device_list.html`:
```html
{% extends "dashboard/base.html" %}
{% block content %}
<h2>Device</h2>
<p><a href="{% url 'device_create' %}" role="button">Tambah device</a></p>
<table>
  <thead><tr><th>No</th><th>Nama</th><th>Outlet</th><th>Status</th><th>Sync terakhir</th><th>Data menunggu</th><th>Versi app</th></tr></thead>
  <tbody>
  {% for d in object_list %}
    <tr>
      <td><a href="{% url 'device_detail' d.pk %}">{{ d.number }}</a></td>
      <td>{{ d.name }}</td>
      <td>{{ d.outlet.code }}</td>
      <td>{% if d.revoked_at %}Dicabut{% elif d.activated_at %}Aktif{% else %}Belum aktif{% endif %}</td>
      <td>{{ d.last_sync_at|date:"d M H:i"|default:"-" }}</td>
      <td>{{ d.pending_count }}</td>
      <td>{{ d.app_version|default:"-" }}</td>
    </tr>
  {% empty %}
    <tr><td colspan="7">Belum ada device.</td></tr>
  {% endfor %}
  </tbody>
</table>
{% endblock %}
```

`backend/dashboard/templates/dashboard/device_detail.html`:
```html
{% extends "dashboard/base.html" %}
{% block content %}
<h2>Device #{{ object.number }} — {{ object.name }}</h2>
<p>Outlet: {{ object.outlet }}</p>
{% if object.revoked_at %}
  <p><mark>Dicabut {{ object.revoked_at|date:"d M Y H:i" }}</mark></p>
{% elif object.activated_at %}
  <p>Aktif sejak {{ object.activated_at|date:"d M Y H:i" }} · sync terakhir {{ object.last_sync_at|date:"d M Y H:i"|default:"-" }} · data menunggu {{ object.pending_count }}</p>
{% else %}
  <p>Kode aktivasi: <strong style="font-size: 2rem; letter-spacing: .2em">{{ object.activation_code }}</strong></p>
  <p>Berlaku sampai {{ object.activation_expires_at|date:"H:i" }}. Masukkan kode ini di app kasir.</p>
  <form method="post">{% csrf_token %}<button name="new_code" value="1">Buat kode baru</button></form>
{% endif %}
{% if not object.revoked_at %}
<form method="post" onsubmit="return confirm('Cabut device ini? Data yang belum sync di HP itu tidak akan diterima lagi.')">
  {% csrf_token %}<button name="revoke" value="1" class="secondary">Cabut device</button>
</form>
{% endif %}
{% endblock %}
```

- [ ] **Step 5: Daftarkan URL & menu**

Di `backend/dashboard/urls.py`:
- ubah `from core.models import Outlet` menjadi `from core.models import Outlet, User`;
- tambahkan `from .forms import StaffForm` di bawah `from .crud import crud`;
- tambahkan baris berikut di akhir list `urlpatterns`:
```python
    *crud(User, None, ["display_name", "username", "role", "is_active"], "staf", "Staf",
          manager="in_tenant", form_cls=StaffForm),
    path("device/", views.DeviceList.as_view(), name="device_list"),
    path("device/baru/", views.DeviceCreate.as_view(), name="device_create"),
    path("device/<uuid:pk>/", views.DeviceDetail.as_view(), name="device_detail"),
```

Di `backend/dashboard/templates/dashboard/base.html`, tambahkan tepat di bawah baris `<li><a href="{% url 'opsi_list' %}">Opsi</a></li>`:
```html
      <li><a href="{% url 'staf_list' %}">Staf</a></li>
      <li><a href="{% url 'device_list' %}">Device</a></li>
```

- [ ] **Step 6: Jalankan test**

Run: `.\.venv\Scripts\python.exe -m pytest`
Expected: `48 passed`.

- [ ] **Step 7: Commit**

```powershell
git add dashboard tests/test_dashboard_staff_device.py
git commit -m "feat: dashboard staf (PIN/password) dan device (kode aktivasi, cabut)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Perintah setup usaha, uji isolasi tenant, dan smoke test manual

**Files:**
- Create: `backend/core/management/__init__.py` (kosong), `backend/core/management/commands/__init__.py` (kosong), `backend/core/management/commands/setup_tenant.py`
- Test: `backend/tests/test_isolation.py`

**Interfaces:**
- Consumes: semua task sebelumnya.
- Produces: `manage.py setup_tenant --name … --username … --pin … [--password …]`. Uji isolasi ini menjadi kriteria penerimaan PRD A-02.

- [ ] **Step 1: Tulis test yang gagal**

`backend/tests/test_isolation.py`:
```python
import json

import pytest
from django.core.management import call_command
from django.urls import reverse
from django.utils import timezone

from catalog.models import Category, ModifierGroup, ModifierOption, Product
from core.models import Device, Outlet, Tenant, User, token_hash
from core.pins import check_pin
from core.tenancy import tenant_context

LIST_PAGES = ["outlet_list", "kategori_list", "produk_list", "modifier_list", "opsi_list", "staf_list", "device_list"]


@pytest.fixture
def two_tenants(db):
    """Data lengkap untuk 2 usaha. Semua nama data usaha B mengandung kata RAHASIA."""
    made = {}
    for key, label in (("a", "Alpha"), ("b", "RAHASIA")):
        tenant = Tenant.objects.create(name=f"{label} Kopi")
        with tenant_context(tenant.id):
            outlet = Outlet.objects.create(code=f"{key.upper()}01", name=f"{label} Outlet")
            category = Category.objects.create(name=f"{label} Kategori")
            group = ModifierGroup.objects.create(name=f"{label} Grup")
            option = ModifierOption.objects.create(group=group, name=f"{label} Opsi")
            product = Product.objects.create(category=category, name=f"{label} Produk", price=1000)
            staff = User.objects.create_user(username=f"{key}-kasir", tenant=tenant, display_name=f"{label} Kasir")
            staff.outlets.add(outlet)
            device = Device.objects.create(outlet=outlet, name=f"{label} HP")
        made[key] = {"device": device, "objects": {"outlet": outlet, "kategori": category, "modifier": group,
                                                   "opsi": option, "produk": product, "staf": staff}}
    made["owner_a"] = User.objects.create_user(username="owner-a", password="rahasia-123", tenant=made["a"]["device"].tenant,
                                               role=User.Role.OWNER, display_name="Owner Alpha")
    return made


def test_dashboard_never_shows_other_tenant(client, two_tenants):
    client.force_login(two_tenants["owner_a"])
    for name in LIST_PAGES:
        r = client.get(reverse(name))
        assert r.status_code == 200 and "RAHASIA" not in r.content.decode(), name
    for prefix, obj in two_tenants["b"]["objects"].items():
        assert client.get(reverse(f"{prefix}_update", args=[obj.pk])).status_code == 404, prefix
    assert client.get(reverse("device_detail", args=[two_tenants["b"]["device"].pk])).status_code == 404


def test_api_snapshot_never_contains_other_tenant(client, two_tenants):
    device = two_tenants["a"]["device"]
    device.token_hash, device.activated_at = token_hash("token-a"), timezone.now()
    device.save()
    body = client.get("/api/v1/sync/master?version=0", HTTP_AUTHORIZATION="Bearer token-a").json()
    assert "Alpha Produk" in json.dumps(body) and "RAHASIA" not in json.dumps(body)


def test_setup_tenant_creates_business_and_owner(db):
    call_command("setup_tenant", name="Kopi Contoh", username="pemilik", pin="123456", password="Kopi-Sore-2026")
    owner = User.objects.get(username="pemilik")
    assert owner.tenant.name == "Kopi Contoh" and owner.role == User.Role.OWNER
    assert owner.check_password("Kopi-Sore-2026") and check_pin("123456", owner.pin_hash)
```

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_isolation.py`
Expected: dua test isolasi PASS (scoping sudah ada sejak Task 2). `test_setup_tenant_creates_business_and_owner` FAIL dengan `CommandError: Unknown command: 'setup_tenant'`.

- [ ] **Step 3: Implementasi perintah**

`backend/core/management/commands/setup_tenant.py`:
```python
import getpass

from django.contrib.auth.password_validation import validate_password
from django.core.management.base import BaseCommand
from django.db import transaction

from core.models import Tenant, User
from core.pins import make_pin


class Command(BaseCommand):
    help = "Buat usaha (tenant) beserta akun owner pertama."

    def add_arguments(self, parser):
        parser.add_argument("--name", required=True, help="Nama usaha")
        parser.add_argument("--username", required=True, help="Username owner untuk login dashboard")
        parser.add_argument("--pin", required=True, help="PIN 6 digit owner untuk app kasir")
        parser.add_argument("--password", help="Kosongkan agar diminta secara interaktif")

    def handle(self, *args, name, username, pin, password, **options):
        password = password or getpass.getpass("Password owner: ")
        validate_password(password)
        with transaction.atomic():
            tenant = Tenant.objects.create(name=name)
            User.objects.create_user(username=username, password=password, tenant=tenant,
                                     role=User.Role.OWNER, display_name=username, pin_hash=make_pin(pin))
        self.stdout.write(self.style.SUCCESS(f"Usaha '{name}' dan owner '{username}' sudah dibuat."))
```

Lupa password owner nanti cukup diatasi dengan `.\.venv\Scripts\python.exe manage.py changepassword <username>` (bawaan Django; PRD A-04).

- [ ] **Step 4: Jalankan seluruh test**

Run: `.\.venv\Scripts\python.exe -m pytest`
Expected: `51 passed`.

- [ ] **Step 5: Smoke test manual di database dev**

```powershell
.\.venv\Scripts\python.exe manage.py migrate
.\.venv\Scripts\python.exe manage.py setup_tenant --name "Kopi Contoh" --username owner --pin 123456
.\.venv\Scripts\python.exe manage.py runserver
```
Di browser buka `http://127.0.0.1:8000/login/` dan masuk sebagai `owner`. Buat 1 outlet, 1 kategori, 1 produk, lalu 1 device. Catat kode aktivasi yang tampil. Di jendela PowerShell kedua (folder `backend`), ganti `KODE_DARI_DASHBOARD` dengan kode itu:
```powershell
$act = Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/api/v1/device/activate -ContentType "application/json" -Body (@{ code = "KODE_DARI_DASHBOARD" } | ConvertTo-Json)
Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/v1/sync/master?version=0" -Headers @{ Authorization = "Bearer $($act.token)" } | ConvertTo-Json -Depth 6
```
Expected: JSON `changed: true` yang memuat outlet & produk yang baru dibuat. Halaman Device di dashboard menampilkan status "Aktif" dengan waktu sync terakhir.

- [ ] **Step 6: Commit**

```powershell
git add core/management tests/test_isolation.py
git commit -m "feat: perintah setup_tenant dan uji isolasi tenant menyeluruh" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Rencana Berikutnya

| Rencana | Isi |
|---|---|
| M2 — App Kasir | Flutter: aktivasi (+ QR kode aktivasi di dashboard), snapshot, transaksi offline, outbox & sync, shift/kas, nomor struk, printer (spike), gambar QRIS, pilihan metode bayar per usaha (M-06), test rumus total memakai `shared/totals_cases.json` |
| M3 — Loyalty | Member, StampRule & StampLedger, EARN/REDEEM/VOID, `member.registered` & `card.issued`, web kartu member (PWA), profil usaha (logo & warna) |
| M4 — Laporan & audit | Ringkasan dashboard, laporan + ekspor `.xlsx`, audit log, akses manager per outlet |
| M5 — Pilot & deploy | Docker Compose produksi, Caddy, backup/restore & `resend_since`, staging (setelah PRD Q2 & Q5 dijawab), pilot |
