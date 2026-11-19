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
