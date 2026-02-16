"""Tests for providers/."""

from __future__ import annotations

import pytest

from conclave.models.provider import CompletionResult
from conclave.providers.base import BaseProvider, get_ai_provider


class TestGetAIProvider:
    def test_anthropic_provider(self):
        config = {"ai": {"provider": "anthropic", "anthropic": {"api_key": "test"}}}
        provider = get_ai_provider(config)
        assert provider.name == "anthropic"

    def test_openai_provider(self):
        config = {"ai": {"provider": "openai", "openai": {"api_key": "test"}}}
        provider = get_ai_provider(config)
        assert provider.name == "openai"

    def test_azure_provider(self):
        config = {
            "ai": {
                "provider": "azure-openai",
                "azure-openai": {"api_key": "test", "endpoint": "https://x.openai.azure.com"},
            }
        }
        provider = get_ai_provider(config)
        assert provider.name == "azure-openai"

    def test_ollama_provider(self):
        config = {"ai": {"provider": "ollama", "ollama": {}}}
        provider = get_ai_provider(config)
        assert provider.name == "ollama"

    def test_invalid_provider_raises(self):
        config = {"ai": {"provider": "invalid"}}
        with pytest.raises(ValueError, match="Unknown"):
            get_ai_provider(config)

    def test_provider_override(self):
        config = {"ai": {"provider": "anthropic", "openai": {"api_key": "test"}}}
        provider = get_ai_provider(config, provider_override="openai")
        assert provider.name == "openai"


class TestBaseProviderRetry:
    @pytest.mark.asyncio
    async def test_retry_on_failure(self):
        """Test that complete_with_retry retries on retryable failure."""
        provider = BaseProvider(
            provider_config={},
            common_config={"retry_attempts": 3, "retry_delay_seconds": 0},
        )

        call_count = 0

        async def mock_complete(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count < 3:
                return CompletionResult(success=False, error="500 Internal Server Error")
            return CompletionResult(success=True, content="ok")

        provider.complete = mock_complete

        result = await provider.complete_with_retry(
            shared_context=None,
            system_prompt="test",
            user_prompt="test",
        )
        assert result.success
        assert call_count == 3

    @pytest.mark.asyncio
    async def test_gives_up_after_max_retries(self):
        """Test that retries stop after max attempts for non-retryable errors."""
        provider = BaseProvider(
            provider_config={},
            common_config={"retry_attempts": 2, "retry_delay_seconds": 0},
        )

        async def mock_complete(*args, **kwargs):
            return CompletionResult(success=False, error="401 Unauthorized")

        provider.complete = mock_complete

        result = await provider.complete_with_retry(
            shared_context=None,
            system_prompt="test",
            user_prompt="test",
        )
        assert not result.success

    @pytest.mark.asyncio
    async def test_success_on_first_try(self):
        """Test that a successful first attempt returns immediately."""
        provider = BaseProvider(
            provider_config={},
            common_config={"retry_attempts": 3, "retry_delay_seconds": 0},
        )

        async def mock_complete(*args, **kwargs):
            return CompletionResult(success=True, content="great")

        provider.complete = mock_complete

        result = await provider.complete_with_retry(
            shared_context=None,
            system_prompt="test",
            user_prompt="test",
        )
        assert result.success
        assert result.content == "great"
