from django.urls import path

from . import views

urlpatterns = [
    path("", views.Beranda.as_view(), name="home"),
    path("laporan/", views.Laporan.as_view(tab="laporan"), name="laporan"),
    path("laporan/produk/", views.Laporan.as_view(tab="laporan_produk"), name="laporan_produk"),
    path("laporan/shift/", views.Laporan.as_view(tab="laporan_shift"), name="laporan_shift"),
    path("laporan/void-diskon/", views.Laporan.as_view(tab="laporan_void"), name="laporan_void"),
    path("laporan/excel/", views.Excel.as_view(), name="laporan_excel"),
    path("audit/", views.Audit.as_view(), name="audit"),
]
