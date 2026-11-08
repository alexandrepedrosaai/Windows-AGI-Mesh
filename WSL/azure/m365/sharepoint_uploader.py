"""SharePoint artifact contract for benchmark and transfer-learning reports."""
from dataclasses import dataclass
from pathlib import Path

@dataclass(frozen=True)
class Artifact:
    path: Path
    sha256: str
    release_tag: str


def manifest_entry(path: Path, sha256: str, release_tag: str) -> Artifact:
    if not path.is_file():
        raise FileNotFoundError(path)
    if len(sha256) != 64:
        raise ValueError("sha256 must be a 64-character digest")
    return Artifact(path, sha256, release_tag)
