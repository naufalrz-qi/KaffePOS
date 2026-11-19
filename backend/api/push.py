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
