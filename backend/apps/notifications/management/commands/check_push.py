"""
Checks that push notifications can be delivered, without sending any.

    python manage.py check_push                  credential + Google sign-in
    python manage.py check_push --token <FCM>    also validates a real device
    python manage.py check_push --user <id>      validates that user's devices

Use it after rotating the Firebase key. It prints the Firebase project id and
pass/fail results only - never any part of the key or a device token.
"""

from django.core.management.base import BaseCommand, CommandError

from apps.notifications import push
from apps.notifications.models import DeviceToken


def _mask(token):
    return f'...{token[-6:]}' if token and len(token) > 6 else '...'


class Command(BaseCommand):
    help = 'Verifies the Firebase credential and, optionally, device tokens (validate-only, nothing is delivered).'

    def add_arguments(self, parser):
        parser.add_argument('--token', help='An FCM device token to validate.')
        parser.add_argument('--user', type=int, help='Validate every active device of this user id.')

    def handle(self, *args, **options):
        problem = push.configuration_problem()
        if problem:
            raise CommandError(f'Push is not configured: {problem}')
        self.stdout.write(self.style.SUCCESS(f'Credential file found for Firebase project: {push.project_id()}'))

        push.reset_token_cache()
        try:
            access_token = push._access_token()
        except Exception as exc:  # noqa: BLE001 - report the class, never the details
            raise CommandError(
                f'Google refused the credential ({exc.__class__.__name__}). '
                'If the key was rotated, check the new file is in place and the old key is deleted.'
            )
        if not access_token:
            raise CommandError('Could not obtain an access token from Google.')
        self.stdout.write(self.style.SUCCESS('Signed in to Google with the service account.'))

        tokens = []
        if options.get('token'):
            tokens.append(options['token'])
        if options.get('user'):
            tokens.extend(
                DeviceToken.objects.filter(user_id=options['user'], is_active=True).values_list('token', flat=True)
            )
        if not tokens:
            self.stdout.write('No device token given; skipped the device check (pass --token or --user).')
            return

        for token in tokens:
            result = push.send_to_tokens([token], 'SchoolConnect check', 'Validation only', validate_only=True)
            if result['auth_failed']:
                raise CommandError('Firebase rejected the credential while validating a device.')
            if result['sent']:
                self.stdout.write(self.style.SUCCESS(f'Device {_mask(token)}: valid (nothing delivered).'))
            elif result['invalid_tokens']:
                self.stdout.write(self.style.WARNING(f'Device {_mask(token)}: token is dead - the phone should re-register.'))
            else:
                self.stdout.write(self.style.WARNING(f'Device {_mask(token)}: could not be validated.'))
