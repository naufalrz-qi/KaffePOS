"""API mobile /api/v1 (desain teknis §5)."""
import secrets
from uuid import UUID

from django.utils import timezone
from ninja import Field, NinjaAPI, Schema
from ninja.errors import AuthenticationError
from ninja.errors import ValidationError as NinjaValidationError
from ninja.security import HttpBearer

from core.models import Device, Tenant, token_hash
from core.ratelimit import client_ip, hit
from core.tenancy import activate_tenant

from .push import process_event
from .snapshot import build_snapshot

api = NinjaAPI(title="KaffePOS API", version="1", urls_namespace="api_v1")


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message


@api.exception_handler(ApiError)
def on_api_error(request, exc):
    return api.create_response(request, {"error": exc.code, "message": exc.message}, status=exc.status)


@api.exception_handler(NinjaValidationError)
def on_validation_error(request, exc):
    return api.create_response(request, {"error": "invalid_request", "message": str(exc.errors)[:500]}, status=400)


@api.exception_handler(AuthenticationError)
def on_missing_token(request, exc):
    return api.create_response(request, {"error": "invalid_token", "message": "Token device wajib diisi"}, status=401)


class DeviceAuth(HttpBearer):
    def authenticate(self, request, token):
        device = (Device.all_tenants.select_related("outlet", "tenant").defer("outlet__qris_image")
                  .filter(token_hash=token_hash(token)).first())
        if device is None:
            raise ApiError(401, "invalid_token", "Token device tidak dikenal")
        if device.revoked_at:
            raise ApiError(401, "device_revoked", "Device sudah dicabut")
        activate_tenant(device.tenant_id)
        return device


device_auth = DeviceAuth()


class ActivateIn(Schema):
    code: str
    app_version: str = ""


@api.post("/device/activate", auth=None)
def activate(request, payload: ActivateIn):
    if hit(f"activate:{client_ip(request)}", 3600) > 10:
        raise ApiError(429, "rate_limited", "Terlalu banyak percobaan aktivasi, coba lagi nanti")
    code = payload.code.strip().upper()
    device = (Device.all_tenants.select_related("outlet")
              .filter(activation_code=code, activated_at__isnull=True, revoked_at__isnull=True,
                      activation_expires_at__gt=timezone.now())
              .first()) if len(code) == 8 else None
    if device is None:
        raise ApiError(400, "invalid_code", "Kode aktivasi salah, kedaluwarsa, atau sudah dipakai")
    token = secrets.token_urlsafe(32)
    device.token_hash, device.activation_code = token_hash(token), ""
    device.activated_at, device.app_version = timezone.now(), payload.app_version[:20]
    device.save()
    return {"token": token,
            "device": {"id": str(device.id), "number": device.number},
            "outlet": {"id": str(device.outlet_id), "code": device.outlet.code, "name": device.outlet.name}}


def master_version(device) -> int:
    return Tenant.objects.values_list("master_version", flat=True).get(pk=device.tenant_id)


@api.get("/sync/master", auth=device_auth)
def sync_master(request, version: int = 0):
    device = request.auth
    current = master_version(device)  # dibaca SEBELUM data, jadi tidak ada perubahan yang terlewat (desain §5)
    Device.all_tenants.filter(pk=device.pk).update(last_sync_at=timezone.now())
    body = {"changed": current != version, "version": current, "server_time": timezone.now()}
    if body["changed"]:
        body["snapshot"] = build_snapshot(device)
    return body


class EventIn(Schema):
    id: UUID
    type: str
    data: dict


class PushIn(Schema):
    pending_after: int = Field(0, ge=0)
    events: list[EventIn] = Field(max_length=100)


@api.post("/sync/push", auth=device_auth)
def sync_push(request, payload: PushIn):
    device = request.auth
    results = [process_event(device, e.id, e.type, e.data) for e in payload.events]
    Device.all_tenants.filter(pk=device.pk).update(
        last_sync_at=timezone.now(), pending_count=payload.pending_after,
        app_version=request.headers.get("X-App-Version", "")[:20])
    return {"results": results, "server_time": timezone.now(), "master_version": master_version(device)}
