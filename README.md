# GitHub Action: SonarQube Analysis for .NET

[![Latest Release](https://img.shields.io/github/v/release/f2calv/gha-sonarqube-dotnet)](https://github.com/f2calv/gha-sonarqube-dotnet/releases/latest)
[![License](https://img.shields.io/github/license/f2calv/gha-sonarqube-dotnet)](LICENSE)

This GitHub Action runs [SonarQube](https://www.sonarsource.com/products/sonarqube/) / [SonarCloud](https://sonarcloud.io/) code-quality analysis on .NET projects. It installs the `dotnet-sonarscanner` tool, builds the solution, and submits results. If `sonar-token` is not provided, the action posts a warning and skips analysis.

## Usage

```yaml
steps:
  - uses: actions/checkout@v6
    with:
      fetch-depth: 0

  - uses: f2calv/gha-sonarqube-dotnet@v2
    with:
      github-token: ${{ secrets.GITHUB_TOKEN }}
      sonar-token: ${{ secrets.SONAR_TOKEN }}
```

## Inputs

| Input | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| `github-token` | string | ✅ | | GitHub token for PR information, i.e. `${{ secrets.GITHUB_TOKEN }}` |
| `sonar-token` | string | ✅ | | SonarQube/SonarCloud authentication token, i.e. `${{ secrets.SONAR_TOKEN }}` |
| `sonar-host-url` | string | | `https://sonarcloud.io` | SonarQube server URL |
| `build-configuration` | string | | `Release` | .NET build configuration e.g. `Debug` or `Release` |
