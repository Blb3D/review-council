"""Error message sanitization to prevent credential leakage."""

from __future__ import annotations

import os
import re


def sanitize_error(message: str) -> str:
    """Sanitize error messages to prevent API key and path leakage."""
    if not message:
        return message

    sanitized = message
    # Redact API key patterns
    sanitized = re.sub(r"sk-ant-[a-zA-Z0-9_-]+", "[REDACTED_KEY]", sanitized)
    sanitized = re.sub(r"sk-[a-zA-Z0-9_-]{20,}", "[REDACTED_KEY]", sanitized)
    sanitized = re.sub(r"Bearer\s+\S+", "Bearer [REDACTED]", sanitized)
    sanitized = re.sub(r"api-key:\s*\S+", "api-key: [REDACTED]", sanitized)
    sanitized = re.sub(r"x-api-key:\s*\S+", "x-api-key: [REDACTED]", sanitized)
    sanitized = re.sub(r"Authorization:\s*\S+", "Authorization: [REDACTED]", sanitized)

    # Redact user home paths
    home = os.environ.get("USERPROFILE") or os.environ.get("HOME") or ""
    if home:
        sanitized = sanitized.replace(home, "[USER_HOME]")

    return sanitized
