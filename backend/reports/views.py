from datetime import datetime, time, timedelta

from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.http import HttpResponse
from django.utils import timezone
from django.utils.dateparse import parse_date
from django.views import View
from django.views.generic import ListView, TemplateView

from core.models import AuditLog, User
from dashboard.views import OwnerRequired

from . import queries as q
from .excel import build_workbook
from .filters import ReportFilter, allowed_outlets, default_dates, presets

TABS = [("laporan", "Penjualan"), ("laporan_produk", "Produk"), ("laporan_shift", "Shift"),
        ("laporan_void", "Void & diskon")]


class ReportAccess(LoginRequiredMixin, UserPassesTestMixin):
    def test_func(self):
        return self.request.user.role in (User.Role.OWNER, User.Role.MANAGER)


def _filter(request):
    data = request.GET.copy()
    for k, v in default_dates().items():
        data.setdefault(k, v)
    return data, ReportFilter(data, user=request.user)


class Beranda(ReportAccess, TemplateView):
    template_name = "reports/beranda.html"

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        outlets = list(allowed_outlets(self.request.user))
        ids = [o.pk for o in outlets]
        sales = q.sales_today(outlets)
        ctx.update(outlets=outlets, s=q.summary(sales), per_outlet=q.by_outlet(sales), per_metode=q.by_method(sales),
                   per_jam=q.by_hour(sales), terlaris=q.by_product(sales)[:5], devices=q.device_status(ids),
                   shift_lama=q.stale_shifts(ids))
        return ctx


class Laporan(ReportAccess, TemplateView):
    template_name = "reports/laporan.html"
    tab = "laporan"

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        data, form = _filter(self.request)
        ctx.update(form=form, tab=self.tab, tabs=TABS, presets=presets(timezone.localdate()),
                   query=data.urlencode(), has_outlets=form.allowed.exists())
        if form.is_valid() and ctx["has_outlets"]:
            c = form.cleaned_data
            sales = q.sales_between(form.outlet_ids, c["dari"], c["sampai"], c["staf"])
            ctx["s"] = q.summary(sales)
            if self.tab == "laporan":
                ctx.update(harian=q.by_day(sales), per_outlet=q.by_outlet(sales), per_metode=q.by_method(sales),
                           per_staf=q.by_staff(sales), per_jam=q.by_hour(sales))
            elif self.tab == "laporan_produk":
                ctx.update(produk=q.by_product(sales), kategori=q.by_category(sales), modifier=q.by_modifier(sales))
            elif self.tab == "laporan_shift":
                ctx["shifts"] = q.shifts_between(form.outlet_ids, c["dari"], c["sampai"], c["staf"])
            else:
                ctx.update(voids=q.voids(sales), discounts=q.discounts(sales))
        return ctx


class Excel(ReportAccess, View):
    def get(self, request):
        _, form = _filter(request)
        if not form.is_valid():
            return HttpResponse("Filter tidak valid", status=400)
        c = form.cleaned_data
        body = build_workbook(form.outlet_ids, c["dari"], c["sampai"], c["staf"], judul=request.user.tenant.name)
        response = HttpResponse(body, content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        response["Content-Disposition"] = f'attachment; filename="laporan-{c["dari"]}_{c["sampai"]}.xlsx"'
        return response


def _start_of(day):
    """Awal hari dalam zona TIME_ZONE (WIB)."""
    return timezone.make_aware(datetime.combine(day, time.min))


class Audit(OwnerRequired, ListView):
    template_name = "reports/audit.html"
    paginate_by = 50

    def get_queryset(self):
        logs = AuditLog.objects.select_related("actor", "device").order_by("-at")
        get = self.request.GET
        if get.get("aksi") in AuditLog.Action.values:
            logs = logs.filter(action=get["aksi"])
        try:  # tanggal rusak / di luar jangkauan = tanpa filter
            dari, sampai = parse_date(get.get("dari") or ""), parse_date(get.get("sampai") or "")
            start = _start_of(dari) if dari else None
            end = _start_of(sampai + timedelta(1)) if sampai else None
        except (ValueError, OverflowError):
            start = end = None
        if start:
            logs = logs.filter(at__gte=start)
        if end:
            logs = logs.filter(at__lt=end)
        return logs

    def get_context_data(self, **kwargs):
        get = self.request.GET.copy()
        get.pop("page", None)
        return super().get_context_data(actions=AuditLog.Action.choices, aksi=get.get("aksi", ""),
                                        dari=get.get("dari", ""), sampai=get.get("sampai", ""),
                                        query=get.urlencode(), **kwargs)
