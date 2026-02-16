"""3-layer configuration system for Code Conclave.

Loads and merges configuration from:
1. Default settings (built-in)
2. Project config (.code-conclave/config.yaml)
3. CLI parameters (override)
"""

from __future__ import annotations

import copy
from pathlib import Path
from typing import Optional

import yaml

DEFAULT_CONFIG: dict = {
    "project": {
        "name": "",
        "version": "1.0.0",
        "industry": "general",
    },
    "standards": {
        "required": [],
        "default": [],
        "available": [],
        "profiles": {},
    },
    "agents": {
        "timeout": 40,
        "parallel": False,
        "sentinel": {"enabled": True, "coverage_target": 80, "tier": "primary"},
        "guardian": {"enabled": True, "scan_dependencies": True, "tier": "primary"},
        "architect": {"enabled": True, "tier": "primary"},
        "navigator": {"enabled": True, "tier": "primary"},
        "herald": {"enabled": True, "tier": "primary"},
        "operator": {"enabled": True, "tier": "primary"},
    },
    "output": {
        "format": "markdown",
        "include_evidence": True,
        "include_remediation": True,
    },
    "ci": {
        "exit_codes": {"ship": 0, "conditional": 2, "hold": 1},
    },
    "ai": {
        "provider": "anthropic",
        "temperature": 0.3,
        "timeout_seconds": 300,
        "retry_attempts": 3,
        "retry_delay_seconds": 5,
        "max_context_kb": 100,
        "anthropic": {
            "model": "claude-sonnet-4-5-20250929",
            "lite_model": "claude-haiku-4-5-20251001",
            "api_key_env": "ANTHROPIC_API_KEY",
            "max_tokens": 16000,
        },
        "azure-openai": {
            "endpoint": "",
            "deployment": "gpt-4o",
            "lite_deployment": "",
            "api_version": "2024-10-01-preview",
            "api_key_env": "AZURE_OPENAI_KEY",
            "max_tokens": 16000,
        },
        "openai": {
            "model": "gpt-4o",
            "lite_model": "gpt-4o-mini",
            "api_key_env": "OPENAI_API_KEY",
            "max_tokens": 16000,
        },
        "ollama": {
            "endpoint": "http://localhost:11434",
            "model": "llama3.1:70b",
            "max_tokens": 8000,
        },
    },
}


def deep_merge(base: dict, override: dict) -> dict:
    """Deep merge two dicts. Arrays are replaced, not merged."""
    result = {}
    for key in base:
        result[key] = base[key]
    for key, value in override.items():
        base_value = result.get(key)
        if isinstance(base_value, dict) and isinstance(value, dict):
            result[key] = deep_merge(base_value, value)
        else:
            result[key] = value
    return result


def load_project_config(project_path: Path) -> dict:
    """Load project configuration from .code-conclave/config.yaml."""
    config_path = project_path / ".code-conclave" / "config.yaml"
    if not config_path.exists():
        return {}
    try:
        content = config_path.read_text(encoding="utf-8-sig")  # utf-8-sig strips BOM
        return yaml.safe_load(content) or {}
    except Exception:
        return {}


def get_effective_standards(
    config: dict,
    profile: Optional[str] = None,
    add_standards: Optional[list[str]] = None,
    skip_standards: Optional[list[str]] = None,
) -> list[str]:
    """Calculate the effective list of standards to apply."""
    standards_config = config.get("standards") or {
        "required": [],
        "default": [],
        "available": [],
    }
    skip = set(skip_standards or [])

    effective: list[str] = []

    # Required standards always included
    for std in standards_config.get("required") or []:
        effective.append(std)

    # Profile or default standards
    if profile and profile != "default" and standards_config.get("profiles"):
        profile_config = standards_config["profiles"].get(profile)
        if profile_config and profile_config.get("standards"):
            effective.extend(profile_config["standards"])
    else:
        for std in standards_config.get("default") or []:
            if std not in skip:
                effective.append(std)

    # Explicitly added standards
    if add_standards:
        for std in add_standards:
            if std and std not in effective:
                effective.append(std)

    # Deduplicate preserving order
    seen: set[str] = set()
    result: list[str] = []
    for std in effective:
        if std and std not in seen:
            seen.add(std)
            result.append(std)

    return result


def get_effective_config(
    project_path: Path,
    profile: Optional[str] = None,
    add_standards: Optional[list[str]] = None,
    skip_standards: Optional[list[str]] = None,
    cli_overrides: Optional[dict] = None,
) -> dict:
    """Get the fully resolved configuration for a review."""
    config = copy.deepcopy(DEFAULT_CONFIG)

    project_config = load_project_config(project_path)
    if project_config:
        config = deep_merge(config, project_config)

    if cli_overrides:
        config = deep_merge(config, cli_overrides)

    config["_effective_standards"] = get_effective_standards(
        config, profile, add_standards, skip_standards
    )
    config["_project_path"] = str(project_path)

    return config
