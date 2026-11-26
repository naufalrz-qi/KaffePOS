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
    discount_approved_by = models.ForeignKey(USER, on_delete=models.PROTECT, null=True, related_name="+")
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
