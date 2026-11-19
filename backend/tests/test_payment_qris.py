import base64

from django.core.files.uploadedfile import SimpleUploadedFile

from core.models import Outlet, Tenant

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
OUTLET_FORM = {"code": "GRB01", "name": "Gerobak Sudirman", "type": "MOBILE", "timezone": "Asia/Jakarta",
               "tax_rate_bp": 1000, "rounding_unit": 0, "is_active": "on"}


def test_owner_sets_payment_methods(owner_client, tctx):
    r = owner_client.post("/usaha/", {"name": "Kopi Uji", "receipt_footer": "IG @kopiuji",
                                      "payment_methods": ["QRIS", "CASH"]})
    assert r.status_code == 302
    tenant = Tenant.objects.get(pk=tctx.pk)
    assert tenant.payment_methods == "CASH,QRIS" and tenant.receipt_footer == "IG @kopiuji"


def test_snapshot_has_payment_methods_and_qris(client, owner_client, outlet, auth):
    r = owner_client.post(f"/outlet/{outlet.pk}/", OUTLET_FORM | {"qris": SimpleUploadedFile("qris.png", PNG)})
    assert r.status_code == 302
    owner_client.post("/usaha/", {"name": "Kopi Uji", "payment_methods": ["CASH", "QRIS"]})
    snap = client.get("/api/v1/sync/master?version=0", **auth).json()["snapshot"]
    assert snap["payment_methods"] == ["CASH", "QRIS"]
    assert base64.b64decode(snap["outlet"]["qris_image"]) == PNG


def test_qris_must_be_image(owner_client, outlet):
    r = owner_client.post(f"/outlet/{outlet.pk}/", OUTLET_FORM | {"qris": SimpleUploadedFile("x.txt", b"bukan gambar")})
    assert r.status_code == 200 and "PNG atau JPG" in r.content.decode()
    assert not Outlet.objects.get(pk=outlet.pk).qris_image
