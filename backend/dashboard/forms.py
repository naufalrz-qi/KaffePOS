from django import forms
from django.contrib.auth.forms import AuthenticationForm
from django.core.cache import cache

from core.models import User
from core.ratelimit import client_ip, hit

LOGIN_LIMIT, LOGIN_WINDOW = 5, 15 * 60


class LoginForm(AuthenticationForm):
    def clean(self):
        key = f"login:{self.data.get('username', '')}:{client_ip(self.request)}"
        if (cache.get(key) or 0) >= LOGIN_LIMIT:
            raise forms.ValidationError("Terlalu banyak percobaan gagal. Coba lagi 15 menit lagi.")
        try:
            return super().clean()
        except forms.ValidationError:
            hit(key, LOGIN_WINDOW)  # hanya kegagalan yang dihitung
            raise

    def confirm_login_allowed(self, user):
        super().confirm_login_allowed(user)
        if user.tenant_id is None or user.role not in (User.Role.OWNER, User.Role.MANAGER):
            raise forms.ValidationError("Akun ini tidak punya akses dashboard.", code="no_access")
