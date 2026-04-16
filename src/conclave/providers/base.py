"""AI provider abstraction with retry logic.

Port of cli/lib/ai-engine.ps1.
"""

from __future__ import annotations

import asyncio
import math
from typing import Optional, Protocol, runtime_checkable

from ..models.provider import CompletionResult
from ..utils.sanitize import sanitize_error


@runtime_checkable
class AIProvider(Protocol):
    """Protocol that all AI providers must implement."""

    name: str

    async def complete(
        self,
        shared_context: Optional[str],
        system_prompt: str,
        user_prompt: str,
        tier: str = "primary",
        max_tokens: int = 0,
    ) -> CompletionResult: ...


class BaseProvider:
    """Base class with shared retry logic and config handling."""

    name: str = "base"

    def __init__(self, provider_config: dict, common_config: dict):
        self.config = provider_config
        self.common = common_config
        self.max_attempts = common_config.get("retry_attempts", 3)
        self.retry_delay = common_config.get("retry_delay_seconds", 5)

    async def complete(
        self,
        shared_context: Optional[str],
        system_prompt: str,
        user_prompt: str,
        tier: str = "primary",
        max_tokens: int = 0,
    ) -> CompletionResult:
        raise NotImplementedError

    async def complete_with_retry(
        self,
        shared_context: Optional[str],
        system_prompt: str,
        user_prompt: str,
        tier: str = "primary",
        max_tokens: int = 0,
    ) -> CompletionResult:
        """Wrap complete() with retry logic including rate-limit handling."""
        rate_limit_max = max(self.max_attempts, 5)
        last_result: Optional[CompletionResult] = None

        for attempt in range(1, rate_limit_max + 1):
            result = await self.complete(
                shared_context, system_prompt, user_prompt, tier, max_tokens
            )
            last_result = result

            if result.success:
                return result

            error_msg = result.error or ""
            is_rate_limit = "429" in error_msg
            is_retryable = (
                is_rate_limit
                or any(
                    code in error_msg
                    for code in ("500", "502", "503", "504", "timeout", "timed out")
                )
            ) and not any(
                code in error_msg
                for code in ("400", "401", "403", "404")
            )

            effective_max = rate_limit_max if is_rate_limit else self.max_attempts
            if not is_retryable or attempt >= effective_max:
                result.error = sanitize_error(error_msg)
                return result

            # Rate limits: 30s base. Others: standard backoff.
            base_delay = 30 if is_rate_limit else self.retry_delay
            wait_time = base_delay * min(attempt, 3)
            await asyncio.sleep(wait_time)

        return last_result or CompletionResult(success=False, error="Max retries exceeded")


def get_ai_provider(
    config: dict,
    provider_override: Optional[str] = None,
    model_override: Optional[str] = None,
    endpoint_override: Optional[str] = None,
) -> BaseProvider:
    """Factory function to create the configured AI provider."""
    ai_config = config.get("ai", {})
    provider_name = provider_override or ai_config.get("provider", "anthropic")

    # Get provider-specific config
    provider_config = dict(ai_config.get(provider_name, {}))

    # Apply CLI overrides
    if model_override:
        if provider_name == "azure-openai":
            provider_config["deployment"] = model_override
        else:
            provider_config["model"] = model_override
    if endpoint_override:
        provider_config["endpoint"] = endpoint_override

    # Build common config (ai section minus provider sub-configs)
    common_config = {
        k: v
        for k, v in ai_config.items()
        if k not in ("anthropic", "azure-openai", "openai", "ollama")
    }

    # Import and instantiate provider
    if provider_name == "anthropic":
        from .anthropic import AnthropicProvider
        return AnthropicProvider(provider_config, common_config)
    elif provider_name == "azure-openai":
        from .azure_openai import AzureOpenAIProvider
        return AzureOpenAIProvider(provider_config, common_config)
    elif provider_name == "openai":
        from .openai_provider import OpenAIProvider
        return OpenAIProvider(provider_config, common_config)
    elif provider_name == "ollama":
        from .ollama import OllamaProvider
        return OllamaProvider(provider_config, common_config)
    else:
        raise ValueError(f"Unknown AI provider: {provider_name}")
