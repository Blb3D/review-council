"""Standards YAML loading.

Port of Get-AvailableStandards / Get-StandardById from mapping-engine.ps1.
"""

from __future__ import annotations

from pathlib import Path
from typing import Optional

import yaml


def get_available_standards(standards_dir: Path) -> list[dict]:
    """Get list of all available compliance standards."""
    standards: list[dict] = []

    if not standards_dir.exists():
        return standards

    for yaml_file in standards_dir.rglob("*.yaml"):
        if yaml_file.name == ".gitkeep":
            continue
        try:
            content = yaml.safe_load(yaml_file.read_text(encoding="utf-8"))
            if content and content.get("id"):
                standards.append({
                    "id": content["id"],
                    "name": content.get("name", ""),
                    "domain": content.get("domain", ""),
                    "version": content.get("version", ""),
                    "description": content.get("description", ""),
                    "path": str(yaml_file),
                })
        except Exception:
            pass

    return standards


def get_standard_by_id(standard_id: str, standards_dir: Path) -> Optional[dict]:
    """Load a specific compliance standard by ID."""
    standards = get_available_standards(standards_dir)
    match = next((s for s in standards if s["id"] == standard_id), None)

    if not match:
        return None

    return yaml.safe_load(Path(match["path"]).read_text(encoding="utf-8"))
