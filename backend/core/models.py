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
