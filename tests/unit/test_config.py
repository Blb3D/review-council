"""Tests for core/config.py."""

from __future__ import annotations

from pathlib import Path

from conclave.core.config import deep_merge, get_effective_config, get_effective_standards, load_project_config


class TestDeepMerge:
    def test_simple_merge(self):
        base = {"a": 1, "b": 2}
        override = {"b": 3, "c": 4}
        result = deep_merge(base, override)
        assert result == {"a": 1, "b": 3, "c": 4}

    def test_nested_merge(self):
        base = {"ai": {"provider": "anthropic", "timeout": 30}}
        override = {"ai": {"provider": "openai"}}
        result = deep_merge(base, override)
        assert result["ai"]["provider"] == "openai"
        assert result["ai"]["timeout"] == 30

    def test_arrays_replaced(self):
        base = {"agents": ["guardian", "sentinel"]}
        override = {"agents": ["architect"]}
        result = deep_merge(base, override)
        assert result["agents"] == ["architect"]

    def test_empty_override(self):
        base = {"a": 1}
        result = deep_merge(base, {})
        assert result == {"a": 1}

    def test_base_not_mutated(self):
        base = {"a": {"b": 1}}
        override = {"a": {"b": 2}}
        deep_merge(base, override)
        assert base["a"]["b"] == 1

    def test_deeply_nested(self):
        base = {"l1": {"l2": {"l3": "base"}}}
        override = {"l1": {"l2": {"l3": "override", "new": True}}}
        result = deep_merge(base, override)
        assert result["l1"]["l2"]["l3"] == "override"
        assert result["l1"]["l2"]["new"] is True


class TestLoadProjectConfig:
    def test_loads_yaml(self, initialized_project: Path):
        config = load_project_config(initialized_project)
        assert config["project"]["name"] == "test-project"
        assert config["ai"]["provider"] == "anthropic"

    def test_missing_config_returns_empty(self, tmp_project: Path):
        config = load_project_config(tmp_project)
        assert config == {}

    def test_empty_config_returns_empty(self, tmp_path: Path):
        project = tmp_path / "proj"
        project.mkdir()
        cc = project / ".code-conclave"
        cc.mkdir()
        (cc / "config.yaml").write_text("", encoding="utf-8")
        config = load_project_config(project)
        assert config == {}


class TestGetEffectiveConfig:
    def test_defaults_applied(self, tmp_project: Path):
        config = get_effective_config(tmp_project)
        assert "ai" in config
        assert config["ai"]["provider"] == "anthropic"

    def test_project_overrides_defaults(self, initialized_project: Path):
        config = get_effective_config(initialized_project)
        assert config["project"]["name"] == "test-project"

    def test_cli_overrides_project(self, initialized_project: Path):
        config = get_effective_config(
            initialized_project,
            cli_overrides={"ai": {"provider": "openai"}},
        )
        assert config["ai"]["provider"] == "openai"


class TestGetEffectiveStandards:
    def test_empty_config(self):
        result = get_effective_standards({})
        assert isinstance(result, list)
