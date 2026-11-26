from django import forms

from catalog.models import Category, Product
from core.audit import form_changes, record, rupiah
from core.models import AuditLog


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
