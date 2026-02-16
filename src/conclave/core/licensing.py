"""Licensing and feature gating.

Determines the current tier and controls access to features.
"""

from __future__ import annotations

import json
import os
from enum import Enum
from pathlib import Path


class Tier(str, Enum):
    FREE = "free"
    PRO = "pro"
    COMPLIANCE = "compliance"
    ENTERPRISE = "enterprise"


FEATURE_MATRIX: dict[str, dict[Tier, object]] = {
    "max_agents": {
        Tier.FREE: 2,
        Tier.PRO: 6,
        Tier.COMPLIANCE: 6,
        Tier.ENTERPRISE: 6,
    },
    "allowed_agents": {
        Tier.FREE: {"guardian", "sentinel"},
        Tier.PRO: {"guardian", "sentinel", "architect", "navigator", "herald", "operator"},
        Tier.COMPLIANCE: {"guardian", "sentinel", "architect", "navigator", "herald", "operator"},
        Tier.ENTERPRISE: {"guardian", "sentinel", "architect", "navigator", "herald", "operator"},
    },
    "prompt_caching": {
        Tier.FREE: False,
        Tier.PRO: True,
        Tier.COMPLIANCE: True,
        Tier.ENTERPRISE: True,
    },
    "diff_scoping": {
        Tier.FREE: False,
        Tier.PRO: True,
        Tier.COMPLIANCE: True,
        Tier.ENTERPRISE: True,
    },
    "junit_output": {
        Tier.FREE: False,
        Tier.PRO: True,
        Tier.COMPLIANCE: True,
        Tier.ENTERPRISE: True,
    },
    "compliance_mapping": {
        Tier.FREE: False,
        Tier.PRO: False,
        Tier.COMPLIANCE: True,
        Tier.ENTERPRISE: True,
    },
    "six_agents": {
        Tier.FREE: False,
        Tier.PRO: True,
        Tier.COMPLIANCE: True,
        Tier.ENTERPRISE: True,
    },
}


def get_current_tier() -> Tier:
    """Determine current licensing tier."""
    # Env var override
    env_tier = os.environ.get("CONCLAVE_TIER", "").lower()
    if env_tier in {t.value for t in Tier}:
        return Tier(env_tier)

    # License key from env or file
    license_key = os.environ.get("CONCLAVE_LICENSE_KEY", "")
    if not license_key:
        license_file = Path.home() / ".conclave" / "license.json"
        if license_file.exists():
            try:
                data = json.loads(license_file.read_text(encoding="utf-8"))
                license_key = data.get("key", "")
            except Exception:
                pass

    if not license_key:
        return Tier.FREE

    return _validate_license(license_key)


def _validate_license(key: str) -> Tier:
    """Validate a license key. Simple prefix-based for now."""
    # Phase 1: prefix-based validation
    if key.startswith("ccl-ent-"):
        return Tier.ENTERPRISE
    if key.startswith("ccl-comp-"):
        return Tier.COMPLIANCE
    if key.startswith("ccl-pro-"):
        return Tier.PRO
    return Tier.FREE


def check_feature(feature: str) -> bool:
    """Check if a feature is available in the current tier."""
    tier = get_current_tier()
    matrix = FEATURE_MATRIX.get(feature, {})
    return bool(matrix.get(tier, False))


def get_allowed_agents() -> set[str]:
    """Get the set of agents allowed in the current tier."""
    tier = get_current_tier()
    return set(FEATURE_MATRIX["allowed_agents"].get(tier, {"guardian", "sentinel"}))
