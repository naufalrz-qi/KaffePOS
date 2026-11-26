"""Pembuat data penjualan langsung lewat ORM untuk test laporan (lebih cepat dari push)."""
import uuid
from datetime import date, datetime, timezone as tz

from core.models import Device, User
from sales.models import Payment, Sale, SaleItem, SaleItemModifier, Shift

_seq = iter(range(1, 10**6))


def make_staff(tenant, outlet, name="Andi", role=User.Role.CASHIER):
    user = User.objects.create_user(username=f"{name.lower()}-{uuid.uuid4().hex[:6]}", tenant=tenant,
                                    display_name=name, role=role)
    user.outlets.add(outlet)
    return user


def make_shift(outlet, staff, day=date(2026, 11, 19), opening=100000, closed=True, counted=None, expected=None):
    device = Device.objects.filter(outlet=outlet).first() or Device.objects.create(outlet=outlet, name="HP")
    return Shift.objects.create(
        id=uuid.uuid4(), outlet=outlet, device=device, staff=staff, opened_at=datetime(2026, 11, 19, 1, tzinfo=tz.utc),
        opening_cash=opening, business_date=day,
        closed_at=datetime(2026, 11, 19, 12, tzinfo=tz.utc) if closed else None,
        counted_cash=counted, expected_cash=expected)


def make_sale(shift, total, method="CASH", hour=9, items=(("Es Kopi Susu", "Kopi", 1),), voided=False,
              discount=0, modifier=None):
    """items: (nama, kategori, qty). Seluruh total dibebankan ke item pertama."""
    sale = Sale.objects.create(
        id=uuid.uuid4(), outlet=shift.outlet, device=shift.device, shift=shift, staff=shift.staff,
        receipt_no=f"T-{next(_seq):05d}", created_at=shift.opened_at, business_date=shift.business_date,
        local_hour=hour, subtotal=total + discount, discount_total=discount, total=total,
        tax_enabled=False, tax_rate_bp=0, tax_inclusive=False, rounding_unit=0,
        status=Sale.Status.VOIDED if voided else Sale.Status.COMPLETED)
    for n, (name, category, qty) in enumerate(items):
        line = total if n == 0 else 0
        item = SaleItem.objects.create(id=uuid.uuid4(), sale=sale, product_id=uuid.uuid4(), name=name,
                                       category_name=category, qty=qty, unit_price=line // qty if qty else 0,
                                       line_total=line)
        if modifier and n == 0:
            SaleItemModifier.objects.create(sale_item=item, option_id=uuid.uuid4(), group_name=modifier[0],
                                            name=modifier[1], price_delta=modifier[2])
    Payment.objects.create(id=uuid.uuid4(), sale=sale, method=method, amount=total)
    return sale
