import pytest

from core.models import Outlet, Tenant
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
