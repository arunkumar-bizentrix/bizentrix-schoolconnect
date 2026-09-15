"""
Serving uploaded files only to people allowed to see the record they belong to.

Attachments used to be plain /media/ links: anyone holding the URL - a parent
forwarding it, a guessed filename - could open another class's notice. Views
now fetch the record through their normal permission checks and stream the
file from here, so the check runs on every download.
"""

import mimetypes
import os

from django.http import FileResponse, Http404


def serve_private_file(field_file, *, as_attachment=False):
    if not field_file:
        raise Http404("This record has no attachment.")
    try:
        handle = field_file.open('rb')
    except (FileNotFoundError, OSError):
        raise Http404("The attachment file is missing.")

    filename = os.path.basename(field_file.name)
    content_type, _ = mimetypes.guess_type(filename)
    response = FileResponse(
        handle,
        as_attachment=as_attachment,
        filename=filename,
        content_type=content_type or 'application/octet-stream',
    )
    # Never let a shared proxy keep a copy of a child's document.
    response['Cache-Control'] = 'private, no-store'
    response['X-Content-Type-Options'] = 'nosniff'
    return response


def private_file_url(request, route):
    """Absolute URL of the permission-checked download route."""
    return request.build_absolute_uri(route) if request else route
