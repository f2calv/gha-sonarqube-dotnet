#!/usr/bin/env bash
# Build .NET targets inside one repository-wide SonarQube analysis.
# Required environment variables: SONAR_TOKEN (or IN_SONAR_TOKEN), SONAR_HOST_URL,
# SONAR_PROJECT_KEY, SOLUTION_NAME, RUNNER_TEMP.
# Optional: SONAR_ORGANIZATION, SONAR_REGION, ADDITIONAL_PROJECTS, PROJECT_BASE_DIRECTORY,
# SONAR_EXCLUSIONS, QUALITY_GATE_WAIT, BUILD_CONFIGURATION, EXECUTE_TESTS,
# DOTNET_TEST_ARGS, COVERAGE_REPORT_PATHS, RUNNER_OS (Windows selects native paths).

if [[ -n "${IN_SONAR_TOKEN:-}" ]]; then
  export SONAR_TOKEN="$IN_SONAR_TOKEN"
fi
for var in SONAR_TOKEN SONAR_HOST_URL SONAR_PROJECT_KEY SOLUTION_NAME RUNNER_TEMP; do
  if [[ -z "${!var:-}" ]]; then
    echo "::error::Required environment variable $var is not set." >&2
    exit 1
  fi
done

set -euo pipefail
trap 'echo "::error::SonarQube analysis failed at line $LINENO." >&2' ERR

: "${SONAR_ORGANIZATION:=}"
: "${SONAR_REGION:=}"
: "${ADDITIONAL_PROJECTS:=[]}"
: "${PROJECT_BASE_DIRECTORY:=.}"
: "${SONAR_EXCLUSIONS:=}"
: "${QUALITY_GATE_WAIT:=false}"
: "${BUILD_CONFIGURATION:=Release}"
: "${EXECUTE_TESTS:=false}"
: "${DOTNET_TEST_ARGS:=[]}"
: "${COVERAGE_REPORT_PATHS:=}"

for value in "$QUALITY_GATE_WAIT" "$EXECUTE_TESTS"; do
  if [[ "$value" != true && "$value" != false ]]; then
    echo "::error::Boolean inputs must be true or false." >&2
    exit 1
  fi
done
if ! jq -e 'type == "array" and all(.[]; type == "string" and length > 0)' <<< "$ADDITIONAL_PROJECTS" >/dev/null; then
  echo "::error::additional-projects must be a JSON array of non-empty project paths." >&2
  exit 1
fi
if ! jq -e 'type == "array" and all(.[]; type == "string")' <<< "$DOTNET_TEST_ARGS" >/dev/null; then
  echo "::error::dotnet-test-args must be a JSON array of strings." >&2
  exit 1
fi
if [[ "$SONAR_HOST_URL" == https://sonarcloud.io && -z "$SONAR_ORGANIZATION" ]]; then
  echo "::error::sonar-organization is required for SonarQube Cloud." >&2
  exit 1
fi

cd "$PROJECT_BASE_DIRECTORY"
targets=("$SOLUTION_NAME")
mapfile -d '' -t additional_targets < <(jq -j '.[] | ., "\u0000"' <<< "$ADDITIONAL_PROJECTS")
targets+=("${additional_targets[@]}")
for target in "${targets[@]}"; do
  case "$target" in
    *.sln | *.slnx | *.csproj) ;;
    *) echo "::error::Build targets must be .sln, .slnx or .csproj files." >&2; exit 1 ;;
  esac
  if [[ ! -f "$target" ]]; then
    echo "::error::A requested build target does not exist." >&2
    exit 1
  fi
done
if [[ "$EXECUTE_TESTS" == true ]] && ! jq -e '.test.runner == "Microsoft.Testing.Platform"' global.json >/dev/null; then
  echo "::error::global.json must select Microsoft.Testing.Platform." >&2
  exit 1
fi

analysis_root="$PWD"
if [[ "${RUNNER_OS:-}" == Windows ]]; then
  analysis_root=$(cygpath -m "$analysis_root")
fi

scanner_args=(
  "/k:$SONAR_PROJECT_KEY"
  "/d:sonar.host.url=$SONAR_HOST_URL"
  "/d:sonar.projectBaseDir=$analysis_root"
  "/d:sonar.scanner.scanAll=true"
  "/d:sonar.dotnet.excludeTestProjects=false"
  "/d:sonar.qualitygate.wait=$QUALITY_GATE_WAIT"
)
[[ -z "$SONAR_ORGANIZATION" ]] || scanner_args+=("/o:$SONAR_ORGANIZATION")
[[ -z "$SONAR_REGION" ]] || scanner_args+=("/d:sonar.region=$SONAR_REGION")
[[ -z "$SONAR_EXCLUSIONS" ]] || scanner_args+=("/d:sonar.exclusions=$SONAR_EXCLUSIONS")
if [[ -n "$COVERAGE_REPORT_PATHS" ]]; then
  scanner_args+=("/d:sonar.cs.vscoveragexml.reportsPaths=$COVERAGE_REPORT_PATHS")
elif [[ "$EXECUTE_TESTS" == true ]]; then
  scanner_args+=("/d:sonar.cs.vscoveragexml.reportsPaths=TestResults/**/*.xml")
fi

scanner_dir=$(mktemp -d "$RUNNER_TEMP/sonarscanner.XXXXXX")
trap 'rm -rf "$scanner_dir"' EXIT
#The scanner publishes no floating major package; its JRE is provisioned automatically.
dotnet tool install dotnet-sonarscanner --version 12.1.0 --tool-path "$scanner_dir"
scanner="$scanner_dir/dotnet-sonarscanner"
MSYS2_ARG_CONV_EXCL='*' "$scanner" begin "${scanner_args[@]}"
for target in "${targets[@]}"; do
  dotnet build "$target" -c "$BUILD_CONFIGURATION" --no-incremental --disable-build-servers
done
if [[ "$EXECUTE_TESTS" == true ]]; then
  test_args=(--solution "$SOLUTION_NAME")
  [[ "$SOLUTION_NAME" != *.csproj ]] || test_args=(--project "$SOLUTION_NAME")
  mapfile -d '' -t extra_args < <(jq -j '.[] | ., "\u0000"' <<< "$DOTNET_TEST_ARGS")
  dotnet test "${test_args[@]}" -c "$BUILD_CONFIGURATION" --no-restore --no-build \
    --coverage --coverage-output-format xml "${extra_args[@]}"
fi
MSYS2_ARG_CONV_EXCL='*' "$scanner" end
