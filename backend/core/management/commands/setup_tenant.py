import getpass

from django.contrib.auth.password_validation import validate_password
from django.core.management.base import BaseCommand
from django.db import transaction

from core.models import Tenant, User
from core.pins import make_pin


class Command(BaseCommand):
    help = "Buat usaha (tenant) beserta akun owner pertama."

    def add_arguments(self, parser):
        parser.add_argument("--name", required=True, help="Nama usaha")
        parser.add_argument("--username", required=True, help="Username owner untuk login dashboard")
        parser.add_argument("--pin", required=True, help="PIN 6 digit owner untuk app kasir")
        parser.add_argument("--password", help="Kosongkan agar diminta secara interaktif")

    def handle(self, *args, name, username, pin, password, **options):
        password = password or getpass.getpass("Password owner: ")
        validate_password(password)
        with transaction.atomic():
            tenant = Tenant.objects.create(name=name)
            User.objects.create_user(username=username, password=password, tenant=tenant,
                                     role=User.Role.OWNER, display_name=username, pin_hash=make_pin(pin))
        self.stdout.write(self.style.SUCCESS(f"Usaha '{name}' dan owner '{username}' sudah dibuat."))
