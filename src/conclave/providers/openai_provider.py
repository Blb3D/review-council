"""OpenAI API provider.

Port of cli/lib/providers/openai.ps1.
"""

from __future__ import annotations

import os
from typing import Optional

import httpx

from ..models.provider import CompletionResult
from .base import BaseProvider


class OpenAIProvider(BaseProvider):
    name = "openai"
    API_URL = "https://api.openai.com/v1/chat/completions"

    def _get_api_key(self) -> Optional[str]:
        env_var = self.config.get("api_key_env", "OPENAI_API_KEY")
        return os.environ.get(env_var)

    def _resolve_model(self, tier: str) -> str:
        if tier == "lite" and self.config.get("lite_model"):
            return self.config["lite_model"]
        return self.config.get("model", "gpt-4o")

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
            env_var = self.config.get("api_key_env", "OPENAI_API_KEY")
            return CompletionResult(
                success=False,
                error=f"API key not found in environment variable: {env_var}",
            )

        model = self._resolve_model(tier)
        max_tok = max_tokens or self.config.get("max_tokens", 16000)
        temperature = self.common.get("temperature", 0.3)
        timeout = self.common.get("timeout_seconds", 300)

        full_system = (
            f"{shared_context}\n\n{system_prompt}" if shared_context else system_prompt
        )

        body = {
            "model": model,
            "max_tokens": max_tok,
            "temperature": temperature,
            "messages": [
                {"role": "system", "content": full_system},
                {"role": "user", "content": user_prompt},
            ],
        }

        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }

        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.post(self.API_URL, json=body, headers=headers)
                response.raise_for_status()
                data = response.json()

            content = data["choices"][0]["message"]["content"]
            usage = data.get("usage", {})
            tokens = {
                "input": usage.get("prompt_tokens", 0),
                "output": usage.get("completion_tokens", 0),
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
