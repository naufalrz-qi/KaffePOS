# backend/tests/test_reports_queries.py
from datetime import date, datetime, timedelta, timezone as tz

import pytest

from core.models import Device, Outlet
from reports import queries as q
from tests.factories import make_sale, make_shift, make_staff

DAY = date(2026, 11, 19)


@pytest.fixture
def data(tctx, outlet):
    kemang = Outlet.objects.create(code="KMG", name="Kemang", timezone="Asia/Makassar")
    andi, budi = make_staff(tctx, outlet, "Andi"), make_staff(tctx, kemang, "Budi")
    s1, s2 = make_shift(outlet, andi), make_shift(kemang, budi)
    make_sale(s1, 30000, "CASH", hour=8, items=(("Es Kopi Susu", "Kopi", 2),), modifier=("Ukuran", "Large", 5000))
    make_sale(s1, 15000, "QRIS", hour=9, items=(("Americano", "Kopi", 1),), discount=3000)
    make_sale(s2, 12000, "TRANSFER", hour=9, items=(("Teh Lemon", "Non-kopi", 1),))
    make_sale(s2, 99000, "CASH", hour=10, voided=True)
    return {"outlets": [outlet.pk, kemang.pk], "andi": andi}


def test_summary_excludes_voids(data):
    s = q.summary(q.sales_between(data["outlets"], DAY, DAY))
    assert s == {"omzet": 57000, "transaksi": 3, "item": 4, "rata_rata": 19000, "diskon": 3000,
                 "void_jumlah": 1, "void_nilai": 99000}


@pytest.mark.parametrize("fn", ["by_day", "by_outlet", "by_method", "by_staff", "by_hour"])
def test_breakdowns_add_up_to_omzet(data, fn):
    sales = q.sales_between(data["outlets"], DAY, DAY)
    assert sum(r["omzet"] for r in getattr(q, fn)(sales)) == 57000


def test_products_modifiers_and_hours(data):
    sales = q.sales_between(data["outlets"], DAY, DAY)
    assert q.by_product(sales)[0] == {"label": "Es Kopi Susu", "qty": 2, "omzet": 30000}
    assert q.by_modifier(sales) == [{"label": "Ukuran: Large", "qty": 2, "omzet": 10000}]
    hours = {r["label"]: r for r in q.by_hour(sales)}
    assert hours[8]["persen"] == 100 and hours[9]["omzet"] == 27000 and hours[9]["persen"] == 90
    assert 10 not in hours  # jam 10 hanya berisi penjualan void


def test_staff_filter_and_empty_period(data):
    assert q.summary(q.sales_between(data["outlets"], DAY, DAY, staff=data["andi"]))["omzet"] == 45000
    empty = q.summary(q.sales_between(data["outlets"], DAY + timedelta(1), DAY + timedelta(1)))
    assert empty["omzet"] == 0 and empty["rata_rata"] == 0


def test_today_follows_each_outlet_timezone(tctx, outlet, monkeypatch):
    # 2026-11-19 16:30 UTC = 23:30 WIB (masih 19/11) = 00:30 WITA (sudah 20/11)
    monkeypatch.setattr(q, "now", lambda: datetime(2026, 11, 19, 16, 30, tzinfo=tz.utc))
    wita = Outlet.objects.create(code="MKS", name="Makassar", timezone="Asia/Makassar")
    andi, budi = make_staff(tctx, outlet), make_staff(tctx, wita, "Budi")
    make_sale(make_shift(outlet, andi, day=date(2026, 11, 19)), 10000)
    make_sale(make_shift(wita, budi, day=date(2026, 11, 20)), 20000)
    make_sale(make_shift(wita, budi, day=date(2026, 11, 19)), 40000)
    assert q.summary(q.sales_today(Outlet.objects.all()))["omzet"] == 30000


def test_shift_rows_and_stale_warning(tctx, outlet, monkeypatch):
    monkeypatch.setattr(q, "now", lambda: datetime(2026, 11, 21, 3, tzinfo=tz.utc))
    andi = make_staff(tctx, outlet)
    make_shift(outlet, andi, counted=80000, expected=85000)
    stale = make_shift(outlet, andi, closed=False)
    rows = q.shifts_between([outlet.pk], DAY, DAY)
    assert {r["selisih"] for r in rows} == {-5000, None}
    assert q.stale_shifts([outlet.pk]) == [stale]


def test_device_status_flags_late_sync(tctx, outlet, monkeypatch):
    now = datetime(2026, 11, 21, 3, tzinfo=tz.utc)
    monkeypatch.setattr(q, "now", lambda: now)
    Device.objects.create(outlet=outlet, name="Baru", last_sync_at=now - timedelta(hours=1), activated_at=now)
    Device.objects.create(outlet=outlet, name="Lama", last_sync_at=now - timedelta(hours=30), activated_at=now,
                          pending_count=3)
    rows = {r["nama"]: r for r in q.device_status([outlet.pk])}
    assert rows["Baru"]["telat"] is False and rows["Lama"]["telat"] is True and rows["Lama"]["menunggu"] == 3


def test_voids_and_discounts_lists(data):
    sales = q.sales_between(data["outlets"], DAY, DAY)
    assert [r["nilai"] for r in q.voids(sales)] == [99000]
    assert [r["nilai"] for r in q.discounts(sales)] == [3000]
