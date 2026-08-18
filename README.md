# BashChecker Action

Static security and quality analysis for Bash scripts, straight in CI. Scripts are
**never executed** — only analyzed.

[![Analyzed by BashChecker](https://bashchecker.com/badge.svg)](https://bashchecker.com)

## Usage

```yaml
name: BashChecker

on: [push, pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: bashchecker/bashchecker-action@v1
        with:
          files: 'scripts/**/*.sh'
          fail-on: high
```

## Inputs

| Input | Default | Description |
|---|---|---|
| `files` | `**/*.sh` | Glob(s) of scripts to analyze. Space-separated globs allowed. |
| `fail-on` | `high` | Fail the build on findings at or above this severity: `high`, `medium`, `low`, `info`, `none`. |
| `max-files` | `10` | Cap on files analyzed per run. |
| `endpoint` | BashChecker CI endpoint | Override only for self-hosted deployments. |

## Outputs

| Output | Description |
|---|---|
| `passed` | `true` when no finding met the threshold. |
| `risk-score` | Highest risk score (0–100) across analyzed files. |
| `badge-url` | Badge SVG URL for the run. |

## What it does

- Posts each matched script to the BashChecker analysis API
- Annotates the exact lines of blocking findings in the PR
- Writes a per-file job summary with risk score and severity counts
- Exits non-zero when a blocking finding is present

## Badge

```markdown
[![Analyzed by BashChecker](https://bashchecker.com/badge.svg)](https://bashchecker.com)
```

More badge formats and a live score badge: <https://bashchecker.com/badge>

## Privacy

Script contents are sent to the BashChecker API for analysis and are not stored.
Do not run it on files containing plaintext secrets.

## License

MIT
