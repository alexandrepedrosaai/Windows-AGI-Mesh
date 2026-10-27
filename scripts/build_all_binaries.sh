#!/usr/bin/env bash
set -uo pipefail

output_root="${1:-artifacts/binaries}"
mkdir -p "$output_root"
: > "$output_root/build-report.txt"
failures=0
successes=0

mapfile -t projects < <(find . -type f \( -name '*.csproj' -o -name '*.qsproj' \) \
  -not -path './.git/*' \
  -not -path './packaging/generated/*' \
  -not -path './packaging/zenith60-generated/*' \
  -not -path './tools/MZM.Hilbert.DSL/*' | sort)

for project in "${projects[@]}"; do
  slug="$(printf '%s' "$project" | sed 's#^./##; s#[/.]#-#g; s#-$##')"
  destination="$output_root/$slug"
  mkdir -p "$destination"
  echo "BUILD $project" | tee -a "$output_root/build-report.txt"
  if dotnet publish "$project" --configuration Release --output "$destination" --nologo >> "$output_root/build-report.txt" 2>&1; then
    successes=$((successes + 1))
    echo "OK $project" | tee -a "$output_root/build-report.txt"
  else
    failures=$((failures + 1))
    echo "FAILED $project" | tee -a "$output_root/build-report.txt"
  fi
done

printf 'projects=%s successes=%s failures=%s\n' "${#projects[@]}" "$successes" "$failures" | tee -a "$output_root/build-report.txt"
if (( failures > 0 )); then
  exit 1
fi
