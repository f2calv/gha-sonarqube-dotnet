# gha-sonarqube-dotnet

GitHub Action for maintainers running .NET and multi-language code-quality analysis with
SonarQube Cloud or SonarQube Server. It builds every requested .NET target in one analysis,
optionally collects Microsoft.Testing.Platform coverage, and fails on scanner or build errors.

[![Latest Release](https://img.shields.io/github/v/release/f2calv/gha-sonarqube-dotnet)](https://github.com/f2calv/gha-sonarqube-dotnet/releases/latest)
[![License](https://img.shields.io/github/license/f2calv/gha-sonarqube-dotnet)](LICENSE)

## Usage

The following examples target **v3**. During feature-branch validation, use that branch or
commit reference until `@v3` is published. Existing `@v2` callers remain unchanged until they
migrate. Install the project's .NET SDKs and restore workloads
before authenticating, because SonarQube Cloud's ephemeral token lasts 30 minutes.

```yaml
jobs:
  analyze:
    runs-on: ubuntu-26.04
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - uses: actions/setup-dotnet@v6
        with:
          dotnet-version: 11.0.x

      - run: dotnet workload restore Example.slnx

      - uses: SonarSource/sonarqube-auth-action@v1
        id: auth

      - uses: f2calv/gha-sonarqube-dotnet@v3
        with:
          sonar-project-key: ${{ steps.auth.outputs.project-key }}
          sonar-organization: ${{ steps.auth.outputs.organization }}
          solution-name: Example.slnx
          quality-gate-wait: 'true'
```

For secretless authentication, enable **Administration > Organization settings > Analysis >
Enable secretless analysis for GitHub Actions** in SonarQube Cloud. The repository must be
bound to its project. Disable automatic analysis for that project before using CI analysis.
The official auth action exports `SONAR_TOKEN`; no stored GitHub secret is required.

For SonarQube Server or stored-token authentication, omit the auth action, remove
`id-token: write`, and pass `sonar-token: ${{ secrets.SONAR_TOKEN }}`. Set `sonar-host-url`
for your server and omit `sonar-organization`. Cloud users must provide the organization.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `sonar-token` | No | Environment `SONAR_TOKEN` | Stored or ephemeral authentication token. Missing credentials fail analysis. |
| `sonar-host-url` | No | `https://sonarcloud.io` | SonarQube server URL. |
| `sonar-project-key` | Yes | | Project key; explicit rather than inferred. |
| `sonar-organization` | For Cloud | | Cloud organization; empty for Server. |
| `solution-name` | Yes | | Primary `.sln`, `.slnx` or `.csproj` build/test target. |
| `additional-projects` | No | `[]` | JSON array of additional build targets included before submission; not additional test targets. |
| `project-base-directory` | No | `.` | Analysis root; build target paths are relative to it. |
| `sonar-exclusions` | No | Generated build/tool directories | Comma-separated exclusions; fixtures and tests are not blanket-excluded. |
| `quality-gate-wait` | No | `false` | Fail when the reported Quality Gate fails. |
| `build-configuration` | No | `Release` | Build/test configuration. |
| `execute-tests` | No | `false` | Run MTP tests on the primary target and collect Microsoft coverage XML. |
| `dotnet-test-args` | No | `[]` | JSON array preserving each literal argument. |
| `coverage-report-paths` | No | `TestResults/**/*.xml` when tests run | Existing Microsoft coverage XML to import. |

The action requires Bash, jq and the project's .NET SDK/workloads. It installs SonarScanner
for .NET **12.1.0** into a disposable runner directory; the scanner provisions its own JRE.
The analysis root includes supported non-.NET files through `sonar.scanner.scanAll=true`.
C# files must belong to a built project, including test projects. Generated output is excluded.
Coverage uses MTP's default per-application naming and merging rather than making parallel
target frameworks overwrite one fixed filename.

SonarScanner's supported language analyzers determine findings: Bash secret detection is not
a replacement for ShellCheck, actionlint or zizmor. Rust remains covered by its separate
Clippy/tests pipeline; this action does not promise Rust analysis.

## Migration from v2

- Remove the unused `github-token` input.
- Provide `sonar-project-key`, `solution-name` and, for Cloud, `sonar-organization` explicitly.
- Supply `dotnet-test-args` as a JSON array rather than a whitespace-delimited string.
- Missing authentication now fails instead of warning and skipping.
- Scanner/build/test failures stop submission; builds are non-incremental.

## Local Validation

Run `bats tests/bash` with bats-support, bats-assert and jq available, or use the
official `bats/bats:1.14.0` image. Tests use fake scanner/build commands, never real credentials
or SonarQube services. CI also exercises the composite action with those fakes and runs ShellCheck.
