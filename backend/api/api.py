"""API mobile /api/v1 (desain teknis §5)."""
import secrets

from django.utils import timezone
from ninja import NinjaAPI, Schema
from ninja.errors import ValidationError as NinjaValidationError

from core.models import Device, token_hash
from core.ratelimit import client_ip, hit

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
