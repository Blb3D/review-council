"""Anthropic Claude API provider with prompt caching.

Port of cli/lib/providers/anthropic.ps1.
"""

from __future__ import annotations

import os
from typing import Optional

import httpx

from ..models.provider import CompletionResult
from .base import BaseProvider


class AnthropicProvider(BaseProvider):
    name = "anthropic"
    API_URL = "https://api.anthropic.com/v1/messages"

    def _get_api_key(self) -> Optional[str]:
        env_var = self.config.get("api_key_env", "ANTHROPIC_API_KEY")
        return os.environ.get(env_var)

    def _resolve_model(self, tier: str) -> str:
        if tier == "lite" and self.config.get("lite_model"):
            return self.config["lite_model"]
        return self.config.get("model", "claude-sonnet-4-5-20250929")

    async def complete(
        self,
        shared_context: Optional[str],
        system_prompt: str,
        user_prompt: str,
        tier: str = "primary",
        max_tokens: int = 0,
    ) -> CompletionResult:
        api_key = self._get_api_key()
        if not api_key:
            env_var = self.config.get("api_key_env", "ANTHROPIC_API_KEY")
            return CompletionResult(
                success=False,
                error=f"API key not found in environment variable: {env_var}",
            )

        model = self._resolve_model(tier)
        max_tok = max_tokens or self.config.get("max_tokens", 16000)
        temperature = self.common.get("temperature", 0.3)
        timeout = self.common.get("timeout_seconds", 300)

        # Build system with cache_control when SharedContext provided
        if shared_context:
            system_content: list | str = [
                {
                    "type": "text",
                    "text": shared_context,
                    "cache_control": {"type": "ephemeral"},
                },
                {"type": "text", "text": system_prompt},
            ]
        else:
            system_content = system_prompt

        body = {
            "model": model,
            "max_tokens": max_tok,
            "temperature": temperature,
            "system": system_content,
            "messages": [{"role": "user", "content": user_prompt}],
        }

        headers = {
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        }

        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.post(self.API_URL, json=body, headers=headers)
                response.raise_for_status()
                data = response.json()

            content = None
            for block in data.get("content", []):
                if block.get("type") == "text":
                    content = block.get("text")
                    break

            usage = data.get("usage", {})
            tokens = {
                "input": usage.get("input_tokens", 0),
                "output": usage.get("output_tokens", 0),
                "cacheRead": usage.get("cache_read_input_tokens", 0),
                "cacheWrite": usage.get("cache_creation_input_tokens", 0),
            }

            return CompletionResult(
                success=True, content=content, tokens_used=tokens
            )
        except httpx.HTTPStatusError as e:
            error_body = ""
            try:
                error_body = e.response.text
            except Exception:
                pass
            return CompletionResult(
                success=False,
                error=f"{e.response.status_code} | {error_body}",
            )
        except Exception as e:
            return CompletionResult(success=False, error=str(e))
