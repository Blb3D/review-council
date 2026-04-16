"""Ollama local inference provider.

Port of cli/lib/providers/ollama.ps1.
"""

from __future__ import annotations

from typing import Optional

import httpx

from ..models.provider import CompletionResult
from .base import BaseProvider


class OllamaProvider(BaseProvider):
    name = "ollama"

    async def complete(
        self,
        shared_context: Optional[str],
        system_prompt: str,
        user_prompt: str,
        tier: str = "primary",
        max_tokens: int = 0,
    ) -> CompletionResult:
        endpoint = self.config.get("endpoint", "http://localhost:11434")
        model = self.config.get("model", "llama3.1:70b")
        timeout = self.common.get("timeout_seconds", 300)

        full_system = (
            f"{shared_context}\n\n{system_prompt}" if shared_context else system_prompt
        )

        body = {
            "model": model,
            "system": full_system,
            "prompt": user_prompt,
            "stream": False,
        }

        try:
            url = f"{endpoint.rstrip('/')}/api/generate"
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.post(url, json=body)
                response.raise_for_status()
                data = response.json()

            return CompletionResult(
                success=True,
                content=data.get("response", ""),
                tokens_used=None,
            )
        except Exception as e:
            return CompletionResult(success=False, error=str(e))
