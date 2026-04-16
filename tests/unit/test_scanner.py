"""Tests for core/scanner.py."""

from __future__ import annotations

from pathlib import Path

from conclave.core.scanner import get_file_tier, get_project_file_tree, get_source_files_content


class TestGetFileTier:
    """get_file_tier(file_path: Path, project_path: Path) -> int"""

    def _tier(self, rel_path: str, tmp_path: Path) -> int:
        """Helper: get tier for a relative path within a project."""
        return get_file_tier(tmp_path / rel_path, tmp_path)

    def test_entry_point_tier1(self, tmp_path: Path):
        assert self._tier("src/main.py", tmp_path) == 1

    def test_index_js_root_tier1(self, tmp_path: Path):
        assert self._tier("index.js", tmp_path) == 1

    def test_index_js_deep_not_tier1(self, tmp_path: Path):
        # index.js at depth > 2 should NOT be tier 1
        assert self._tier("src/components/deep/index.js", tmp_path) != 1

    def test_business_logic_tier2(self, tmp_path: Path):
        assert self._tier("src/services/service.py", tmp_path) == 2

    def test_model_tier3(self, tmp_path: Path):
        assert self._tier("src/models/user.py", tmp_path) == 3

    def test_test_file_tier4(self, tmp_path: Path):
        assert self._tier("tests/test_main.py", tmp_path) == 4

    def test_spec_file_tier4(self, tmp_path: Path):
        assert self._tier("src/app.spec.js", tmp_path) == 4

    def test_doc_file_tier5(self, tmp_path: Path):
        assert self._tier("docs/README.md", tmp_path) == 5

    def test_frontend_tier6(self, tmp_path: Path):
        assert self._tier("src/components/App.tsx", tmp_path) == 6

    def test_everything_else_tier7(self, tmp_path: Path):
        assert self._tier("data/data.csv", tmp_path) == 7

    def test_settings_py_in_api_not_tier1(self, tmp_path: Path):
        # settings.py inside an api/ directory should not be tier 1
        tier = self._tier("src/api/settings.py", tmp_path)
        assert tier != 1

    def test_dockerfile_tier1(self, tmp_path: Path):
        assert self._tier("Dockerfile", tmp_path) == 1

    def test_init_py_tier7(self, tmp_path: Path):
        tier = self._tier("src/pkg/__init__.py", tmp_path)
        assert tier == 7  # Not in any special dir


class TestGetProjectFileTree:
    def test_returns_string(self, tmp_project: Path):
        tree = get_project_file_tree(tmp_project)
        assert isinstance(tree, str)
        assert len(tree) > 0

    def test_includes_files(self, tmp_project: Path):
        tree = get_project_file_tree(tmp_project)
        assert "main.py" in tree

    def test_excludes_git_dir(self, tmp_project: Path):
        (tmp_project / ".git").mkdir()
        (tmp_project / ".git" / "config").write_text("x", encoding="utf-8")
        tree = get_project_file_tree(tmp_project)
        # .git dir should be excluded from tree
        lines = tree.split("\n")
        assert not any(".git" in line and "config" in line for line in lines)


class TestGetSourceFilesContent:
    def test_returns_content(self, tmp_project: Path):
        # Create files large enough to pass min_file_bytes (50)
        (tmp_project / "src" / "main.py").write_text(
            "# Main module\n" * 10, encoding="utf-8"
        )
        result = get_source_files_content(tmp_project, max_size_kb=100)
        assert result.content != ""
        assert result.file_count > 0

    def test_respects_budget(self, tmp_project: Path):
        # Create a large file
        large = tmp_project / "src" / "big.py"
        large.write_text("x = 1\n" * 40_000, encoding="utf-8")  # ~240KB
        result = get_source_files_content(tmp_project, max_size_kb=50)
        assert result.total_size_kb <= 55  # Allow some overhead

    def test_tier_ordering(self, tmp_project: Path):
        """Higher-tier files should be included before lower ones."""
        (tmp_project / "src" / "main.py").write_text("# entry point\n" * 10, encoding="utf-8")
        tests_dir = tmp_project / "tests"
        tests_dir.mkdir(exist_ok=True)
        (tests_dir / "test_main.py").write_text("# test\n" * 10, encoding="utf-8")

        result = get_source_files_content(tmp_project, max_size_kb=100)
        # main.py (tier 1) should appear before test_main.py (tier 4)
        if "main.py" in result.content and "test_main.py" in result.content:
            assert result.content.index("main.py") < result.content.index("test_main.py")
