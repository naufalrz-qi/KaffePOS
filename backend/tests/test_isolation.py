import json

import pytest
from django.core.management import call_command
from django.urls import reverse
from django.utils import timezone

from catalog.models import Category, ModifierGroup, ModifierOption, Product
from core.models import Device, Outlet, Tenant, User, token_hash
from core.pins import check_pin
from core.tenancy import tenant_context

LIST_PAGES = ["outlet_list", "kategori_list", "produk_list", "modifier_list", "opsi_list", "staf_list", "device_list"]


@pytest.fixture
def two_tenants(db):
    """Data lengkap untuk 2 usaha. Semua nama data usaha B mengandung kata RAHASIA."""
    made = {}
    for key, label in (("a", "Alpha"), ("b", "RAHASIA")):
        tenant = Tenant.objects.create(name=f"{label} Kopi")
        with tenant_context(tenant.id):
            outlet = Outlet.objects.create(code=f"{key.upper()}01", name=f"{label} Outlet")
            category = Category.objects.create(name=f"{label} Kategori")
            group = ModifierGroup.objects.create(name=f"{label} Grup")
            option = ModifierOption.objects.create(group=group, name=f"{label} Opsi")
            product = Product.objects.create(category=category, name=f"{label} Produk", price=1000)
            staff = User.objects.create_user(username=f"{key}-kasir", tenant=tenant, display_name=f"{label} Kasir")
            staff.outlets.add(outlet)
            device = Device.objects.create(outlet=outlet, name=f"{label} HP")
        made[key] = {"device": device, "objects": {"outlet": outlet, "kategori": category, "modifier": group,
                                                   "opsi": option, "produk": product, "staf": staff}}
    made["owner_a"] = User.objects.create_user(username="owner-a", password="rahasia-123", tenant=made["a"]["device"].tenant,
                                               role=User.Role.OWNER, display_name="Owner Alpha")
    return made


def test_dashboard_never_shows_other_tenant(client, two_tenants):
    client.force_login(two_tenants["owner_a"])
    for name in LIST_PAGES:
        r = client.get(reverse(name))
        assert r.status_code == 200 and "RAHASIA" not in r.content.decode(), name
    for prefix, obj in two_tenants["b"]["objects"].items():
        assert client.get(reverse(f"{prefix}_update", args=[obj.pk])).status_code == 404, prefix
    assert client.get(reverse("device_detail", args=[two_tenants["b"]["device"].pk])).status_code == 404


def test_api_snapshot_never_contains_other_tenant(client, two_tenants):
    device = two_tenants["a"]["device"]
    device.token_hash, device.activated_at = token_hash("token-a"), timezone.now()
    device.save()
    body = client.get("/api/v1/sync/master?version=0", HTTP_AUTHORIZATION="Bearer token-a").json()
    assert "Alpha Produk" in json.dumps(body) and "RAHASIA" not in json.dumps(body)


def test_setup_tenant_creates_business_and_owner(db):
    call_command("setup_tenant", name="Kopi Contoh", username="pemilik", pin="123456", password="Kopi-Sore-2026")
    owner = User.objects.get(username="pemilik")
    assert owner.tenant.name == "Kopi Contoh" and owner.role == User.Role.OWNER
    assert owner.check_password("Kopi-Sore-2026") and check_pin("123456", owner.pin_hash)
