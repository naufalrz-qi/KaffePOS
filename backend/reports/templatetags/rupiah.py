from django import template

from core.audit import rupiah as fmt

register = template.Library()


@register.filter
def rupiah(value):
    return "-" if value is None else fmt(int(value))
