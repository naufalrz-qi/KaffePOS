"""Snapshot master data untuk satu device (desain §5). HP mengganti snapshot lamanya secara utuh."""
import base64

from django.conf import settings
from django.db.models import Q

from catalog.models import Category, ModifierGroup, Product
from core.models import User


def build_snapshot(device):
    outlet, tenant = device.outlet, device.tenant
    staff = (User.in_tenant.filter(is_active=True)
             .filter(Q(role=User.Role.OWNER) | Q(outlets=outlet)).distinct())
    products = (Product.objects.filter(is_active=True, category__is_active=True)
                .filter(Q(available_outlets=None) | Q(available_outlets=outlet)).distinct()
                .prefetch_related("modifier_groups"))
    return {
        "min_app_version": settings.MIN_APP_VERSION,
        "business": {"name": tenant.name, "receipt_footer": tenant.receipt_footer},
        "outlet": {
            "id": str(outlet.id), "code": outlet.code, "name": outlet.name, "type": outlet.type,
            "timezone": outlet.timezone, "tax_enabled": outlet.tax_enabled,
            "tax_rate_bp": outlet.tax_rate_bp, "tax_inclusive": outlet.tax_inclusive,
            "rounding_unit": outlet.rounding_unit, "void_needs_manager": outlet.void_needs_manager,
            "receipt_header": outlet.receipt_header, "receipt_footer": outlet.receipt_footer,
            # ponytail: gambar QRIS (≤ 300 KB) ikut snapshot sebagai base64; pindah ke URL + cache di HP jika snapshot membesar
            "qris_image": base64.b64encode(bytes(outlet.qris_image)).decode() if outlet.qris_image else None,
        },
        "device": {"id": str(device.id), "number": device.number},
        "staff": [{"id": str(u.id), "name": u.display_name, "role": u.role,
                   "pin_hash": u.pin_hash, "can_discount": u.can_discount} for u in staff],
        "categories": [{"id": str(c.id), "name": c.name, "sort": c.sort}
                       for c in Category.objects.filter(is_active=True)],
        "products": [{"id": str(p.id), "category_id": str(p.category_id), "name": p.name,
                      "price": p.price, "earns_stamp": p.earns_stamp, "sort": p.sort,
                      "modifier_group_ids": [str(g.id) for g in p.modifier_groups.all()]}
                     for p in products],
        "modifier_groups": [{"id": str(g.id), "name": g.name, "required": g.required,
                             "multi": g.multi, "sort": g.sort,
                             "options": [{"id": str(o.id), "name": o.name, "price_delta": o.price_delta}
                                         for o in g.options.all() if o.is_active]}
                            for g in ModifierGroup.objects.prefetch_related("options")],
        "payment_methods": [m for m in tenant.payment_methods.split(",") if m],
        "stamp_rule": None,  # diisi di rencana M3 (loyalty)
    }
