"""Proses event outbox dari HP (desain §5).

Setiap event idempotent lewat kunci entitasnya. Penjualan tidak pernah ditolak karena aturan bisnis:
`Reject` hanya untuk data rusak/akses salah, `Retry` untuk ketergantungan yang belum diterima.
"""
from datetime import datetime, timedelta
from typing import Literal
from uuid import UUID
from zoneinfo import ZoneInfo

from django.db import IntegrityError, transaction
from django.db.models import Sum
from django.utils import timezone
from pydantic import AwareDatetime, BaseModel, Field, ValidationError

from core.audit import record, rupiah
from core.models import AuditLog, User
from sales.models import CashMovement, Payment, Sale, SaleItem, SaleItemModifier, Shift
from sales.totals import compute_totals


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


def approver_for(device, user_id):
    """Penyetuju bersifat opsional: tidak dikenal -> None (tidak menolak transaksi)."""
    if not user_id:
        return None
    return User.objects.filter(pk=user_id, tenant_id=device.tenant_id).first()


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
    discount_approved_by_id: UUID | None = None
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
    staff = staff_for(device, d.staff_id)
    approver = approver_for(device, d.discount_approved_by_id)
    if d.discount_approved_by_id and approver is None:
        flags.append("unknown_approver")  # metadata sekunder: penjualan tetap diterima
    sale = Sale.objects.create(
        id=d.sale_id, outlet_id=device.outlet_id, device=device, shift=shift,
        staff=staff, discount_approved_by=approver, receipt_no=d.receipt_no, created_at=d.created_at,
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
    if sale.discount_total > 0:
        approved = f", disetujui {approver.display_name}" if approver else ""
        record(AuditLog.Action.DISCOUNT, sale, actor=staff, device=device,
               detail=f"{sale.receipt_no}: diskon {rupiah(sale.discount_total)} ({sale.discount_reason or '-'}){approved}")
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
    sale.void_approved_by = approver_for(device, d.approved_by_id)
    if d.approved_by_id and sale.void_approved_by is None:
        sale.flags = ",".join(filter(None, [sale.flags, "unknown_approver"]))
    sale.save(update_fields=["status", "voided_at", "void_reason", "voided_by", "void_approved_by", "flags"])
    approved = f", disetujui {sale.void_approved_by.display_name}" if sale.void_approved_by else ""
    record(AuditLog.Action.VOID, sale, actor=sale.voided_by, device=device,
           detail=f"{sale.receipt_no}: {rupiah(sale.total)} ({sale.void_reason}){approved}")
    return "ok"


HANDLERS = {
    "shift.opened": shift_opened,
    "cash.moved": cash_moved,
    "sale.completed": sale_completed,
    "sale.voided": sale_voided,
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
