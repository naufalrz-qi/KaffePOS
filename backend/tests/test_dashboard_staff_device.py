from core.models import Device, Outlet, Tenant, User
from core.pins import check_pin
from core.tenancy import tenant_context
from dashboard.forms import StaffForm


def test_staff_form_outlet_choices_follow_active_tenant(db):
    """Regresi: pilihan outlet tidak boleh terkunci ke tenant yang aktif saat modul form di-import."""
    a, b = Tenant.objects.create(name="A"), Tenant.objects.create(name="B")
    with tenant_context(a.id):
        Outlet.objects.create(code="A1", name="Outlet A")
    with tenant_context(b.id):
        Outlet.objects.create(code="B1", name="Outlet B")
        assert [o.code for o in StaffForm().fields["outlets"].queryset] == ["B1"]
    with tenant_context(a.id):
        assert [o.code for o in StaffForm().fields["outlets"].queryset] == ["A1"]


def test_create_cashier_with_pin(owner_client, outlet):
    r = owner_client.post("/staf/baru/", {"display_name": "Andi", "username": "andi", "role": "CASHIER",
                                          "outlets": [outlet.pk], "is_active": "on", "pin": "123456"})
    assert r.status_code == 302
    andi = User.objects.get(username="andi")
    assert check_pin("123456", andi.pin_hash) and not andi.has_usable_password()
    assert andi.tenant_id == outlet.tenant_id and list(andi.outlets.all()) == [outlet]


def test_new_manager_requires_password(owner_client):
    r = owner_client.post("/staf/baru/", {"display_name": "Mgr", "username": "mgr", "role": "MANAGER",
                                          "is_active": "on", "pin": "222222"})
    assert r.status_code == 200 and "butuh password" in r.content.decode()


def test_staff_list_hides_other_tenants(owner_client):
    other = Tenant.objects.create(name="Usaha Lain")
    User.objects.create_user(username="orang-lain", tenant=other, display_name="Orang Lain")
    html = owner_client.get("/staf/").content.decode()
    assert "Pak Owner" in html and "Orang Lain" not in html


def test_device_shows_activation_code_and_can_be_revoked(owner_client, outlet):
    r = owner_client.post("/device/baru/", {"name": "HP Gerobak 1", "outlet": outlet.pk})
    device = Device.objects.get(name="HP Gerobak 1")
    assert r.status_code == 302 and device.activation_code in owner_client.get(r.url).content.decode()
    owner_client.post(f"/device/{device.pk}/", {"revoke": "1"})
    device.refresh_from_db()
    assert device.revoked_at is not None
    assert "Dicabut" in owner_client.get("/device/").content.decode()
