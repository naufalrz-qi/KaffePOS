import io
from datetime import date

from openpyxl import load_workbook

from reports import queries as q
from reports.excel import SHEETS, build_workbook
from tests.factories import make_sale, make_shift, make_staff

DAY = date(2026, 11, 19)


def test_workbook_has_all_sheets_and_matching_totals(tctx, outlet):
    shift = make_shift(outlet, make_staff(tctx, outlet))
    make_sale(shift, 30000, "CASH")
    make_sale(shift, 12000, "QRIS")
    wb = load_workbook(io.BytesIO(build_workbook([outlet.pk], DAY, DAY, judul="Uji")))
    assert wb.sheetnames == SHEETS
    harian = wb["Harian"]
    assert [c.value for c in harian[1]] == ["Tanggal", "Transaksi", "Omzet"]
    assert sum(r[2] for r in harian.iter_rows(min_row=2, values_only=True)) == \
        q.summary(q.sales_between([outlet.pk], DAY, DAY))["omzet"] == 42000
    assert isinstance(wb["Metode bayar"]["C2"].value, int)


def _wb(outlet):
    return load_workbook(io.BytesIO(build_workbook([outlet.pk], DAY, DAY, judul="=1+1")))


def test_formula_text_stays_text_and_ringkasan_formatted(tctx, outlet):
    shift = make_shift(outlet, make_staff(tctx, outlet))
    sale = make_sale(shift, 5000, voided=True)
    sale.void_reason = "=1+1"
    sale.save()
    wb = _wb(outlet)
    cell = wb["Void"]["D2"]
    assert cell.value == "=1+1" and cell.data_type == "s"
    assert wb["Ringkasan"]["B2"].data_type == "s"  # judul
    assert wb["Ringkasan"]["B4"].number_format == "#,##0"


def test_waktu_void_dan_diskon_dalam_wib(tctx, outlet):
    from datetime import datetime, timezone as tz
    shift = make_shift(outlet, make_staff(tctx, outlet))
    t = datetime(2026, 11, 19, 1, 0, tzinfo=tz.utc)
    v = make_sale(shift, 5000, voided=True)
    v.voided_at = t
    v.save()
    d = make_sale(shift, 9000, discount=1000)
    d.created_at = t
    d.save()
    wb = _wb(outlet)
    assert wb["Void"]["B2"].value == datetime(2026, 11, 19, 8, 0)
    assert wb["Diskon"]["B2"].value == datetime(2026, 11, 19, 8, 0)
