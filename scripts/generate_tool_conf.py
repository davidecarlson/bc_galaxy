#!/usr/bin/env python3
"""Generate a shared Galaxy tool_conf.xml from installed shed_tools content."""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class ToolEntry:
    owner: str
    repo: str
    revision: str
    xml_path: Path
    container_path: str
    tool_id: str
    tool_name: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Scan a shared Galaxy shed_tools tree and generate a curated "
            "tool_conf.xml."
        )
    )
    parser.add_argument(
        "--shed-tools-root",
        default="/gpfs/software/galaxy/shed_tools",
        help="Host path to the shared shed_tools root.",
    )
    parser.add_argument(
        "--container-prefix",
        default="/srv/galaxy/shed_tools",
        help="Container-visible prefix corresponding to --shed-tools-root.",
    )
    parser.add_argument(
        "--section-config",
        default="tool_sections.json",
        help="JSON file describing section mappings.",
    )
    parser.add_argument(
        "--output",
        default="-",
        help="Output file path, or '-' for stdout.",
    )
    parser.add_argument(
        "--skip-uncategorized",
        action="store_true",
        help="Do not emit a fallback section for tools not matched to a named section.",
    )
    return parser.parse_args()


def load_section_config(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def discover_tools(shed_tools_root: Path, container_prefix: str) -> list[ToolEntry]:
    repos_root = shed_tools_root / "toolshed.g2.bx.psu.edu" / "repos"
    tools: list[ToolEntry] = []

    for xml_path in sorted(repos_root.rglob("*.xml")):
        relative = xml_path.relative_to(repos_root)
        if len(relative.parts) < 4:
            continue
        owner, repo, revision = relative.parts[:3]

        try:
            root = ET.parse(xml_path).getroot()
        except ET.ParseError:
            continue

        if root.tag != "tool":
            continue

        tool_id = root.attrib.get("id", "")
        tool_name = root.attrib.get("name", xml_path.stem)
        container_path = (
            f"{container_prefix}/toolshed.g2.bx.psu.edu/repos/"
            f"{relative.as_posix()}"
        )
        tools.append(
            ToolEntry(
                owner=owner,
                repo=repo,
                revision=revision,
                xml_path=xml_path,
                container_path=container_path,
                tool_id=tool_id,
                tool_name=tool_name,
            )
        )

    return tools


def section_order(config: dict) -> list[dict]:
    return config.get("sections", [])


def tool_sort_key(tool: ToolEntry) -> tuple[str, str, str, str]:
    return (tool.repo, tool.tool_name.lower(), tool.tool_id, tool.container_path)


def render_section(section_id: str, name: str, tools: Iterable[ToolEntry]) -> list[str]:
    lines = [f'  <section id="{section_id}" name="{name}">']
    for tool in sorted(tools, key=tool_sort_key):
        lines.append(f'    <tool file="{tool.container_path}" />')
    lines.append("  </section>")
    return lines


def build_xml(tools: list[ToolEntry], config: dict, include_uncategorized: bool) -> str:
    tools_by_repo: dict[str, list[ToolEntry]] = {}
    for tool in tools:
        tools_by_repo.setdefault(tool.repo, []).append(tool)

    consumed_repos: set[str] = set()
    lines = ['<?xml version="1.0"?>', '<toolbox tool_path="/srv/galaxy/tools" monitor="true">']

    for section in section_order(config):
        repos = section.get("repos", [])
        section_tools = [
            tool
            for repo in repos
            for tool in tools_by_repo.get(repo, [])
        ]
        if not section_tools:
            continue

        consumed_repos.update(repos)
        lines.extend(render_section(section["id"], section["name"], section_tools))
        lines.append("")

    if include_uncategorized:
        uncategorized = [
            tool for tool in tools if tool.repo not in consumed_repos
        ]
        if uncategorized:
            fallback = config.get(
                "default_section",
                {"id": "shared_other", "name": "Shared Other Tools"},
            )
            lines.extend(render_section(fallback["id"], fallback["name"], uncategorized))
            lines.append("")

    if lines[-1] == "":
        lines.pop()
    lines.append("</toolbox>")
    return "\n".join(lines) + "\n"


def write_output(output_path: str, content: str) -> None:
    if output_path == "-":
        sys.stdout.write(content)
        return

    output = Path(output_path)
    output.write_text(content, encoding="utf-8")


def main() -> int:
    args = parse_args()
    config = load_section_config(Path(args.section_config))
    tools = discover_tools(Path(args.shed_tools_root), args.container_prefix)
    xml = build_xml(
        tools,
        config,
        include_uncategorized=not args.skip_uncategorized,
    )
    write_output(args.output, xml)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
