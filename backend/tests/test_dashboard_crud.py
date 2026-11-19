from catalog.models import Category, ModifierGroup, Product
from core.models import Outlet, Tenant, User
from core.tenancy import tenant_context


def test_owner_creates_outlet_and_duplicate_code_is_rejected(owner_client):
    data = {"code": "GRB02", "name": "Gerobak Kuningan", "type": "MOBILE", "timezone": "Asia/Jakarta",
            "tax_rate_bp": 1000, "rounding_unit": 0}
    assert owner_client.post("/outlet/baru/", data).status_code == 302
    r = owner_client.post("/outlet/baru/", data)
    assert r.status_code == 200 and "Kode sudah dipakai" in r.content.decode()
    assert Outlet.objects.filter(code="GRB02").count() == 1


def test_product_form_only_offers_own_categories(owner_client, tctx):
    Category.objects.create(name="Kopi")
    other = Tenant.objects.create(name="Usaha Lain")
    with tenant_context(other.id):
        Category.objects.create(name="Kategori Rahasia")
    html = owner_client.get("/produk/baru/").content.decode()
    assert "Kopi" in html and "Kategori Rahasia" not in html


def test_owner_creates_product_with_modifier_group(owner_client, tctx):
    kopi = Category.objects.create(name="Kopi")
    size = ModifierGroup.objects.create(name="Ukuran", required=True)
    r = owner_client.post("/produk/baru/", {"category": kopi.pk, "name": "Es Kopi Susu", "price": 18000,
                                            "earns_stamp": "on", "modifier_groups": [size.pk],
                                            "sort": 1, "is_active": "on"})
    assert r.status_code == 302
    assert list(Product.objects.get(name="Es Kopi Susu").modifier_groups.all()) == [size]
    assert "Es Kopi Susu" in owner_client.get("/produk/").content.decode()


def test_manager_cannot_open_master_data_pages(client, tctx):
    manager = User.objects.create_user(username="mgr", password="rahasia-123", tenant=tctx,
                                       role=User.Role.MANAGER, display_name="Mgr")
    client.force_login(manager)
    assert client.get("/produk/").status_code == 403
