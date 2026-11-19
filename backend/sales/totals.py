"""Rumus total transaksi (desain §7.1). HARUS identik dengan versi Dart di app kasir;
keduanya diuji dengan shared/totals_cases.json. Hanya integer, tanpa float."""


def half_up(a: int, b: int) -> int:
    """Pembagian integer, setengah dibulatkan ke atas (a >= 0, b > 0)."""
    return (2 * a + b) // (2 * b)


def compute_totals(items, order_discount, tax_enabled, tax_rate_bp, tax_inclusive, rounding_unit):
    subtotal = sum(
        (i["unit_price"] + sum(m["price_delta"] for m in i["modifiers"])) * i["qty"] - i["discount"]
        for i in items
    )
    net = subtotal - order_discount
    if not tax_enabled:
        tax = 0
    elif tax_inclusive:
        tax = half_up(net * tax_rate_bp, 10000 + tax_rate_bp)
    else:
        tax = half_up(net * tax_rate_bp, 10000)
    before = net + tax if tax_enabled and not tax_inclusive else net
    total = before // rounding_unit * rounding_unit if rounding_unit else before  # selalu ke bawah
    return {"subtotal": subtotal, "tax_total": tax, "rounding": total - before, "total": total}
