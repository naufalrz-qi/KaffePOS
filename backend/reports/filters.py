"""Filter laporan (tanggal, outlet, staf) dan pembatasan outlet per peran (spec §5)."""
from datetime import timedelta

from django import forms
from django.http import Http404
from django.utils import timezone

from core.models import Outlet, User

MAX_DAYS = 366


def allowed_outlets(user):
    """Satu-satunya sumber pembatasan outlet: owner semua, manager hanya yang ditugaskan."""
    outlets = Outlet.objects.order_by("name")
    if user.role == User.Role.OWNER:
        return outlets
    return outlets.filter(pk__in=user.outlets.values("pk"))


class ReportFilter(forms.Form):
    dari = forms.DateField(label="Dari", widget=forms.DateInput(attrs={"type": "date"}))
    sampai = forms.DateField(label="Sampai", widget=forms.DateInput(attrs={"type": "date"}))
    outlet = forms.ModelChoiceField(queryset=Outlet.all_tenants.none(), required=False, empty_label="Semua outlet")
    staf = forms.ModelChoiceField(queryset=User.objects.none(), required=False, empty_label="Semua staf",
                                  to_field_name="pk")

    def __init__(self, data, user):
        super().__init__(data)
        self.allowed = allowed_outlets(user)
        self.fields["outlet"].queryset = self.allowed
        self.fields["staf"].queryset = User.in_tenant.exclude(role=User.Role.OWNER, pin_hash="").order_by("display_name")
        outlet_id = (data or {}).get("outlet")
        if outlet_id and not self.allowed.filter(pk=outlet_id).exists():
            raise Http404("Outlet tidak ditemukan")

    def clean(self):
        cleaned = super().clean()
        dari, sampai = cleaned.get("dari"), cleaned.get("sampai")
        if dari and sampai:
            if dari > sampai:
                raise forms.ValidationError("Tanggal 'dari' harus sebelum 'sampai'.")
            if (sampai - dari).days + 1 > MAX_DAYS:
                raise forms.ValidationError(f"Rentang maksimal {MAX_DAYS} hari.")
        return cleaned

    @property
    def outlet_ids(self):
        chosen = self.cleaned_data.get("outlet")
        return [chosen.pk] if chosen else list(self.allowed.values_list("pk", flat=True))


def default_dates(today=None):
    """Default filter = hari ini (WIB). Hari ini per zona outlet dipakai di beranda."""
    today = today or timezone.localdate()
    return {"dari": today.isoformat(), "sampai": today.isoformat()}


def presets(today):
    """Tombol cepat: (label, dari, sampai)."""
    first = today.replace(day=1)
    return [("Hari ini", today, today), ("Kemarin", today - timedelta(1), today - timedelta(1)),
            ("7 hari", today - timedelta(6), today), ("Bulan ini", first, today)]
