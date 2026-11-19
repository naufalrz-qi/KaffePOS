from django.contrib.auth.views import LogoutView
from django.urls import path

from catalog.models import Category, ModifierGroup, ModifierOption, Product
from core.models import Outlet, User

from . import views
from .crud import crud
from .forms import OutletForm, StaffForm

urlpatterns = [
    path("login/", views.Login.as_view(), name="login"),
    path("logout/", LogoutView.as_view(), name="logout"),
    path("", views.Home.as_view(), name="home"),
    path("usaha/", views.BusinessUpdate.as_view(), name="usaha"),
    *crud(Outlet, None, ["code", "name", "type", "is_active"], "outlet", "Outlet & Gerobak", form_cls=OutletForm),
    *crud(Category, ["name", "sort", "is_active"], ["name", "sort", "is_active"], "kategori", "Kategori"),
    *crud(ModifierGroup, ["name", "required", "multi", "sort"], ["name", "required", "multi"],
          "modifier", "Grup Modifier"),
    *crud(ModifierOption, ["group", "name", "price_delta", "sort", "is_active"],
          ["group", "name", "price_delta", "is_active"], "opsi", "Opsi Modifier"),
    *crud(Product, ["category", "name", "price", "earns_stamp", "modifier_groups", "available_outlets",
                    "sort", "is_active"], ["name", "category", "price", "is_active"], "produk", "Produk"),
    *crud(User, None, ["display_name", "username", "role", "is_active"], "staf", "Staf",
          manager="in_tenant", form_cls=StaffForm),
    path("device/", views.DeviceList.as_view(), name="device_list"),
    path("device/baru/", views.DeviceCreate.as_view(), name="device_create"),
    path("device/<uuid:pk>/", views.DeviceDetail.as_view(), name="device_detail"),
]
