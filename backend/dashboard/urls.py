from django.contrib.auth.views import LogoutView
from django.urls import path

from catalog.models import Category, ModifierGroup, ModifierOption, Product
from core.models import Outlet

from . import views
from .crud import crud

urlpatterns = [
    path("login/", views.Login.as_view(), name="login"),
    path("logout/", LogoutView.as_view(), name="logout"),
    path("", views.Home.as_view(), name="home"),
    *crud(Outlet, ["code", "name", "type", "timezone", "tax_enabled", "tax_rate_bp", "tax_inclusive",
                   "rounding_unit", "void_needs_manager", "receipt_header", "receipt_footer", "is_active"],
          ["code", "name", "type", "is_active"], "outlet", "Outlet & Gerobak"),
    *crud(Category, ["name", "sort", "is_active"], ["name", "sort", "is_active"], "kategori", "Kategori"),
    *crud(ModifierGroup, ["name", "required", "multi", "sort"], ["name", "required", "multi"],
          "modifier", "Grup Modifier"),
    *crud(ModifierOption, ["group", "name", "price_delta", "sort", "is_active"],
          ["group", "name", "price_delta", "is_active"], "opsi", "Opsi Modifier"),
    *crud(Product, ["category", "name", "price", "earns_stamp", "modifier_groups", "available_outlets",
                    "sort", "is_active"], ["name", "category", "price", "is_active"], "produk", "Produk"),
]
