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
