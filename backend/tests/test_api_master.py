import pytest
from django.utils import timezone

from catalog.models import Category, ModifierGroup, ModifierOption, Product
from core.models import Outlet, Tenant, User
from core.pins import check_pin, make_pin


def test_pin_hash_format_and_check():
    encoded = make_pin("123456")
    assert encoded.startswith("pbkdf2_sha256$20000$")
    assert check_pin("123456", encoded) and not check_pin("654321", encoded)


def test_pin_must_be_six_digits():
    with pytest.raises(ValueError):
        make_pin("12a456")


def test_unknown_or_missing_token_rejected(client, db):
    assert client.get("/api/v1/sync/master", HTTP_AUTHORIZATION="Bearer salah").json()["error"] == "invalid_token"
    r = client.get("/api/v1/sync/master")
    assert r.status_code == 401 and r.json()["error"] == "invalid_token"


def test_revoked_device_rejected(client, device, auth):
    device.revoked_at = timezone.now()
    device.save()
    r = client.get("/api/v1/sync/master", **auth)
    assert r.status_code == 401 and r.json()["error"] == "device_revoked"


def test_snapshot_only_contains_this_outlet(client, tctx, outlet, device, auth):
    other = Outlet.objects.create(code="OUT02", name="Outlet Lain", type=Outlet.Type.OUTLET)
    kopi = Category.objects.create(name="Kopi")
    size = ModifierGroup.objects.create(name="Ukuran", required=True)
    ModifierOption.objects.create(group=size, name="Large", price_delta=5000)
    es_kopi = Product.objects.create(category=kopi, name="Es Kopi Susu", price=18000)
    es_kopi.modifier_groups.add(size)
    tubruk = Product.objects.create(category=kopi, name="Kopi Tubruk", price=10000)
    tubruk.available_outlets.add(other)  # hanya di outlet lain
    andi = User.objects.create_user(username="andi", tenant=tctx, display_name="Andi", pin_hash=make_pin("111111"))
    andi.outlets.add(outlet)
    User.objects.create_user(username="sinta", tenant=tctx, display_name="Sinta")  # tidak punya akses outlet ini

    body = client.get("/api/v1/sync/master?version=0", **auth).json()

    snap = body["snapshot"]
    assert body["changed"] is True
    assert [p["name"] for p in snap["products"]] == ["Es Kopi Susu"]
    assert snap["products"][0]["modifier_group_ids"] == [str(size.id)]
    assert [(o["name"], o["price_delta"]) for o in snap["modifier_groups"][0]["options"]] == [("Large", 5000)]
    assert [s["name"] for s in snap["staff"]] == ["Andi"]
    assert check_pin("111111", snap["staff"][0]["pin_hash"])
    assert snap["outlet"]["code"] == "GRB01" and snap["device"]["number"] == device.number


def test_unchanged_version_returns_no_snapshot(client, tctx, device, auth):
    v = Tenant.objects.get(pk=tctx.pk).master_version
    body = client.get(f"/api/v1/sync/master?version={v}", **auth).json()
    assert body == {"changed": False, "version": v, "server_time": body["server_time"]}
    device.refresh_from_db()
    assert device.last_sync_at is not None
