from django import forms
from django.contrib.auth.forms import AuthenticationForm
from django.contrib.auth.password_validation import validate_password
from django.core.cache import cache

from core.models import Outlet, User
from core.pins import make_pin
from core.ratelimit import client_ip, hit
from core.tenancy import current_tenant_id

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


class StaffForm(forms.ModelForm):
    # Dideklarasikan manual: field otomatis dari model membangun queryset Outlet ber-tenant saat modul
    # di-import, sehingga terkunci ke tenant yang kebetulan aktif. Queryset asli diisi per request di __init__.
    outlets = forms.ModelMultipleChoiceField(queryset=Outlet.all_tenants.none(), required=False, label="Outlet")
    pin = forms.CharField(label="PIN app kasir (6 digit)", required=False, min_length=6, max_length=6,
                          help_text="Wajib untuk staf baru. Kosongkan jika tidak diubah.")
    new_password = forms.CharField(label="Password dashboard", required=False, widget=forms.PasswordInput,
                                   help_text="Hanya untuk owner/manager. Kosongkan jika tidak diubah.")

    class Meta:
        model = User
        fields = ["display_name", "username", "role", "outlets", "can_discount", "is_active"]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["outlets"].queryset = Outlet.objects.all()  # tenant aktif saat request ini

    def clean_pin(self):
        pin = self.cleaned_data["pin"]
        if pin and not pin.isdigit():
            raise forms.ValidationError("PIN harus 6 digit angka.")
        if not pin and not self.instance.pin_hash:
            raise forms.ValidationError("PIN wajib untuk staf baru.")
        return pin

    def clean(self):
        cleaned = super().clean()
        password = cleaned.get("new_password")
        has_password = not self.instance._state.adding and self.instance.has_usable_password()
        if cleaned.get("role") in (User.Role.OWNER, User.Role.MANAGER) and not (password or has_password):
            self.add_error("new_password", "Owner/manager butuh password untuk login dashboard.")
        if password:
            try:
                validate_password(password)
            except forms.ValidationError as e:
                self.add_error("new_password", e)
        return cleaned

    def save(self, commit=True):
        user = super().save(commit=False)
        user.tenant_id = current_tenant_id()
        if self.cleaned_data["pin"]:
            user.pin_hash = make_pin(self.cleaned_data["pin"])
        if self.cleaned_data["new_password"]:
            user.set_password(self.cleaned_data["new_password"])
        elif self.instance._state.adding:
            user.set_unusable_password()
        if commit:
            user.save()
            self.save_m2m()
        return user
