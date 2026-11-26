import io

import pytest
from openpyxl import load_workbook

from core.models import AuditLog, Outlet, User
from tests.factories import make_sale, make_shift, make_staff

Q = "?dari=2026-11-19&sampai=2026-11-19"


@pytest.fixture
def toko(tctx, outlet):
    kemang = Outlet.objects.create(code="KMG", name="Kemang")
    make_sale(make_shift(outlet, make_staff(tctx, outlet, "Andi")), 30000)
    make_sale(make_shift(kemang, make_staff(tctx, kemang, "Budi")), 77000)
    return kemang


@pytest.fixture
def manager_client(client, tctx, outlet):
    m = User.objects.create_user(username="mgr", password="rahasia-123", tenant=tctx,
                                 role=User.Role.MANAGER, display_name="Mgr")
    m.outlets.add(outlet)
    client.force_login(m)
    return client


@pytest.mark.parametrize("path", ["/laporan/", "/laporan/produk/", "/laporan/shift/", "/laporan/void-diskon/"])
def test_owner_tabs_load_with_all_outlets_in_filter(owner_client, toko, path):
    r = owner_client.get(path + Q)
    assert r.status_code == 200 and "Kemang" in r.content.decode()  # pilihan outlet di filter


def test_owner_report_totals(owner_client, toko):
    html = owner_client.get("/laporan/" + Q).content.decode()
    assert "107.000" in html  # 30.000 + 77.000


def test_manager_only_sees_own_outlet(manager_client, toko):
    html = manager_client.get("/laporan/" + Q).content.decode()
    assert "30.000" in html and "77.000" not in html and "Kemang" not in html
    assert manager_client.get(f"/laporan/{Q}&outlet={toko.pk}").status_code == 404
    assert manager_client.get("/audit/").status_code == 403
    assert "Kelola" not in manager_client.get("/").content.decode()


def test_manager_without_outlet_gets_message(client, tctx, toko):
    m = User.objects.create_user(username="m2", password="rahasia-123", tenant=tctx,
                                 role=User.Role.MANAGER, display_name="M2")
    client.force_login(m)
    assert "Belum ada outlet yang ditugaskan" in client.get("/").content.decode()


def test_bad_filter_shows_error_without_numbers(owner_client, toko):
    html = owner_client.get("/laporan/?dari=2026-11-21&sampai=2026-11-01").content.decode()
    assert "harus sebelum" in html and "107.000" not in html


def test_excel_download(owner_client, toko):
    r = owner_client.get("/laporan/excel/" + Q)
    assert r["Content-Type"].startswith("application/vnd.openxmlformats")
    assert "laporan-2026-11-19_2026-11-19.xlsx" in r["Content-Disposition"]
    assert load_workbook(io.BytesIO(r.content))["Ringkasan"]["B4"].value == 107000


def test_home_shows_greeting_and_device_section(owner_client, toko):
    html = owner_client.get("/").content.decode()
    assert "Pak Owner" in html and "Device" in html


def test_audit_page_lists_entries_owner_only(owner_client, tctx, owner):
    AuditLog.objects.create(action="update", actor=owner, detail="Harga: 18.000 → 20.000")
    html = owner_client.get("/audit/").content.decode()
    assert "18.000 → 20.000" in html and "Ubah data" in html


def test_audit_filters_by_action_and_wib_date(owner_client, tctx, owner):
    from datetime import datetime, timezone as tz
    for detail, action, hour in (("log-kemarin", "update", 16), ("log-hari-ini", "create", 17)):
        AuditLog.objects.create(action=action, actor=owner, detail=detail,
                                at=datetime(2026, 11, 18, hour, 30, tzinfo=tz.utc))
    html = owner_client.get("/audit/?dari=2026-11-19&sampai=2026-11-19").content.decode()
    assert "log-hari-ini" in html and "log-kemarin" not in html  # 17:30 UTC = 00:30 WIB tgl 19
    html = owner_client.get("/audit/?aksi=update").content.decode()
    assert "log-kemarin" in html and "log-hari-ini" not in html
