from django import forms

from catalog.models import Category, Product
from core.audit import form_changes, record, rupiah
from core.models import AuditLog, Device, User


def test_record_stores_object_and_actor(tctx, owner):
    kopi = Category.objects.create(name="Kopi")
    record(AuditLog.Action.CREATE, kopi, "dibuat", actor=owner)
    log = AuditLog.objects.get()
    assert (log.action, log.object_type, log.object_id, log.actor, log.detail) == (
        "create", "category", str(kopi.pk), owner, "dibuat")


def test_record_truncates_long_detail(tctx):
    record(AuditLog.Action.UPDATE, detail="x" * 900)
    assert len(AuditLog.objects.get().detail) == 500


class ProductForm(forms.ModelForm):
    pin = forms.CharField(required=False, label="PIN")

    class Meta:
        model = Product
        fields = ["name", "price", "is_active"]


def test_form_changes_lists_old_and_new_and_hides_secrets(tctx):
    kopi = Category.objects.create(name="Kopi")
    product = Product.objects.create(category=kopi, name="Es Kopi Susu", price=18000)
    form = ProductForm({"name": "Es Kopi Susu", "price": 20000, "pin": "123456"}, instance=product)
    assert form.is_valid()
    text = form_changes(form)
    assert "Harga: 18.000 → 20.000" in text
    assert "Aktif: Ya → Tidak" in text
    assert "PIN diubah" in text and "123456" not in text


def test_rupiah_formats_thousands():
    assert rupiah(1250000) == "1.250.000" and rupiah(-5000) == "-5.000" and rupiah(0) == "0"


def test_price_change_is_audited(owner_client, tctx, owner):
    kopi = Category.objects.create(name="Kopi")
    p = Product.objects.create(category=kopi, name="Es Kopi Susu", price=18000)
    owner_client.post(f"/produk/{p.pk}/", {"category": kopi.pk, "name": "Es Kopi Susu", "price": 20000,
                                           "sort": 0, "is_active": "on"})
    log = AuditLog.objects.get(action="update")
    assert log.actor == owner and "18.000 → 20.000" in log.detail and log.object_id == str(p.pk)


def test_fk_change_shows_name_not_pk(owner_client, tctx):
    kopi = Category.objects.create(name="Kopi")
    teh = Category.objects.create(name="Teh")
    p = Product.objects.create(category=kopi, name="Es Kopi Susu", price=18000)
    owner_client.post(f"/produk/{p.pk}/", {"category": teh.pk, "name": "Es Kopi Susu", "price": 18000,
                                           "sort": 0, "is_active": "on"})
    detail = AuditLog.objects.get(action="update").detail
    assert "Kopi → Teh" in detail and str(teh.pk) not in detail


def test_create_and_unchanged_save(owner_client, tctx):
    owner_client.post("/kategori/baru/", {"name": "Teh", "sort": 1, "is_active": "on"})
    cat = Category.objects.get(name="Teh")
    owner_client.post(f"/kategori/{cat.pk}/", {"name": "Teh", "sort": 1, "is_active": "on"})
    assert list(AuditLog.objects.values_list("action", flat=True)) == ["create"]


def test_staff_pin_change_hides_value(owner_client, tctx):
    owner_client.post("/staf/baru/", {"display_name": "Andi", "username": "andi", "role": "CASHIER",
                                      "pin": "111111", "is_active": "on"})
    andi = User.in_tenant.get(username="andi")
    owner_client.post(f"/staf/{andi.pk}/", {"display_name": "Andi", "username": "andi", "role": "CASHIER",
                                            "pin": "222222", "is_active": "on"})
    detail = AuditLog.objects.get(action="update").detail
    assert "diubah" in detail and "222222" not in detail


def test_device_lifecycle_is_audited(owner_client, outlet):
    owner_client.post("/device/baru/", {"name": "HP 2", "outlet": outlet.pk})
    device = Device.objects.get(name="HP 2")
    owner_client.post(f"/device/{device.pk}/", {"code": "1"})
    owner_client.post(f"/device/{device.pk}/", {"revoke": "1"})
    assert list(AuditLog.objects.order_by("at").values_list("action", flat=True)) == [
        "device_create", "device_code", "device_revoke"]
