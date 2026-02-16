"""Tests for core/licensing.py."""

from __future__ import annotations

import os
from unittest.mock import patch

from conclave.core.licensing import (
    Tier,
    check_feature,
    get_allowed_agents,
    get_current_tier,
)


class TestGetCurrentTier:
    def test_default_free(self, tmp_path):
        with patch.dict(os.environ, {}, clear=True):
            with patch("conclave.core.licensing.Path.home", return_value=tmp_path):
                assert get_current_tier() == Tier.FREE

    def test_tier_from_env_var(self):
        with patch.dict(os.environ, {"CONCLAVE_TIER": "pro"}, clear=True):
            assert get_current_tier() == Tier.PRO

    def test_pro_from_license_key(self):
        with patch.dict(os.environ, {"CONCLAVE_LICENSE_KEY": "ccl-pro-test-key"}, clear=True):
            assert get_current_tier() == Tier.PRO

    def test_compliance_from_license_key(self):
        with patch.dict(os.environ, {"CONCLAVE_LICENSE_KEY": "ccl-comp-test-key"}, clear=True):
            assert get_current_tier() == Tier.COMPLIANCE

    def test_enterprise_from_license_key(self):
        with patch.dict(os.environ, {"CONCLAVE_LICENSE_KEY": "ccl-ent-test-key"}, clear=True):
            assert get_current_tier() == Tier.ENTERPRISE

    def test_invalid_key_defaults_free(self):
        with patch.dict(os.environ, {"CONCLAVE_LICENSE_KEY": "invalid-key"}, clear=True):
            assert get_current_tier() == Tier.FREE


class TestCheckFeature:
    def test_free_no_caching(self):
        with patch("conclave.core.licensing.get_current_tier", return_value=Tier.FREE):
            assert check_feature("prompt_caching") is False

    def test_pro_has_caching(self):
        with patch("conclave.core.licensing.get_current_tier", return_value=Tier.PRO):
            assert check_feature("prompt_caching") is True

    def test_free_no_compliance(self):
        with patch("conclave.core.licensing.get_current_tier", return_value=Tier.FREE):
            assert check_feature("compliance_mapping") is False

    def test_compliance_has_mapping(self):
        with patch("conclave.core.licensing.get_current_tier", return_value=Tier.COMPLIANCE):
            assert check_feature("compliance_mapping") is True

    def test_unknown_feature_false(self):
        with patch("conclave.core.licensing.get_current_tier", return_value=Tier.ENTERPRISE):
            assert check_feature("nonexistent_feature") is False


class TestGetAllowedAgents:
    def test_free_two_agents(self):
        with patch("conclave.core.licensing.get_current_tier", return_value=Tier.FREE):
            agents = get_allowed_agents()
            assert set(agents) == {"guardian", "sentinel"}

    def test_pro_all_agents(self):
        with patch("conclave.core.licensing.get_current_tier", return_value=Tier.PRO):
            agents = get_allowed_agents()
            assert len(agents) == 6
            assert "guardian" in agents
            assert "architect" in agents
            assert "herald" in agents
