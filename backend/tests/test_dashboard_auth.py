from core.models import User


def test_owner_can_log_in(client, owner):
    r = client.post("/login/", {"username": "owner", "password": "rahasia-123"})
    assert r.status_code == 302
    assert "Pak Owner" in client.get("/").content.decode()


def test_cashier_cannot_log_in(client, tctx):
    User.objects.create_user(username="kasir", password="rahasia-123", tenant=tctx, display_name="Kasir")
    r = client.post("/login/", {"username": "kasir", "password": "rahasia-123"})
    assert r.status_code == 200 and "tidak punya akses" in r.content.decode()


def test_login_blocked_after_five_failures(client, owner):
    for _ in range(5):
        client.post("/login/", {"username": "owner", "password": "salah"})
    r = client.post("/login/", {"username": "owner", "password": "rahasia-123"})
    assert r.status_code == 200 and "Terlalu banyak percobaan" in r.content.decode()


def test_home_requires_login(client, db):
    assert client.get("/").status_code == 302
