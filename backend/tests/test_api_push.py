import json
import uuid

import pytest
from django.utils import timezone

from core.models import Device, User
from sales.models import CashMovement, Sale, Shift

NOW = "2026-11-19T03:00:00Z"  # = 10:00 WIB


def push(client, auth, *events, pending_after=0):
    body = {"pending_after": pending_after,
            "events": [{"id": str(uuid.uuid4()), "type": t, "data": d} for t, d in events]}
    r = client.post("/api/v1/sync/push", data=json.dumps(body), content_type="application/json", **auth)
    assert r.status_code == 200, r.content
    return [x["status"] for x in r.json()["results"]], r.json()


@pytest.fixture
def kasir(tctx, outlet):
    user = User.objects.create_user(username="andi", tenant=tctx, display_name="Andi")
    user.outlets.add(outlet)
    return user


def shift_opened(shift_id, kasir, cash=100000):
    return ("shift.opened", {"shift_id": str(shift_id), "staff_id": str(kasir.id),
                             "opened_at": NOW, "opening_cash": cash})


def cash_moved(shift_id, kasir, amount=15000, direction="OUT", move_id=None):
    return ("cash.moved", {"id": str(move_id or uuid.uuid4()), "shift_id": str(shift_id),
                           "staff_id": str(kasir.id), "at": NOW, "direction": direction,
                           "amount": amount, "note": "es batu"})


def shift_closed(shift_id, kasir, counted):
    return ("shift.closed", {"shift_id": str(shift_id), "staff_id": str(kasir.id),
                             "closed_at": NOW, "counted_cash": counted})


def test_shift_open_is_idempotent_and_uses_local_date(client, auth, kasir):
    sid = uuid.uuid4()
    assert push(client, auth, shift_opened(sid, kasir))[0] == ["ok"]
    assert push(client, auth, shift_opened(sid, kasir))[0] == ["duplicate"]
    assert Shift.objects.get(pk=sid).business_date.isoformat() == "2026-11-19"


def test_cash_before_shift_is_retried_then_accepted(client, auth, kasir):
    sid, mid = uuid.uuid4(), uuid.uuid4()
    assert push(client, auth, cash_moved(sid, kasir, move_id=mid))[0] == ["retry"]
    assert push(client, auth, shift_opened(sid, kasir), cash_moved(sid, kasir, move_id=mid))[0] == ["ok", "ok"]
    assert CashMovement.objects.get(pk=mid).amount == 15000


def test_invalid_payload_is_rejected_with_field_name(client, auth, kasir):
    statuses, body = push(client, auth, shift_opened(uuid.uuid4(), kasir, cash=-5))
    assert statuses == ["rejected"] and "opening_cash" in body["results"][0]["reason"]


def test_unknown_event_type_is_rejected(client, auth):
    assert push(client, auth, ("member.teleported", {}))[0] == ["rejected"]


def test_shift_close_computes_expected_cash(client, auth, kasir):
    sid = uuid.uuid4()
    statuses, _ = push(client, auth, shift_opened(sid, kasir, cash=100000), cash_moved(sid, kasir, 15000),
                       shift_closed(sid, kasir, counted=80000))
    assert statuses == ["ok", "ok", "ok"]
    shift = Shift.objects.get(pk=sid)
    assert (shift.expected_cash, shift.counted_cash) == (85000, 80000)
    assert push(client, auth, shift_closed(sid, kasir, counted=80000))[0] == ["duplicate"]


def test_push_updates_device_status(client, auth, device):
    push(client, auth, pending_after=7)
    device.refresh_from_db()
    assert (device.pending_count, device.app_version) == (7, "1.0.0") and device.last_sync_at


def test_more_than_100_events_is_invalid_request(client, auth):
    body = {"events": [{"id": str(uuid.uuid4()), "type": "x", "data": {}} for _ in range(101)]}
    r = client.post("/api/v1/sync/push", data=json.dumps(body), content_type="application/json", **auth)
    assert r.status_code == 400 and r.json()["error"] == "invalid_request"
