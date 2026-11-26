"""Halaman daftar/tambah/ubah generik untuk data master. Semua query lewat manager ber-tenant,
jadi objek usaha lain otomatis 404 dan tidak muncul di pilihan form."""
from django.urls import path, reverse_lazy
from django.views.generic import CreateView, ListView, UpdateView

from core.audit import form_changes, record
from core.models import AuditLog

from .views import OwnerRequired


def display(obj, field):
    getter = getattr(obj, f"get_{field}_display", None)
    value = getter() if getter else getattr(obj, field)
    if isinstance(value, bool):
        return "Ya" if value else "Tidak"
    return value


def crud(model_cls, form_fields, columns, prefix, title, manager="objects", form_cls=None):
    def scoped():
        return getattr(model_cls, manager).all()

    class List(OwnerRequired, ListView):
        template_name = "dashboard/list.html"

        def get_queryset(self):
            return scoped()

        def get_context_data(self, **kwargs):
            ctx = super().get_context_data(**kwargs)
            ctx.update(
                title=title, prefix=prefix,
                headers=[model_cls._meta.get_field(c).verbose_name for c in columns],
                rows=[(o.pk, [display(o, c) for c in columns]) for o in ctx["object_list"]],
            )
            return ctx

    class Edit(OwnerRequired):
        model = model_cls
        fields = None if form_cls else form_fields
        form_class = form_cls
        template_name = "dashboard/form.html"
        success_url = reverse_lazy(f"{prefix}_list")
        extra_context = {"title": title}

        def get_queryset(self):
            return scoped()

        def form_valid(self, form):
            adding = form.instance._state.adding
            changes = "" if adding else form_changes(form)
            response = super().form_valid(form)
            if adding:
                record(AuditLog.Action.CREATE, self.object, f"{title}: {self.object}", actor=self.request.user)
            elif changes:
                record(AuditLog.Action.UPDATE, self.object, f"{self.object} — {changes}", actor=self.request.user)
            return response

    class Create(Edit, CreateView):
        pass

    class Update(Edit, UpdateView):
        pass

    return [
        path(f"{prefix}/", List.as_view(), name=f"{prefix}_list"),
        path(f"{prefix}/baru/", Create.as_view(), name=f"{prefix}_create"),
        path(f"{prefix}/<uuid:pk>/", Update.as_view(), name=f"{prefix}_update"),
    ]
