import os
from django.core.exceptions import ValidationError

ALLOWED_EXTENSIONS = {'.pdf', '.jpg', '.jpeg', '.png', '.webp'}
MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB


def validate_announcement_attachment(file):
    """
    Validates that the uploaded attachment is a supported document/image format
    and within safe file size limits.
    """
    ext = os.path.splitext(file.name)[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise ValidationError(
            f"Unsupported file format '{ext}'. Allowed formats are: {', '.join(sorted(ALLOWED_EXTENSIONS))}."
        )

    if file.size > MAX_FILE_SIZE_BYTES:
        max_mb = MAX_FILE_SIZE_BYTES / (1024 * 1024)
        raise ValidationError(
            f"File size exceeds the {max_mb:.0f} MB limit."
        )
