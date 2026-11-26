from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.contrib.auth.views import LoginView
from django.shortcuts import redirect
from django.urls import reverse, reverse_lazy
from django.utils import timezone
from django.views.generic import CreateView, DetailView, ListView, UpdateView

from core.audit import form_changes, record
from core.models import AuditLog, Device, User

from .forms import BusinessForm, LoginForm


class OwnerRequired(LoginRequiredMixin, UserPassesTestMixin):
    """Halaman kelola data master & audit log hanya untuk owner."""

    def test_func(self):
        return self.request.user.role == User.Role.OWNER


class Login(LoginView):
    template_name = "dashboard/login.html"
    form_class = LoginForm


class DeviceList(OwnerRequired, ListView):
    template_name = "dashboard/device_list.html"

    def get_queryset(self):
        return Device.objects.select_related("outlet").order_by("number")


class DeviceCreate(OwnerRequired, CreateView):
    model = Device
    fields = ["name", "outlet"]
    template_name = "dashboard/form.html"
    extra_context = {"title": "Device baru"}

    def form_valid(self, form):
        response = super().form_valid(form)
        self.object.issue_activation_code()
        record(AuditLog.Action.DEVICE_CREATE, self.object, f"{self.object.name} · {self.object.outlet}",
               actor=self.request.user)
        return response

    def get_success_url(self):
        return reverse("device_detail", args=[self.object.pk])


class DeviceDetail(OwnerRequired, DetailView):
    model = Device
    template_name = "dashboard/device_detail.html"

    def post(self, request, pk):
        device = self.get_object()
        if "revoke" in request.POST:
            device.revoked_at = timezone.now()
            device.save(update_fields=["revoked_at"])
            record(AuditLog.Action.DEVICE_REVOKE, device, device.name, actor=request.user)
        elif device.activated_at is None and device.revoked_at is None:
            device.issue_activation_code()
            record(AuditLog.Action.DEVICE_CODE, device, device.name, actor=request.user)
        return redirect("device_detail", pk=pk)


class BusinessUpdate(OwnerRequired, UpdateView):
    """Profil usaha (PRD A-01) dan metode pembayaran aktif (M-06) milik owner yang login."""
    form_class = BusinessForm
    template_name = "dashboard/form.html"
    extra_context = {"title": "Profil usaha"}
    success_url = reverse_lazy("home")

    def get_object(self, queryset=None):
        return self.request.user.tenant

    def form_valid(self, form):
        changes = form_changes(form)
        response = super().form_valid(form)
        if changes:
            record(AuditLog.Action.UPDATE, self.object, f"{self.object} — {changes}", actor=self.request.user)
        return response
