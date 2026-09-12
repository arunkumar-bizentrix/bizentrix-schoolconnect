"""
School context resolution.

SchoolConnect serves ONE school. Every domain record still carries a
``school`` foreign key for data integrity and for safe historical queries,
but the application layer never asks the client which school it is talking
about - the school is derived from the authenticated user, falling back to
the single School row this deployment was set up with.

This module is the only place that resolution happens. Nothing else in the
codebase should call ``School.objects.first()``.
"""

from .models import School


def get_default_school():
    """
    The school this deployment serves.

    Ordering follows School.Meta.ordering (by name), so the result is stable
    for a given database. Returns None only when no School row exists yet,
    which means the installation has not been set up.
    """
    return School.objects.first()


def get_school_for(user):
    """
    Resolve the school context for a request user.

    Uses the user's own association when present, otherwise the deployment's
    school. Read-only: callers that need the association persisted (login,
    registration, first write) do that explicitly via ``attach_user_to_school``.
    """
    if user is None:
        return get_default_school()
    return getattr(user, 'school', None) or get_default_school()


def get_school_id_for(user):
    """
    The id of :func:`get_school_for`, without fetching the School row when the
    user already carries the foreign key. Returns None if nothing resolves.
    """
    if user is not None and getattr(user, 'school_id', None):
        return user.school_id
    school = get_default_school()
    return school.id if school else None


def attach_user_to_school(user):
    """
    Persist the deployment's school onto a user that has none, and return the
    resolved school.

    Called at authentication time and before a user's first write - never from
    a permission class, which must not mutate the database.
    """
    school = get_school_for(user)
    if school and not user.school_id and not user.is_superuser:
        user.school = school
        user.save(update_fields=['school'])
    return school
