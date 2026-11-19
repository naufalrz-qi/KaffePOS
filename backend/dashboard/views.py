from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.contrib.auth.views import LoginView
from django.shortcuts import redirect
from django.urls import reverse
from django.utils import timezone
from django.views.generic import CreateView, DetailView, ListView, TemplateView

from core.models import Device, User

from .forms import LoginForm


class OwnerRequired(LoginRequiredMixin, UserPassesTestMixin):
    """Halaman kelola data master hanya untuk owner. Akses manager untuk laporan menyusul di M4."""

    def test_func(self):
        return self.request.user.role == User.Role.OWNER


class Login(LoginView):
    template_name = "dashboard/login.html"
    form_class = LoginForm


class Home(LoginRequiredMixin, TemplateView):
    template_name = "dashboard/home.html"


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
        elif device.activated_at is None and device.revoked_at is None:
            device.issue_activation_code()
        return redirect("device_detail", pk=pk)
