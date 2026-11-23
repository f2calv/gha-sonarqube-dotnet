#!/usr/bin/env bats
#Bats isolates tests; injection payloads below are deliberately literal.
#shellcheck disable=SC2030,SC2031,SC2016
bats_require_minimum_version 1.5.0
bats_load_library bats-support
bats_load_library bats-assert

setup() {
  export SCRIPT="$BATS_TEST_DIRNAME/../../.scripts/analyze.sh"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/work" "$BATS_TEST_TMPDIR/temp"
  cp "$BATS_TEST_DIRNAME/fakes/dotnet.sh" "$BATS_TEST_TMPDIR/bin/dotnet"
  chmod +x "$BATS_TEST_TMPDIR/bin/dotnet"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export FAKE_SCANNER="$BATS_TEST_DIRNAME/fakes/scanner.sh"
  export COMMAND_LOG="$BATS_TEST_TMPDIR/commands"
  touch "$COMMAND_LOG" "$BATS_TEST_TMPDIR/work/Example.slnx" "$BATS_TEST_TMPDIR/work/Mobile.csproj"
  echo '{"test":{"runner":"Microsoft.Testing.Platform"}}' > "$BATS_TEST_TMPDIR/work/global.json"
  unset IN_SONAR_TOKEN SONAR_ORGANIZATION SONAR_REGION ADDITIONAL_PROJECTS SONAR_EXCLUSIONS
  unset QUALITY_GATE_WAIT BUILD_CONFIGURATION EXECUTE_TESTS DOTNET_TEST_ARGS COVERAGE_REPORT_PATHS FAIL_COMMAND
  unset RUNNER_OS EXPECT_NATIVE_SCANNER_ARGS
  export SONAR_TOKEN=fixture-token SONAR_HOST_URL=https://sonarqube.example.com SONAR_PROJECT_KEY=example_project
  export SOLUTION_NAME=Example.slnx PROJECT_BASE_DIRECTORY="$BATS_TEST_TMPDIR/work" RUNNER_TEMP="$BATS_TEST_TMPDIR/temp"
}

@test "scans repository-wide sources and all requested projects before submission" {
  export ADDITIONAL_PROJECTS='["Mobile.csproj"]' EXECUTE_TESTS=true
  export DOTNET_TEST_ARGS='["--minimum-expected-tests","4"]'
  run bash "$SCRIPT"
  assert_success
  run cat "$COMMAND_LOG"
  assert_line --index 0 --partial '<--version> <12.1.0>'
  assert_line --index 1 --partial "/d:sonar.projectBaseDir=$PROJECT_BASE_DIRECTORY"
  assert_line --index 1 --partial '/d:sonar.scanner.scanAll=true'
  assert_line --index 1 --partial '/d:sonar.dotnet.excludeTestProjects=false'
  assert_line --index 1 --partial '/d:sonar.cs.vscoveragexml.reportsPaths=TestResults/**/*.xml'
  assert_line --index 2 --partial 'dotnet <build> <Example.slnx>'
  assert_line --index 3 --partial 'dotnet <build> <Mobile.csproj>'
  assert_line --index 4 --partial 'dotnet <test> <--solution> <Example.slnx>'
  assert_line --index 4 --partial '<--minimum-expected-tests> <4>'
  assert_line --index 5 'scanner <end>'
  refute_output --partial fixture-token
  refute_output --partial '<--coverage-output>'
  run find "$RUNNER_TEMP" -mindepth 1
  assert_output ''
}

@test "fails explicitly without credentials before running tools" {
  unset SONAR_TOKEN
  run --separate-stderr bash "$SCRIPT"
  assert_failure 1
  [[ "$stderr" == *'Required environment variable SONAR_TOKEN is not set.'* ]]
  [[ ! -s "$COMMAND_LOG" ]]
}

@test "never submits partial results after scanner, build or test failure" {
  export EXECUTE_TESTS=true
  for command in tool begin build test end; do
    export FAIL_COMMAND="$command"
    : > "$COMMAND_LOG"
    run --separate-stderr bash "$SCRIPT"
    assert_failure 1
    [[ "$stderr" == *'SonarQube analysis failed'* ]]
    if [[ "$command" != end ]]; then
      run grep 'scanner <end>' "$COMMAND_LOG"
      assert_failure 1
    fi
  done
}

@test "rejects malformed project and test argument arrays before running tools" {
  for value in 'not-json' '{}' '[42]' '[""]'; do
    export ADDITIONAL_PROJECTS="$value"
    run bash "$SCRIPT"
    assert_failure 1
  done
  export ADDITIONAL_PROJECTS='[]' DOTNET_TEST_ARGS='["--filter",42]'
  run bash "$SCRIPT"
  assert_failure 1
  [[ ! -s "$COMMAND_LOG" ]]
}

@test "rejects missing targets and wrong test runner before running tools" {
  export ADDITIONAL_PROJECTS='["Missing.csproj"]'
  run bash "$SCRIPT"
  assert_failure 1
  export ADDITIONAL_PROJECTS='[]' EXECUTE_TESTS=true
  echo '{}' > "$PROJECT_BASE_DIRECTORY/global.json"
  run bash "$SCRIPT"
  assert_failure 1
  [[ ! -s "$COMMAND_LOG" ]]
}

@test "uses the project test selector and preserves literal argument values" {
  export SOLUTION_NAME=Mobile.csproj EXECUTE_TESTS=true
  export DOTNET_TEST_ARGS='["--filter","value with spaces; $(touch injected)"]'
  run bash "$SCRIPT"
  assert_success
  run cat "$COMMAND_LOG"
  assert_output --partial 'dotnet <test> <--project> <Mobile.csproj>'
  assert_output --partial '<value with spaces; $(touch injected)>'
  [[ ! -e "$PROJECT_BASE_DIRECTORY/injected" ]]
}

@test "preserves project paths and test arguments with native Windows jq output" {
  jq() {
    if [[ "$1" == -r ]]; then
      command jq "$@" | sed 's/$/\r/'
    else
      command jq "$@"
    fi
  }
  export -f jq
  export ADDITIONAL_PROJECTS='["Mobile.csproj"]' EXECUTE_TESTS=true
  export DOTNET_TEST_ARGS='["--minimum-expected-tests","4"]'
  run bash "$SCRIPT"
  assert_success
  run cat "$COMMAND_LOG"
  assert_output --partial 'dotnet <build> <Mobile.csproj>'
  assert_output --partial '<--minimum-expected-tests> <4>'
}

@test "accepts input credentials and forwards Cloud region and coverage settings" {
  unset SONAR_TOKEN
  export IN_SONAR_TOKEN=fixture-token SONAR_HOST_URL=https://sonarcloud.io SONAR_ORGANIZATION=example
  export SONAR_REGION=us COVERAGE_REPORT_PATHS='TestResults/**/*.xml'
  run bash "$SCRIPT"
  assert_success
  run cat "$COMMAND_LOG"
  assert_output --partial '</o:example>'
  assert_output --partial '</d:sonar.region=us>'
  assert_output --partial '</d:sonar.cs.vscoveragexml.reportsPaths=TestResults/**/*.xml>'
  refute_output --partial fixture-token
}

@test "passes unchanged scanner switches and a native analysis root on Windows" {
  cygpath() {
    [[ "$1" == -m && "$2" == "$PROJECT_BASE_DIRECTORY" ]] || return 1
    printf 'D:/fixture root\n'
  }
  export -f cygpath
  export RUNNER_OS=Windows EXPECT_NATIVE_SCANNER_ARGS=true
  run bash "$SCRIPT"
  assert_success
  run cat "$COMMAND_LOG"
  assert_output --partial 'scanner <begin> </k:example_project>'
  assert_output --partial '</d:sonar.projectBaseDir=D:/fixture root>'
  assert_line --index 3 'scanner <end>'
}

@test "requires a Cloud organization and validates boolean inputs" {
  export SONAR_HOST_URL=https://sonarcloud.io
  run bash "$SCRIPT"
  assert_failure 1
  export SONAR_ORGANIZATION=example QUALITY_GATE_WAIT=invalid
  run bash "$SCRIPT"
  assert_failure 1
  [[ ! -s "$COMMAND_LOG" ]]
}
