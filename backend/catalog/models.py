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
