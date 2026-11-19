from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.contrib.auth.views import LoginView
from django.views.generic import TemplateView

from core.models import User

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
