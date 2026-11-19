from catalog.models import Category, Product
from core.models import Tenant, User


def version(tenant):
    return Tenant.objects.get(pk=tenant.pk).master_version


def test_save_m2m_and_delete_bump_version(tctx, outlet):
    v0 = version(tctx)
    kopi = Category.objects.create(name="Kopi")
    product = Product.objects.create(category=kopi, name="Es Kopi Susu", price=18000)
    v1 = version(tctx)
    assert v1 > v0
    product.available_outlets.add(outlet)
    v2 = version(tctx)
    assert v2 > v1
    product.delete()
    assert version(tctx) > v2


def test_login_timestamp_does_not_bump_version(tctx):
    kasir = User.objects.create_user(username="kasir1", tenant=tctx, display_name="Kasir 1")
    v = version(tctx)
    kasir.save(update_fields=["last_login"])
    assert version(tctx) == v


def test_saving_stale_tenant_keeps_counters(tctx):
    stale = Tenant.objects.get(pk=tctx.pk)
    Category.objects.create(name="Kopi")  # versi di database naik, objek `stale` tidak tahu
    fresh = version(tctx)
    stale.name = "Kopi Baru"
    stale.save()
    assert version(tctx) == fresh + 1  # tidak mundur ke nilai basi, lalu naik karena profil berubah
