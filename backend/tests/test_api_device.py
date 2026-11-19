import json

from core.models import Device


def post(client, url, body):
    return client.post(url, data=json.dumps(body), content_type="application/json")


def test_activation_returns_token_once(client, tctx, outlet):
    device = Device.objects.create(outlet=outlet, name="HP 1")
    code = device.issue_activation_code()
    r = post(client, "/api/v1/device/activate", {"code": code.lower(), "app_version": "1.0.0"})
    assert r.status_code == 200
    body = r.json()
    assert body["device"] == {"id": str(device.id), "number": device.number}
    assert body["outlet"]["code"] == "GRB01" and len(body["token"]) >= 40
    again = post(client, "/api/v1/device/activate", {"code": code})
    assert again.status_code == 400 and again.json()["error"] == "invalid_code"


def test_activation_is_rate_limited_per_ip(client, db):
    for _ in range(10):
        post(client, "/api/v1/device/activate", {"code": "XXXXXXXX"})
    r = post(client, "/api/v1/device/activate", {"code": "XXXXXXXX"})
    assert r.status_code == 429 and r.json()["error"] == "rate_limited"


def test_malformed_body_is_invalid_request(client, db):
    r = post(client, "/api/v1/device/activate", {"kode": "salah-nama-field"})
    assert r.status_code == 400 and r.json()["error"] == "invalid_request"
