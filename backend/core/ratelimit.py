"""Rate-limit sederhana di atas cache Django. DatabaseCache berlaku lintas worker tanpa Redis."""
from django.core.cache import cache


def hit(key: str, window_seconds: int) -> int:
    """Catat satu kejadian untuk `key`; kembalikan jumlah kejadian dalam jendela waktu ini."""
    # ponytail: get+set DatabaseCache tidak atomik, jadi hitungan bisa meleset sedikit saat ramai; cukup untuk rate-limit
    cache.add(key, 0, window_seconds)
    try:
        return cache.incr(key)
    except ValueError:  # key kedaluwarsa di antara add() dan incr()
        cache.set(key, 1, window_seconds)
        return 1


def client_ip(request) -> str:
    """IP klien. Di belakang Caddy, alamat asli = nilai TERAKHIR X-Forwarded-For (ditambahkan Caddy)."""
    forwarded = request.META.get("HTTP_X_FORWARDED_FOR")
    return forwarded.split(",")[-1].strip() if forwarded else request.META.get("REMOTE_ADDR", "")
