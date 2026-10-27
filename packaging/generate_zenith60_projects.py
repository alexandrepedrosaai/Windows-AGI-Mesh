#!/usr/bin/env python3
"""Generate the 60-module Zenith catalog plus the MajoranaZenithSDK root package."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "packaging" / "zenith60-generated"
MANIFEST = ROOT / "packaging" / "zenith60-packages.json"

GROUP_A = [
    "Zenith.Agent.Runtime", "Zenith.Agent.Hosting", "Zenith.Agent.Registry",
    "Zenith.Agent.Orchestration", "Zenith.Agent.Lifecycle",
    "Zenith.Memory.Vectorization", "Zenith.Memory.Consolidation",
    "Zenith.Memory.ContextGraph", "Zenith.Memory.TemporalIndex",
    "Zenith.Memory.Compression", "Zenith.Storage.Checkpointing",
    "Zenith.Storage.Replication", "Zenith.Storage.Versioning",
    "Zenith.Storage.Archive", "Zenith.Storage.Snapshot",
    "Zenith.Reasoning.Symbolic", "Zenith.Reasoning.Causal",
    "Zenith.Reasoning.Hierarchical", "Zenith.Reasoning.GoalEngine",
    "Zenith.Reasoning.ConstraintSolver",
]
GROUP_B = [
    "Zenith.Agent.Teamwork", "Zenith.Agent.Consensus", "Zenith.Agent.SocialGraph",
    "Zenith.Agent.MissionPlanner", "Zenith.Agent.TaskDelegation",
    "Zenith.Cognition.Reflection", "Zenith.Cognition.SelfAssessment",
    "Zenith.Cognition.MetaReasoning", "Zenith.Cognition.Uncertainty",
    "Zenith.Cognition.HypothesisEngine", "Zenith.Persistence.LocalFirst",
    "Zenith.Persistence.EdgeSync", "Zenith.Persistence.MeshReplication",
    "Zenith.Persistence.QuantumAnchor", "Zenith.Persistence.TimeTravel",
    "Zenith.Edge.Autonomy", "Zenith.Edge.Cluster", "Zenith.Edge.Cooperation",
    "Zenith.Edge.DeviceDiscovery", "Zenith.Edge.MeshRouting",
]
GROUP_C = [
    "Zenith.Benchmark.Reasoning", "Zenith.Benchmark.Memory", "Zenith.Benchmark.Agentic",
    "Zenith.Benchmark.Edge", "Zenith.Benchmark.Immersive", "Zenith.Dataset.Logic",
    "Zenith.Dataset.Causality", "Zenith.Dataset.Planning", "Zenith.Dataset.Memory",
    "Zenith.Dataset.Dialog", "Zenith.Toolkit.Visualizer", "Zenith.Toolkit.Telemetry",
    "Zenith.Toolkit.Diagnostics", "Zenith.Toolkit.Profiler", "Zenith.Toolkit.Validator",
    "Zenith.Research.Majorana", "Zenith.Research.QPersistence", "Zenith.Research.EdgeAGI",
    "Zenith.Research.LocalIntelligence", "Zenith.Research.MeshTheory",
]


def safe(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9.-]+", "-", value).strip(".-")


def project_xml(package_id: str, number: int, dependencies: list[str]) -> str:
    dep_xml = ""
    if dependencies:
        dep_xml = "\n  <ItemGroup>\n" + "".join(
            f'    <PackageReference Include="{d}" Version="$(PackageVersion)" />\n'
            for d in dependencies
        ) + "  </ItemGroup>\n"
    readme = f"$(MSBuildProjectDirectory)/../../packaging/zenith60-readmes/{safe(package_id)}.md"
    return f'''<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <IsPackable>true</IsPackable>
    <IncludeBuildOutput>false</IncludeBuildOutput>
    <PackageId>{package_id}</PackageId>
    <PackageVersion Condition="'$(PackageVersion)' == ''">0.2.0-local</PackageVersion>
    <PackageTitle>{package_id}</PackageTitle>
    <PackageReadmeFile>README.md</PackageReadmeFile>
    <Description>Zenith module {number}/60 for the MajoranaZenithSDK catalog.</Description>
    <Authors>alexandrepedrosaai</Authors>
    <RepositoryUrl>https://github.com/alexandrepedrosaai/Windows-AGI-Mesh</RepositoryUrl>
    <PackageTags>Zenith;MajoranaZenithSDK;Windows-AGI-Mesh</PackageTags>
  </PropertyGroup>{dep_xml}  <ItemGroup>
    <None Include="{readme}" Pack="true" PackagePath="README.md" Visible="false" />
    <None Include="$(MSBuildProjectDirectory)/../../packaging/zenith60-packages.json" Pack="true" PackagePath="build/zenith60-packages.json" Visible="false" />
  </ItemGroup>
</Project>
'''


def main() -> None:
    if len(GROUP_A) != 20 or len(GROUP_B) != 20 or len(GROUP_C) != 20:
        raise SystemExit("Each Zenith group must contain exactly 20 packages")
    OUT.mkdir(parents=True, exist_ok=True)
    readmes = ROOT / "packaging" / "zenith60-readmes"
    readmes.mkdir(parents=True, exist_ok=True)
    for p in OUT.glob("*.csproj"):
        p.unlink()
    for p in readmes.glob("*.md"):
        p.unlink()

    entries = [{
        "number": 0,
        "id": "MajoranaZenithSDK",
        "group": "root",
        "dependsOn": [],
    }]
    for i, package in enumerate(GROUP_A, 1):
        entries.append({"number": i, "id": package, "group": "A", "dependsOn": ["MajoranaZenithSDK"]})
    for i, package in enumerate(GROUP_B, 1):
        # Each B module gets the SDK and exactly 19 of the 20 A modules.
        omitted = (i - 1) % len(GROUP_A)
        deps = ["MajoranaZenithSDK"] + [p for j, p in enumerate(GROUP_A) if j != omitted]
        entries.append({"number": 20 + i, "id": package, "group": "B", "omitsGroupA": GROUP_A[omitted], "dependsOn": deps})
    for i, package in enumerate(GROUP_C, 1):
        entries.append({"number": 40 + i, "id": package, "group": "C", "dependsOn": []})

    if len(entries) != 61:
        raise SystemExit(f"Expected 61 packages including the root, found {len(entries)}")
    MANIFEST.write_text(json.dumps({
        "schemaVersion": 1,
        "rootPackage": "MajoranaZenithSDK",
        "additionalPackages": 60,
        "totalPublishedPackages": 61,
        "combinationRule": "Each Group B package depends on the root and 19 Group A packages, omitting one Group A package in round-robin order.",
        "packages": entries,
    }, indent=2) + "\n", encoding="utf-8")

    root_project = '''<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <IsPackable>true</IsPackable>
    <IncludeBuildOutput>false</IncludeBuildOutput>
    <PackageId>MajoranaZenithSDK</PackageId>
    <PackageVersion Condition="'$(PackageVersion)' == ''">0.2.0-local</PackageVersion>
    <PackageTitle>MajoranaZenithSDK</PackageTitle>
    <PackageReadmeFile>README.md</PackageReadmeFile>
    <Description>Root SDK package for the 60-module Zenith catalog.</Description>
    <Authors>alexandrepedrosaai</Authors>
    <RepositoryUrl>https://github.com/alexandrepedrosaai/Windows-AGI-Mesh</RepositoryUrl>
    <PackageTags>MajoranaZenithSDK;Zenith;Windows-AGI-Mesh</PackageTags>
  </PropertyGroup>
  <ItemGroup>
    <None Include="$(MSBuildProjectDirectory)/../../README.md" Pack="true" PackagePath="README.md" Visible="false" />
    <None Include="$(MSBuildProjectDirectory)/../../packaging/zenith60-packages.json" Pack="true" PackagePath="build/zenith60-packages.json" Visible="false" />
  </ItemGroup>
</Project>
'''
    (OUT / "MajoranaZenithSDK.csproj").write_text(root_project, encoding="utf-8")

    for entry in entries[1:]:
        package = str(entry["id"])
        (OUT / f"{safe(package)}.csproj").write_text(
            project_xml(package, int(entry["number"]), list(entry["dependsOn"])), encoding="utf-8"
        )
        deps = ", ".join(entry["dependsOn"]) or "none"
        omitted = f"\n\nThis round omits `{entry['omitsGroupA']}` from Group A." if entry.get("omitsGroupA") else ""
        (readmes / f"{safe(package)}.md").write_text(
            f"# {package}\n\nZenith catalog module {entry['number']}/60.\n\nDependencies: {deps}.{omitted}\n",
            encoding="utf-8",
        )
    print(f"Generated {len(entries)} package projects: 1 root + 60 Zenith modules")


if __name__ == "__main__":
    main()
