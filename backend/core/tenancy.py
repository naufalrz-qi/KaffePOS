"""Scoping data per tenant (desain §3.2). Query lewat `objects` tanpa tenant aktif = error (fail closed)."""
import contextvars
from contextlib import contextmanager

from django.db import models

_current = contextvars.ContextVar("kaffepos_tenant_id", default=None)


class NoTenant(Exception):
    pass


def current_tenant_id():
    tenant_id = _current.get()
    if tenant_id is None:
        raise NoTenant("Tidak ada tenant aktif untuk query ini")
    return tenant_id


def activate_tenant(tenant_id):
    """Set tenant aktif sampai request selesai. TenantMiddleware yang mereset nilainya."""
    _current.set(tenant_id)


@contextmanager
def tenant_context(tenant_id):
    token = _current.set(tenant_id)
    try:
        yield
    finally:
        _current.reset(token)


class TenantManager(models.Manager):
    def get_queryset(self):
        return super().get_queryset().filter(tenant_id=current_tenant_id())


class TenantScoped(models.Model):
    tenant = models.ForeignKey("core.Tenant", on_delete=models.PROTECT, related_name="+", editable=False)

    objects = TenantManager()
    all_tenants = models.Manager()

    class Meta:
        abstract = True

    def save(self, *args, **kwargs):
        if self.tenant_id is None:
            self.tenant_id = current_tenant_id()
        super().save(*args, **kwargs)


class TenantMiddleware:
    """Setiap request dimulai dengan tenant = tenant user dashboard (atau kosong). Auth API boleh
    menggantinya lewat activate_tenant(); semua nilai direset saat request selesai."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        user = request.user
        with tenant_context(user.tenant_id if user.is_authenticated else None):
            return self.get_response(request)
