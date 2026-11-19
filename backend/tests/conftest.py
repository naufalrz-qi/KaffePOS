import pytest
from django.utils import timezone

from core.models import Device, Outlet, Tenant, User, token_hash
from core.tenancy import tenant_context


@pytest.fixture
def tenant(db):
    return Tenant.objects.create(name="Kopi Uji")


@pytest.fixture
def tctx(tenant):
    """Tenant aktif selama test (seperti saat request dashboard/API)."""
    with tenant_context(tenant.id):
        yield tenant


@pytest.fixture
def outlet(tctx):
    return Outlet.objects.create(code="GRB01", name="Gerobak Sudirman")


@pytest.fixture
def device(outlet):
    return Device.objects.create(outlet=outlet, name="HP Kasir 1")


@pytest.fixture
def auth(device):
    """Header Authorization untuk device yang sudah aktif."""
    token = f"token-uji-{device.id.hex}"
    device.token_hash, device.activated_at = token_hash(token), timezone.now()
    device.save()
    return {"HTTP_AUTHORIZATION": f"Bearer {token}", "HTTP_X_APP_VERSION": "1.0.0"}


@pytest.fixture
def owner(tctx):
    return User.objects.create_user(username="owner", password="rahasia-123", tenant=tctx,
                                    role=User.Role.OWNER, display_name="Pak Owner")


@pytest.fixture
def owner_client(client, owner):
    client.force_login(owner)
    return client
