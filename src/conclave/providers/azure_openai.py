"""Azure OpenAI API provider.

Port of cli/lib/providers/azure-openai.ps1.
"""

from __future__ import annotations

import os
from typing import Optional

import httpx

from ..models.provider import CompletionResult
from .base import BaseProvider


class AzureOpenAIProvider(BaseProvider):
    name = "azure-openai"

    def _get_api_key(self) -> Optional[str]:
        env_var = self.config.get("api_key_env", "AZURE_OPENAI_KEY")
        return os.environ.get(env_var)

    def _resolve_deployment(self, tier: str) -> str:
        if tier == "lite" and self.config.get("lite_deployment"):
            return self.config["lite_deployment"]
        return self.config.get("deployment", "gpt-4o")

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
            env_var = self.config.get("api_key_env", "AZURE_OPENAI_KEY")
            return CompletionResult(
                success=False,
                error=f"API key not found in environment variable: {env_var}",
            )

        endpoint = self.config.get("endpoint", "")
        if not endpoint:
            return CompletionResult(
                success=False, error="Azure OpenAI endpoint not configured"
            )

        deployment = self._resolve_deployment(tier)
        api_version = self.config.get("api_version", "2024-10-01-preview")
        max_tok = max_tokens or self.config.get("max_tokens", 16000)
        temperature = self.common.get("temperature", 0.3)
        timeout = self.common.get("timeout_seconds", 300)

        url = (
            f"{endpoint.rstrip('/')}/openai/deployments/{deployment}"
            f"/chat/completions?api-version={api_version}"
        )

        full_system = (
            f"{shared_context}\n\n{system_prompt}" if shared_context else system_prompt
        )

        body = {
            "max_tokens": max_tok,
            "temperature": temperature,
            "messages": [
                {"role": "system", "content": full_system},
                {"role": "user", "content": user_prompt},
            ],
        }

        headers = {
            "api-key": api_key,
            "Content-Type": "application/json",
        }

        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.post(url, json=body, headers=headers)
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
