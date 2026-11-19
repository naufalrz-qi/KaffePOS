"""Naikkan Tenant.master_version setiap kali data master berubah, supaya HP mengunduh ulang snapshot
(desain §3.4). Jangan pakai QuerySet.update()/bulk_update() pada model master: keduanya tidak memicu sinyal."""
from django.apps import apps
from django.db.models import F
from django.db.models.signals import m2m_changed, post_delete, post_save

MASTER_MODELS = [
    "core.Tenant", "core.Outlet", "core.User",
    "catalog.Category", "catalog.ModifierGroup", "catalog.ModifierOption", "catalog.Product",
]
MASTER_M2M = [("core.User", "outlets"), ("catalog.Product", "modifier_groups"), ("catalog.Product", "available_outlets")]


def bump(tenant_id):
    apps.get_model("core.Tenant").objects.filter(pk=tenant_id).update(master_version=F("master_version") + 1)


def _tenant_id(instance):
    return instance.pk if instance._meta.label == "core.Tenant" else instance.tenant_id


def _on_save(sender, instance, update_fields=None, **kwargs):
    if update_fields and set(update_fields) <= {"last_login"}:
        return
    if _tenant_id(instance):
        bump(_tenant_id(instance))


def _on_delete(sender, instance, **kwargs):
    if _tenant_id(instance):
        bump(_tenant_id(instance))


def _on_m2m(sender, instance, action, **kwargs):
    if action.startswith("post_") and instance.tenant_id:
        bump(instance.tenant_id)


def connect():
    for label in MASTER_MODELS:
        model = apps.get_model(label)
        post_save.connect(_on_save, sender=model, dispatch_uid=f"master-save-{label}")
        post_delete.connect(_on_delete, sender=model, dispatch_uid=f"master-delete-{label}")
    for label, field in MASTER_M2M:
        through = getattr(apps.get_model(label), field).through
        m2m_changed.connect(_on_m2m, sender=through, dispatch_uid=f"master-m2m-{label}.{field}")
