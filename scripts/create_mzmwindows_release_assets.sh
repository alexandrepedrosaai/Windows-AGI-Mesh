#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"
out="${1:-artifacts/MZMWindowsSDK}"
rm -rf "$out/source" "$out/binaries" "$out/SHA256SUMS.txt" "$out/SHA256SUMS-source.txt" "$out"/*.sha256 "$out/MZMWindowsSDK-source.tar.gz" "$out/MZMWindowsSDK-binaries.tar.gz"
mkdir -p "$out/source" "$out/binaries" "$out/nuget"

# Include every repository file known to Git, including generated architecture files.
git ls-files -co --exclude-standard -z \
  | tar --null --exclude='artifacts' --exclude='.git' -czf "$out/MZMWindowsSDK-source.tar.gz" --files-from=-

# Record a byte-level SHA256 for every repository source file.
: > "$out/SHA256SUMS-source.txt"
while IFS= read -r -d '' file; do
  [[ "$file" == artifacts/* ]] && continue
  sha256sum "$file" >> "$out/SHA256SUMS-source.txt"
done < <(git ls-files -co --exclude-standard -z | sort -z)
sort -o "$out/SHA256SUMS-source.txt" "$out/SHA256SUMS-source.txt"

# Build every C# and Q# project that is compatible with the current runner.
chmod +x scripts/build_all_binaries.sh
if [[ ! -s "$out/binaries/build-report.txt" ]]; then
  scripts/build_all_binaries.sh "$out/binaries" --strict \
    quantum/VAQLearningNeural/VAQLearningNeural.csproj
fi

# Package the MZM Hilbert DSL as a release NuGet artifact when the SDK is available.
if command -v dotnet >/dev/null 2>&1; then
  dotnet pack tools/MZM.Hilbert.DSL/MZM.Hilbert.DSL.csproj \
    --configuration Release --output "$out/nuget" \
    -p:PackageVersion="${MZM_TOOL_VERSION:-0.3.0-ci.local}" --nologo
fi

# Include all generated binary/QMesh outputs in one portable archive.
tar -czf "$out/MZMWindowsSDK-binaries.tar.gz" "$out/binaries"

# Hash every release payload except the manifests that are being generated.
find "$out" -type f \
  ! -name 'SHA256SUMS.txt' \
  ! -name 'SHA256SUMS-source.txt' \
  ! -name '*.sha256' -print0 \
  | sort -z | xargs -0 sha256sum > "$out/SHA256SUMS.txt"
while IFS= read -r digest file; do
  printf '%s  %s\n' "$digest" "$(basename "$file")" > "${file}.sha256"
done < "$out/SHA256SUMS.txt"
sha256sum -c "$out/SHA256SUMS.txt"
printf 'MZMWindowsSDK release assets created at %s\n' "$out"
