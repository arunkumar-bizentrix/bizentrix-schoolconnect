from django.core.management.base import BaseCommand
from apps.accounts.models import User
from apps.schools.models import School


class Command(BaseCommand):
    help = 'Seeds or updates local development demo users (Admin, Teacher, Parent)'

    def handle(self, *args, **options):
        school, _ = School.objects.get_or_create(
            id=1,
            defaults={
                'name': 'Vivekananda School, Bagalur',
                'code': 'VIV001',
                'address': 'Jogikalasanapalli, Bagalur, Tamil Nadu 635103',
                'contact_email': 'vivekanandaschoolbagalur@gmail.com',
                'contact_phone': '+91 94439 40772',
            }
        )

        demo_users = [
            {
                'username': 'admin',
                'password': 'Admin@123',
                'role': User.Role.ADMIN,
                'first_name': 'School',
                'last_name': 'Admin',
                'email': 'admin@schoolconnect.edu',
                'phone_number': '9000000001',
                'is_staff': True,
                'is_superuser': True,
            },
            {
                'username': 'teacher_priya',
                'password': 'Teacher@123',
                'role': User.Role.TEACHER,
                'first_name': 'Priya',
                'last_name': 'Sharma',
                'email': 'priya.sharma@schoolconnect.edu',
                'phone_number': '9876543210',
                'is_staff': False,
                'is_superuser': False,
            },
            {
                'username': 'parent_ravi',
                'password': 'Parent@123',
                'role': User.Role.PARENT,
                'first_name': 'Ravi',
                'last_name': 'Kumar',
                'email': 'ravi.kumar@schoolconnect.edu',
                'phone_number': '9000000002',
                'is_staff': False,
                'is_superuser': False,
            },
        ]

        for user_data in demo_users:
            username = user_data['username']
            password = user_data.pop('password')
            user, created = User.objects.get_or_create(
                username=username,
                defaults={
                    'school': school,
                    **user_data
                }
            )
            if not created:
                for k, v in user_data.items():
                    setattr(user, k, v)
                user.school = school

            user.set_password(password)
            user.save()

            action = 'Created' if created else 'Updated'
            self.stdout.write(
                self.style.SUCCESS(f'{action} demo user: {username} [{user.role}]')
            )

        # School 2 for multi-tenant testing
        school_b, _ = School.objects.get_or_create(
            code='XYZ2025',
            defaults={
                'name': 'XYZ International School',
                'contact_phone': '+91 91234 56789',
            }
        )

        demo_users_b = [
            {
                'username': 'admin_xyz',
                'password': 'Admin@123',
                'role': User.Role.ADMIN,
                'first_name': 'XYZ',
                'last_name': 'Admin',
                'email': 'admin@xyzschool.edu',
                'phone_number': '9000000003',
                'is_staff': True,
                'is_superuser': False,
            },
            {
                'username': 'teacher_vikram',
                'password': 'Teacher@123',
                'role': User.Role.TEACHER,
                'first_name': 'Vikram',
                'last_name': 'Mehta',
                'email': 'vikram.mehta@xyzschool.edu',
                'phone_number': '9000000004',
                'is_staff': False,
                'is_superuser': False,
            },
        ]

        for user_data in demo_users_b:
            username = user_data['username']
            password = user_data.pop('password')
            user, created = User.objects.get_or_create(
                username=username,
                defaults={
                    'school': school_b,
                    **user_data
                }
            )
            if not created:
                for k, v in user_data.items():
                    setattr(user, k, v)
                user.school = school_b

            user.set_password(password)
            user.save()

            action = 'Created' if created else 'Updated'
            self.stdout.write(
                self.style.SUCCESS(f'{action} demo user: {username} [{user.role}] (School B)')
            )
