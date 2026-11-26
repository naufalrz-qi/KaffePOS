"""Semua angka laporan & beranda (spec §4). Satu sumber untuk halaman dan Excel, jadi angkanya selalu sama."""
from datetime import timedelta
from zoneinfo import ZoneInfo

from django.db.models import Count, F, Q, Sum
from django.utils import timezone

from core.models import Device
from sales.models import Payment, Sale, SaleItem, SaleItemModifier, Shift

STALE = timedelta(hours=24)


def now():
    return timezone.now()  # dipisah supaya bisa diganti di test


def _completed(sales):
    return sales.filter(status=Sale.Status.COMPLETED)


def sales_between(outlet_ids, dari, sampai, staff=None):
    sales = Sale.objects.filter(outlet_id__in=outlet_ids, business_date__range=(dari, sampai))
    return sales.filter(staff=staff) if staff else sales


def sales_today(outlets):
    """Hari ini dihitung per zona waktu outlet (WIB/WITA/WIT)."""
    cond, instant = Q(pk__in=[]), now()
    for outlet in outlets:
        cond |= Q(outlet_id=outlet.pk, business_date=instant.astimezone(ZoneInfo(outlet.timezone)).date())
    return Sale.objects.filter(cond)


def summary(sales):
    done = _completed(sales).aggregate(omzet=Sum("total"), transaksi=Count("id"), diskon=Sum("discount_total"))
    item = SaleItem.objects.filter(sale__in=_completed(sales)).aggregate(n=Sum("qty"))["n"] or 0
    void = sales.filter(status=Sale.Status.VOIDED).aggregate(n=Count("id"), v=Sum("total"))
    omzet, n = done["omzet"] or 0, done["transaksi"]
    return {"omzet": omzet, "transaksi": n, "item": item, "rata_rata": (omzet * 2 + n) // (2 * n) if n else 0,
            "diskon": done["diskon"] or 0, "void_jumlah": void["n"], "void_nilai": void["v"] or 0}


def _group(sales, fields, label):
    """fields: nama kolom, atau tuple (id, nama) agar entitas bernama sama tidak tergabung; label dari kolom terakhir."""
    fields = (fields,) if isinstance(fields, str) else fields
    rows = _completed(sales).values(*fields).annotate(omzet=Sum("total"), transaksi=Count("id")).order_by(*fields)
    return [{"label": label(r[fields[-1]]), "omzet": r["omzet"], "transaksi": r["transaksi"]} for r in rows]


def by_day(sales):
    return _group(sales, "business_date", lambda d: d)


def by_outlet(sales):
    return sorted(_group(sales, ("outlet_id", "outlet__name"), str), key=lambda r: -r["omzet"])


def by_staff(sales):
    return sorted(_group(sales, ("staff_id", "staff__display_name"), str), key=lambda r: -r["omzet"])


def by_method(sales):
    labels = dict(Payment.Method.choices)
    rows = (Payment.objects.filter(sale__in=_completed(sales)).values("method")
            .annotate(omzet=Sum("amount"), transaksi=Count("sale", distinct=True)).order_by("-omzet"))
    return [{"label": labels.get(r["method"], r["method"]), "omzet": r["omzet"], "transaksi": r["transaksi"]}
            for r in rows]


def by_hour(sales):
    rows = _group(sales, "local_hour", int)
    top = max((r["omzet"] for r in rows), default=0)
    for r in rows:
        r["persen"] = round(r["omzet"] * 100 / top) if top else 0
    return rows


def _items(sales, field):
    rows = (SaleItem.objects.filter(sale__in=_completed(sales)).values(field)
            .annotate(qty=Sum("qty"), omzet=Sum("line_total")).order_by("-qty", field))
    return [{"label": r[field] or "-", "qty": r["qty"], "omzet": r["omzet"]} for r in rows]


def by_product(sales):
    return _items(sales, "name")


def by_category(sales):
    return _items(sales, "category_name")


def by_modifier(sales):
    rows = (SaleItemModifier.objects.filter(sale_item__sale__in=_completed(sales))
            .values("group_name", "name")
            .annotate(qty=Sum("sale_item__qty"), omzet=Sum(F("price_delta") * F("sale_item__qty")))
            .order_by("-qty", "group_name", "name"))
    return [{"label": f"{r['group_name']}: {r['name']}", "qty": r["qty"], "omzet": r["omzet"]} for r in rows]


def shifts_between(outlet_ids, dari, sampai, staff=None):
    shifts = Shift.objects.filter(outlet_id__in=outlet_ids, business_date__range=(dari, sampai))
    if staff:
        shifts = shifts.filter(staff=staff)
    rows = []
    for s in shifts.select_related("outlet", "staff").order_by("-opened_at"):
        selisih = s.counted_cash - s.expected_cash if s.closed_at and s.counted_cash is not None \
            and s.expected_cash is not None else None
        rows.append({"outlet": s.outlet.name, "staf": s.staff.display_name, "buka": s.opened_at,
                     "tutup": s.closed_at, "modal": s.opening_cash, "seharusnya": s.expected_cash,
                     "fisik": s.counted_cash, "selisih": selisih,
                     "lama": s.closed_at is None and now() - s.opened_at > STALE})
    return rows


def stale_shifts(outlet_ids):
    return list(Shift.objects.filter(outlet_id__in=outlet_ids, closed_at__isnull=True,
                                     opened_at__lt=now() - STALE).select_related("outlet", "staff"))


def voids(sales):
    return [{"struk": s.receipt_no, "waktu": s.voided_at, "nilai": s.total, "alasan": s.void_reason,
             "oleh": s.voided_by.display_name if s.voided_by else "-",
             "disetujui": s.void_approved_by.display_name if s.void_approved_by else "-"}
            for s in sales.filter(status=Sale.Status.VOIDED)
            .select_related("voided_by", "void_approved_by").order_by("-voided_at")]


def discounts(sales):
    return [{"struk": s.receipt_no, "waktu": s.created_at, "nilai": s.discount_total, "alasan": s.discount_reason,
             "oleh": s.staff.display_name,
             "disetujui": s.discount_approved_by.display_name if s.discount_approved_by else "-"}
            for s in _completed(sales).filter(discount_total__gt=0)
            .select_related("staff", "discount_approved_by").order_by("-created_at")]


def device_status(outlet_ids):
    rows = []
    for d in (Device.objects.filter(outlet_id__in=outlet_ids, revoked_at__isnull=True, activated_at__isnull=False)
              .select_related("outlet").order_by("number")):
        rows.append({"nama": d.name, "outlet": d.outlet.name, "sync": d.last_sync_at, "menunggu": d.pending_count,
                     "versi": d.app_version or "-",
                     "telat": d.last_sync_at is None or now() - d.last_sync_at > STALE})
    return rows
