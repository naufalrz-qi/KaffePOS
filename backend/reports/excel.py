"""Ekspor laporan ke .xlsx (spec §7). Angka disimpan sebagai angka supaya bisa dijumlah di Excel."""
import io

from django.utils import timezone
from openpyxl import Workbook
from openpyxl.styles import Font

from . import queries as q

SHEETS = ["Ringkasan", "Harian", "Outlet", "Metode bayar", "Staf", "Per jam", "Produk", "Kategori",
          "Modifier", "Shift", "Void", "Diskon"]
RUPIAH = "#,##0"


def _sheet(wb, title, header, rows, money_cols=(), money_rows=()):
    ws = wb.create_sheet(title)
    ws.append(header)
    for cell in ws[1]:
        cell.font = Font(bold=True)
    for row in rows:
        ws.append(list(row))
        for cell in ws[ws.max_row]:  # cegah formula injection: teks berawalan = + - @ tetap teks
            if isinstance(cell.value, str) and cell.value[:1] in ("=", "+", "-", "@"):
                cell.data_type = "s"
    for col in money_cols:
        for (cell,) in ws.iter_rows(min_row=2, min_col=col, max_col=col):
            cell.number_format = RUPIAH
    for r in money_rows:
        ws.cell(row=r, column=2).number_format = RUPIAH
    for col in ws.columns:
        ws.column_dimensions[col[0].column_letter].width = min(60, max(12, max(len(str(c.value or "")) for c in col) + 2))


def _naive(dt):
    # Excel tidak menyimpan zona waktu: tulis dalam WIB, sama dengan tampilan halaman
    return timezone.localtime(dt).replace(tzinfo=None) if dt else None


def build_workbook(outlet_ids, dari, sampai, staff=None, judul=""):
    sales = q.sales_between(outlet_ids, dari, sampai, staff)
    s = q.summary(sales)
    wb = Workbook()
    wb.remove(wb.active)
    _sheet(wb, "Ringkasan", ["Keterangan", "Nilai"], [
        ("Laporan", judul), ("Periode", f"{dari:%d/%m/%Y} – {sampai:%d/%m/%Y}"), ("Omzet", s["omzet"]),
        ("Transaksi", s["transaksi"]), ("Item terjual", s["item"]), ("Rata-rata", s["rata_rata"]),
        ("Diskon", s["diskon"]), ("Void (jumlah)", s["void_jumlah"]), ("Void (nilai)", s["void_nilai"])],
           money_rows=(4, 7, 8, 10))
    for title, fn, first in (("Harian", q.by_day, "Tanggal"), ("Outlet", q.by_outlet, "Outlet"),
                             ("Metode bayar", q.by_method, "Metode"), ("Staf", q.by_staff, "Staf"),
                             ("Per jam", q.by_hour, "Jam")):
        _sheet(wb, title, [first, "Transaksi", "Omzet"],
               [(r["label"], r["transaksi"], r["omzet"]) for r in fn(sales)], money_cols=(3,))
    for title, fn, first in (("Produk", q.by_product, "Produk"), ("Kategori", q.by_category, "Kategori"),
                             ("Modifier", q.by_modifier, "Modifier")):
        _sheet(wb, title, [first, "Qty", "Nilai item"],
               [(r["label"], r["qty"], r["omzet"]) for r in fn(sales)], money_cols=(3,))
    _sheet(wb, "Shift", ["Outlet", "Staf", "Buka", "Tutup", "Modal", "Kas seharusnya", "Kas fisik", "Selisih"],
           [(r["outlet"], r["staf"], _naive(r["buka"]), _naive(r["tutup"]), r["modal"], r["seharusnya"],
             r["fisik"], r["selisih"]) for r in q.shifts_between(outlet_ids, dari, sampai, staff)],
           money_cols=(5, 6, 7, 8))
    for title, rows in (("Void", q.voids(sales)), ("Diskon", q.discounts(sales))):
        _sheet(wb, title, ["No struk", "Waktu", "Nilai", "Alasan", "Oleh", "Disetujui"],
               [(r["struk"], _naive(r["waktu"]), r["nilai"], r["alasan"], r["oleh"], r["disetujui"]) for r in rows],
               money_cols=(3,))
    out = io.BytesIO()
    wb.save(out)
    return out.getvalue()
