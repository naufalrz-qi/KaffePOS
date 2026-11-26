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


def sale_event(sale_id, shift_id, kasir, total=46000, receipt="GRB01-1-261119-0001"):
    return ("sale.completed", {
        "sale_id": str(sale_id), "shift_id": str(shift_id), "staff_id": str(kasir.id),
        "receipt_no": receipt, "created_at": NOW, "customer_label": "Budi",
        "member": {"phone": "+6281234567890"},
        "pricing": {"tax_enabled": False, "tax_rate_bp": 0, "tax_inclusive": False, "rounding_unit": 0},
        "items": [{"id": str(uuid.uuid4()), "product_id": str(uuid.uuid4()), "name": "Es Kopi Susu",
                   "category_name": "Kopi", "qty": 2, "unit_price": 18000, "discount": 0,
                   "earns_stamp": True, "is_reward": False, "note": "",
                   "modifiers": [{"option_id": str(uuid.uuid4()), "group_name": "Ukuran",
                                  "name": "Large", "price_delta": 5000}]}],
        "order_discount": 0, "discount_reason": None,
        "subtotal": 46000, "tax_total": 0, "rounding": 0, "total": total,
        "payments": [{"id": str(uuid.uuid4()), "method": "CASH", "amount": 46000,
                      "tendered": 50000, "change": 4000, "reference": None}]})


def sale_voided(sale_id, kasir):
    return ("sale.voided", {"sale_id": str(sale_id), "staff_id": str(kasir.id), "approved_by_id": None,
                            "voided_at": NOW, "reason": "salah input"})


def test_sale_is_stored_once_with_snapshot(client, auth, kasir):
    sid, sale_id = uuid.uuid4(), uuid.uuid4()
    assert push(client, auth, shift_opened(sid, kasir), sale_event(sale_id, sid, kasir))[0] == ["ok", "ok"]
    assert push(client, auth, sale_event(sale_id, sid, kasir))[0] == ["duplicate"]
    sale = Sale.objects.get(pk=sale_id)
    assert (sale.total, sale.flags, sale.local_hour, sale.member_ref) == (46000, "", 10, "+6281234567890")
    item = sale.items.get()
    assert (item.line_total, item.modifiers.get().name) == (46000, "Large")
    assert sale.payments.get().change_amount == 4000


def test_wrong_total_is_accepted_and_flagged(client, auth, kasir):
    sid, sale_id = uuid.uuid4(), uuid.uuid4()
    push(client, auth, shift_opened(sid, kasir), sale_event(sale_id, sid, kasir, total=40000))
    assert Sale.objects.get(pk=sale_id).flags == "total_mismatch"


def test_duplicate_receipt_number_is_flagged(client, auth, kasir):
    sid, first, second = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    push(client, auth, shift_opened(sid, kasir), sale_event(first, sid, kasir), sale_event(second, sid, kasir))
    assert Sale.objects.get(pk=second).flags == "duplicate_receipt_no"


def test_void_is_idempotent_and_excluded_from_expected_cash(client, auth, kasir):
    sid, keep, cancel = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    statuses, _ = push(client, auth, shift_opened(sid, kasir),
                       sale_event(keep, sid, kasir, receipt="R-1"), sale_event(cancel, sid, kasir, receipt="R-2"),
                       sale_voided(cancel, kasir), shift_closed(sid, kasir, counted=146000))
    assert statuses == ["ok"] * 5
    assert Sale.objects.get(pk=cancel).status == Sale.Status.VOIDED
    assert Shift.objects.get(pk=sid).expected_cash == 146000  # modal 100.000 + tunai 46.000
    assert push(client, auth, sale_voided(cancel, kasir))[0] == ["duplicate"]


def test_void_before_sale_is_retried(client, auth, kasir):
    assert push(client, auth, sale_voided(uuid.uuid4(), kasir))[0] == ["retry"]


def test_shift_of_another_device_is_forbidden(client, auth, kasir, outlet):
    other = Device.objects.create(outlet=outlet, name="HP lain")
    sid = uuid.uuid4()
    Shift.objects.create(id=sid, outlet=outlet, device=other, staff=kasir, opened_at=timezone.now(),
                         opening_cash=0, business_date=timezone.localdate())
    statuses, body = push(client, auth, sale_event(uuid.uuid4(), sid, kasir))
    assert statuses == ["rejected"] and body["results"][0]["reason"] == "forbidden"


from core.models import AuditLog  # noqa: E402


def test_discount_is_audited_with_approver_once(client, auth, kasir, tctx):
    manager = User.objects.create_user(username="sari", tenant=tctx, display_name="Bu Sari", role=User.Role.MANAGER)
    sid, sale_id = uuid.uuid4(), uuid.uuid4()
    _, ev = sale_event(sale_id, sid, kasir, total=40000)
    ev.update(order_discount=6000, discount_reason="pelanggan tetap", discount_approved_by_id=str(manager.id))
    ev["payments"][0]["amount"] = 40000
    push(client, auth, shift_opened(sid, kasir), ("sale.completed", ev))
    push(client, auth, ("sale.completed", ev))  # kirim ulang
    sale = Sale.objects.get(pk=sale_id)
    assert sale.discount_approved_by == manager
    log = AuditLog.objects.get(action="discount")
    assert log.actor == kasir and "6.000" in log.detail and "Bu Sari" in log.detail


def test_old_app_without_approver_field_still_accepted(client, auth, kasir):
    sid, sale_id = uuid.uuid4(), uuid.uuid4()
    statuses, _ = push(client, auth, shift_opened(sid, kasir), sale_event(sale_id, sid, kasir))
    assert statuses == ["ok", "ok"] and Sale.objects.get(pk=sale_id).discount_approved_by is None
    assert not AuditLog.objects.filter(action="discount").exists()


def test_void_is_audited_once(client, auth, kasir):
    sid, sale_id = uuid.uuid4(), uuid.uuid4()
    push(client, auth, shift_opened(sid, kasir), sale_event(sale_id, sid, kasir))
    push(client, auth, sale_voided(sale_id, kasir))
    push(client, auth, sale_voided(sale_id, kasir))
    log = AuditLog.objects.get(action="void")
    assert log.actor == kasir and "salah input" in log.detail and log.object_id == str(sale_id)
