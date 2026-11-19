from core.models import Tenant, User


def test_tenant_and_user_use_uuid7(db):
    tenant = Tenant.objects.create(name="Kopi Uji")
    user = User.objects.create_user(username="budi", password="rahasia-123", tenant=tenant, display_name="Budi")
    assert tenant.id.version == 7 and user.id.version == 7
    assert User.objects.get(username="budi").tenant == tenant
