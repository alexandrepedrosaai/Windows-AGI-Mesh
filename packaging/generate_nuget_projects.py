#!/usr/bin/env python3
"""Generate deterministic SDK-style pack projects for the 50-package catalog."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "packaging" / "generated"
MANIFEST = ROOT / "packaging" / "packages.json"


def package_id(stem: str) -> str:
    value = re.sub(r"[^A-Za-z0-9.-]+", "-", stem).strip(".-")
    return value or "MajoranaZenithComponent"


def source_files(project: Path) -> list[Path]:
    candidates = [project]
    sibling = project.with_suffix(".qs")
    if sibling.is_file():
        candidates.append(sibling)
    sibling_cs = project.with_suffix(".cs")
    if sibling_cs.is_file():
        candidates.append(sibling_cs)
    readme = project.parent / "README.md"
    if readme.is_file():
        candidates.append(readme)
    return candidates


def xml_escape(value: str) -> str:
    return (value.replace("&", "&amp;")
                 .replace("<", "&lt;")
                 .replace(">", "&gt;")
                 .replace('"', "&quot;"))


def main() -> None:
    projects = sorted(
        p for p in ROOT.rglob("*")
        if p.is_file() and p.suffix in {".csproj", ".qsproj"}
        and ".git" not in p.parts
        and "packaging/generated" not in p.as_posix()
    )
    if len(projects) < 49:
        raise SystemExit(f"Expected at least 49 source projects, found {len(projects)}")

    entries: list[dict[str, object]] = [{
        "number": 1,
        "id": "MajoranaZenithSDK",
        "source": "README.md",
        "kind": "sdk-root",
        "dependsOn": [],
    }]

    used = {"MajoranaZenithSDK"}
    for number, project in enumerate(projects[:49], start=2):
        candidate = package_id(project.stem)
        if candidate in used:
            candidate = f"{candidate}-{number:02d}"
        used.add(candidate)
        entries.append({
            "number": number,
            "id": candidate,
            "source": project.relative_to(ROOT).as_posix(),
            "kind": project.suffix.lstrip("."),
            "dependsOn": ["MajoranaZenithSDK"],
        })

    if len(entries) != 50 or entries[0]["id"] != "MajoranaZenithSDK":
        raise SystemExit("Package catalog must contain exactly 50 entries with MajoranaZenithSDK first")

    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.csproj"):
        old.unlink()

    manifest = {
        "schemaVersion": 1,
        "description": "Deterministic 50-package MajoranaZenithSDK NuGet catalog",
        "selection": "MajoranaZenithSDK followed by the first 49 sorted .csproj/.qsproj files",
        "packages": entries,
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    for entry in entries:
        package = str(entry["id"])
        number = int(entry["number"])
        dependencies = ""
        if entry["dependsOn"]:
            dependencies = """\n  <ItemGroup>\n    <PackageReference Include=\"MajoranaZenithSDK\" Version=\"$(PackageVersion)\" />\n  </ItemGroup>\n"""

        project_lines = [
            '<Project Sdk="Microsoft.NET.Sdk">',
            '  <PropertyGroup>',
            '    <TargetFramework>net9.0</TargetFramework>',
            '    <IsPackable>true</IsPackable>',
            '    <IncludeBuildOutput>false</IncludeBuildOutput>',
            f'    <PackageId>{xml_escape(package)}</PackageId>',
            '    <PackageVersion Condition="\'$(PackageVersion)\' == \'\'">0.1.0-local</PackageVersion>',
            f'    <PackageTitle>{xml_escape(package)}</PackageTitle>',
            f'    <Description>MajoranaZenithSDK catalog package {number}/50 for Windows AGI Mesh.</Description>',
            '    <Authors>alexandrepedrosaai</Authors>',
            '    <PackageRequireLicenseAcceptance>false</PackageRequireLicenseAcceptance>',
            '    <RepositoryUrl>https://github.com/alexandrepedrosaai/Windows-AGI-Mesh</RepositoryUrl>',
            '    <PackageTags>MajoranaZenithSDK;Windows-AGI-Mesh;quantum;QSharp</PackageTags>',
            '  </PropertyGroup>',
        ]
        project_lines.append(dependencies.rstrip("\n"))
        project_lines.append('  <ItemGroup>')

        if number == 1:
            files = [ROOT / "README.md"]
            if (ROOT / "global.json").is_file():
                files.append(ROOT / "global.json")
        else:
            source = ROOT / str(entry["source"])
            files = source_files(source)

        for source in files:
            relative = source.relative_to(ROOT).as_posix()
            package_path = f"contentFiles/any/any/{relative}"
            project_lines.extend([
                f'    <None Include="$(MSBuildProjectDirectory)/../../{relative}" Pack="true" PackagePath="{package_path}" Visible="false" />',
            ])
        project_lines.extend(['  </ItemGroup>', '</Project>', ''])
        (OUT / f"{package}.csproj").write_text("\n".join(project_lines), encoding="utf-8")

    print(f"Generated {len(entries)} package projects")
    for entry in entries:
        print(f"{int(entry['number']):02d} {entry['id']} <- {entry['source']}")


if __name__ == "__main__":
    main()
