#!/usr/bin/env python
"""Django's command-line utility for administrative tasks."""
import os
import sys


def main():
    """Run administrative tasks."""
    # `manage.py test` uses config.settings_test unless the caller passed an
    # explicit --settings. That module inherits from config.settings and only
    # overrides what makes the suite slow or dependent on external services.
    running_tests = 'test' in sys.argv[1:2]
    explicit_settings = any(arg.startswith('--settings') for arg in sys.argv)
    if running_tests and not explicit_settings:
        os.environ['DJANGO_SETTINGS_MODULE'] = 'config.settings_test'
    else:
        os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Couldn't import Django. Are you sure it's installed and "
            "available on your PYTHONPATH environment variable? Did you "
            "forget to activate a virtual environment?"
        ) from exc
    execute_from_command_line(sys.argv)


if __name__ == '__main__':
    main()
