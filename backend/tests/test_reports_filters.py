from datetime import date

import pytest
from django.http import Http404

from core.models import Outlet, User
from reports.filters import ReportFilter, allowed_outlets


@pytest.fixture
def manager(tctx, outlet):
    m = User.objects.create_user(username="mgr", password="rahasia-123", tenant=tctx,
                                 role=User.Role.MANAGER, display_name="Mgr")
    m.outlets.add(outlet)
    return m


def test_owner_sees_all_outlets_manager_only_assigned(owner, manager, outlet):
    other = Outlet.objects.create(code="KMG", name="Kemang")
    assert set(allowed_outlets(owner)) == {outlet, other}
    assert list(allowed_outlets(manager)) == [outlet]


def test_valid_filter_and_outlet_ids(owner, outlet):
    f = ReportFilter({"dari": "2026-11-01", "sampai": "2026-11-21", "outlet": str(outlet.pk)}, user=owner)
    assert f.is_valid(), f.errors
    assert f.cleaned_data["dari"] == date(2026, 11, 1) and f.outlet_ids == [outlet.pk]


def test_manager_outlet_outside_assignment_is_404(manager):
    other = Outlet.objects.create(code="KMG", name="Kemang")
    with pytest.raises(Http404):
        ReportFilter({"dari": "2026-11-01", "sampai": "2026-11-01", "outlet": str(other.pk)}, user=manager).is_valid()


@pytest.mark.parametrize("dari,sampai", [("2026-11-21", "2026-11-01"), ("2025-01-01", "2026-11-21")])
def test_bad_range_is_form_error(owner, dari, sampai):
    f = ReportFilter({"dari": dari, "sampai": sampai}, user=owner)
    assert not f.is_valid() and f.non_field_errors()


def test_non_uuid_outlet_is_404(owner):
    with pytest.raises(Http404):
        ReportFilter({"dari": "2026-11-01", "sampai": "2026-11-01", "outlet": "abc"}, user=owner)


def test_staf_choices_follow_role(tctx, owner, manager, outlet):
    from tests.factories import make_staff
    other = Outlet.objects.create(code="KMG", name="Kemang")
    mine, theirs = make_staff(tctx, outlet, "Mine"), make_staff(tctx, other, "Theirs")
    for u in (mine, theirs):
        u.set_password("x"); u.pin_hash = "h"; u.save()
    data = {"dari": "2026-11-01", "sampai": "2026-11-01"}
    mgr = set(ReportFilter(data, user=manager).fields["staf"].queryset)
    own = set(ReportFilter(data, user=owner).fields["staf"].queryset)
    assert mine in mgr and theirs not in mgr
    assert {mine, theirs} <= own
