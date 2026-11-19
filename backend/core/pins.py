"""PIN staf untuk app kasir. Diverifikasi OFFLINE di HP, jadi formatnya harus bisa dihitung ulang di Dart:
pbkdf2_sha256$<iterasi>$<salt>$<base64(PBKDF2-HMAC-SHA256(pin, salt UTF-8, iterasi, 32 byte))>."""
from django.contrib.auth.hashers import PBKDF2PasswordHasher, check_password

# Kenop kalibrasi: verifikasi di HP termurah harus < 300 ms (desain §3.3).
# Hash lama tetap valid karena jumlah iterasi tersimpan di dalam hash.
PIN_ITERATIONS = 20_000


def make_pin(pin: str) -> str:
    if len(pin) != 6 or not pin.isdigit():
        raise ValueError("PIN harus 6 digit angka")
    hasher = PBKDF2PasswordHasher()
    return hasher.encode(pin, hasher.salt(), iterations=PIN_ITERATIONS)


def check_pin(pin: str, encoded: str) -> bool:
    return bool(encoded) and check_password(pin, encoded)
