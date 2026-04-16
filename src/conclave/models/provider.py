"""AI provider data models."""

from __future__ import annotations

from typing import Optional

from pydantic import BaseModel


class CompletionResult(BaseModel):
    success: bool
    content: Optional[str] = None
    tokens_used: Optional[dict] = None
    error: Optional[str] = None
