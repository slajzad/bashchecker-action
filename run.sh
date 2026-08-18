#!/usr/bin/env bash
# BashChecker composite action runner.
# Posts each matched script to the BashChecker CI endpoint, writes a job
# summary, and exits non-zero when a blocking finding is present.
set -uo pipefail

FILES_INPUT="${INPUT_FILES:-**/*.sh}"
FAIL_ON="${INPUT_FAIL_ON:-high}"
MAX_FILES="${INPUT_MAX_FILES:-10}"
ENDPOINT="${INPUT_ENDPOINT:?endpoint input is required}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

case "$FAIL_ON" in
  high|medium|low|info|none) ;;
  *) echo "::error::fail-on must be one of: high, medium, low, info, none (got '$FAIL_ON')"; exit 1 ;;
esac

command -v jq >/dev/null 2>&1 || { echo "::error::jq is required and was not found on the runner"; exit 1; }

# Expand the globs. Word-splitting is intentional: multiple globs may be given.
shopt -s globstar nullglob
# shellcheck disable=SC2206
patterns=($FILES_INPUT)
matched=()
for pattern in "${patterns[@]}"; do
  for path in $pattern; do
    [ -f "$path" ] && matched+=("$path")
  done
done
shopt -u globstar nullglob

if [ "${#matched[@]}" -eq 0 ]; then
  echo "::warning::No files matched '$FILES_INPUT' — nothing to analyze."
  {
    echo "## BashChecker"
    echo
    echo "No files matched \`$FILES_INPUT\`."
  } >> "$SUMMARY"
  echo "passed=true" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "risk-score=0" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

# Deduplicate and cap.
mapfile -t files < <(printf '%s\n' "${matched[@]}" | sort -u | head -n "$MAX_FILES")

{
  echo "## BashChecker"
  echo
  echo "| File | Risk | High | Medium | Low | Result |"
  echo "|---|---:|---:|---:|---:|---|"
} >> "$SUMMARY"

overall_pass=1
max_score=0
blocking_report=""

for file in "${files[@]}"; do
  echo "Analyzing $file"

  request=$(jq -n \
    --rawfile script "$file" \
    --arg failOn "$FAIL_ON" \
    --arg fileName "$file" \
    '{script: $script, failOn: $failOn, fileName: $fileName}')

  response=$(printf '%s' "$request" | curl -sS -m 300 \
    -X POST "$ENDPOINT" \
    -H 'Content-Type: application/json' \
    --data-binary @-)
  curl_status=$?

  if [ $curl_status -ne 0 ] || [ -z "$response" ]; then
    echo "::error file=$file::BashChecker request failed (curl exit $curl_status)"
    echo "| \`$file\` | – | – | – | – | request failed |" >> "$SUMMARY"
    overall_pass=0
    continue
  fi

  if ! echo "$response" | jq -e 'has("passed")' >/dev/null 2>&1; then
    message=$(echo "$response" | jq -r '.error // "Unreadable response"' 2>/dev/null || echo "Unreadable response")
    echo "::error file=$file::BashChecker: $message"
    echo "| \`$file\` | – | – | – | – | $message |" >> "$SUMMARY"
    overall_pass=0
    continue
  fi

  passed=$(echo "$response" | jq -r '.passed')
  score=$(echo "$response" | jq -r '.riskScore // 0')
  high=$(echo "$response" | jq -r '.counts.high // 0')
  medium=$(echo "$response" | jq -r '.counts.medium // 0')
  low=$(echo "$response" | jq -r '.counts.low // 0')

  [ "$score" -gt "$max_score" ] 2>/dev/null && max_score=$score

  # Emit each blocking finding as a GitHub annotation on the right line.
  while IFS=$'\t' read -r severity line description; do
    [ -z "$severity" ] && continue
    level="warning"
    [ "$severity" = "high" ] && level="error"
    if [ -n "$line" ] && [ "$line" != "null" ]; then
      echo "::${level} file=${file},line=${line}::[${severity}] ${description}"
    else
      echo "::${level} file=${file}::[${severity}] ${description}"
    fi
    blocking_report="${blocking_report}- \`${file}\`: **${severity}** — ${description}"$'\n'
  done < <(echo "$response" | jq -r '.blocking[]? | [.severity, (.line // ""), .description] | @tsv')

  if [ "$passed" = "true" ]; then
    result="pass"
  else
    result="**fail**"
    overall_pass=0
  fi

  echo "| \`$file\` | $score | $high | $medium | $low | $result |" >> "$SUMMARY"
done

if [ -n "$blocking_report" ]; then
  {
    echo
    echo "### Blocking findings (fail-on: \`$FAIL_ON\`)"
    echo
    printf '%s' "$blocking_report"
  } >> "$SUMMARY"
fi

badge_url="https://bashchecker.com/badge.svg"
{
  echo
  echo "Full analysis: https://bashchecker.com"
} >> "$SUMMARY"

{
  echo "risk-score=$max_score"
  echo "badge-url=$badge_url"
} >> "${GITHUB_OUTPUT:-/dev/null}"

if [ "$FAIL_ON" = "none" ] || [ "$overall_pass" -eq 1 ]; then
  echo "passed=true" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

echo "passed=false" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "::error::BashChecker found blocking findings at or above severity '$FAIL_ON'."
exit 1
