#!/usr/bin/env bash
set -uo pipefail

output_root="${1:-artifacts/binaries}"
strict=0
if [[ "${2:-}" == "--strict" ]]; then
  strict=1
fi
mkdir -p "$output_root"
: > "$output_root/build-report.txt"
: > "$output_root/build-failures.txt"
failures=0
successes=0

mapfile -t projects < <(find . -type f \( -name '*.csproj' -o -name '*.qsproj' \) \
  -not -path './.git/*' \
  -not -path './packaging/generated/*' \
  -not -path './packaging/zenith60-generated/*' \
  -not -path './packaging/MZMWindowsSDK/*' \
  -not -path './packaging/MZMWindowsSDK.Dependencies/*' \
  -not -path './tools/MZM.Hilbert.DSL/*' | sort)

for project in "${projects[@]}"; do
  slug="$(printf '%s' "$project" | sed 's#^./##; s#[/.]#-#g; s#-$##')"
  destination="$output_root/$slug"
  mkdir -p "$destination"
  echo "BUILD $project" | tee -a "$output_root/build-report.txt"
  dotnet_args=(publish "$project" --configuration Release --output "$destination" --nologo --no-restore)
  if [[ -n "${NUGET_CONFIG:-}" ]]; then
    if ! dotnet restore "$project" --configfile "$NUGET_CONFIG" >> "$output_root/build-report.txt" 2>&1; then
      failures=$((failures + 1))
      echo "FAILED $project (restore)" | tee -a "$output_root/build-report.txt"
      printf '%s\n' "$project" >> "$output_root/build-failures.txt"
      continue
    fi
  else
    if ! dotnet restore "$project" >> "$output_root/build-report.txt" 2>&1; then
      failures=$((failures + 1))
      echo "FAILED $project (restore)" | tee -a "$output_root/build-report.txt"
      printf '%s\n' "$project" >> "$output_root/build-failures.txt"
      continue
    fi
  fi
  if dotnet "${dotnet_args[@]}" >> "$output_root/build-report.txt" 2>&1; then
    successes=$((successes + 1))
    echo "OK $project" | tee -a "$output_root/build-report.txt"
  else
    failures=$((failures + 1))
    echo "FAILED $project" | tee -a "$output_root/build-report.txt"
    printf '%s\n' "$project" >> "$output_root/build-failures.txt"
  fi
done

printf 'projects=%s successes=%s failures=%s\n' "${#projects[@]}" "$successes" "$failures" | tee -a "$output_root/build-report.txt"
if (( failures > 0 && strict == 1 )); then
  exit 1
fi
if (( failures > 0 )); then
  echo "WARN: $failures project(s) could not be published; see build-report.txt and build-failures.txt." | tee -a "$output_root/build-report.txt"
fi
