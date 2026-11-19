import pytest
from django.utils import timezone

from core.models import Device, Outlet, Tenant
from core.tenancy import NoTenant, tenant_context


def test_query_without_tenant_fails_closed(db):
    with pytest.raises(NoTenant):
        list(Outlet.objects.all())


def test_objects_only_sees_active_tenant(db):
    a, b = Tenant.objects.create(name="A"), Tenant.objects.create(name="B")
    with tenant_context(a.id):
        Outlet.objects.create(code="A1", name="Outlet A")
    with tenant_context(b.id):
        Outlet.objects.create(code="B1", name="Outlet B")
        assert [o.code for o in Outlet.objects.all()] == ["B1"]
    assert Outlet.all_tenants.count() == 2


def test_device_numbers_increase_and_are_never_reused(tctx, outlet):
    first = Device.objects.create(outlet=outlet, name="HP 1")
    first.delete()
    second = Device.objects.create(outlet=outlet, name="HP 2")
    assert (first.number, second.number) == (1, 2)


def test_activation_code_is_crockford_and_expires(tctx, outlet):
    device = Device.objects.create(outlet=outlet, name="HP 1")
    code = device.issue_activation_code()
    assert len(code) == 8 and not set(code) & set("ILOU")
    assert device.activation_expires_at > timezone.now()
