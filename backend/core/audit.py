"""Pencatatan audit log (PRD W-05). Dipanggil eksplisit di view/handler, di transaksi yang sama."""
from django.db import models

from .models import AuditLog

SECRET_FIELDS = {"pin", "new_password", "password", "qris"}


def rupiah(n: int) -> str:
    return f"{n:,}".replace(",", ".")


def record(action, obj=None, detail="", actor=None, device=None):
    AuditLog.objects.create(
        action=action, actor=actor, device=device,
        object_type=obj._meta.model_name if obj is not None else "",
        object_id=str(obj.pk) if obj is not None else "",
        detail=detail[:500])


def _show(value):
    if value is None or value == "":
        return "-"
    if isinstance(value, bool):
        return "Ya" if value else "Tidak"
    if isinstance(value, int):
        return rupiah(value)
    if isinstance(value, (list, tuple, set, models.QuerySet)):
        return ", ".join(sorted(str(v) for v in value)) or "-"
    return str(value)


def form_changes(form) -> str:
    """'Label: lama → baru' untuk setiap field yang berubah; field rahasia hanya 'Label diubah'."""
    parts = []
    for name in form.changed_data:
        label = form.fields[name].label or name
        if name in SECRET_FIELDS:
            parts.append(f"{label} diubah")
            continue
        old = form.initial.get(name)
        parts.append(f"{label}: {_show(_initial(form, name, old))} → {_show(form.cleaned_data.get(name))}")
    return "; ".join(parts)


def _initial(form, name, value):
    """Nilai awal ModelForm berupa pk; ubah ke objek supaya tampil sebagai nama."""
    field = form.fields[name]
    queryset = getattr(field, "queryset", None)
    if queryset is None or value in (None, ""):
        return value
    if isinstance(value, (list, tuple)):
        return list(queryset.filter(pk__in=[getattr(v, "pk", v) for v in value]))
    return queryset.filter(pk=getattr(value, "pk", value)).first()
