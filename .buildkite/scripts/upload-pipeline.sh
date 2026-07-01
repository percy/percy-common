#!/usr/bin/env bash
# Decide whether to upload the full pipeline. See .buildkite/pipeline.yml.
set -uo pipefail

FULL=".buildkite/pipeline.steps.yml"

upload_full() {
  echo "+++ Uploading full pipeline"
  buildkite-agent pipeline upload "$FULL"
  exit $?
}

# Only pull-request builds are eligible for the docs-only skip. Every other build
# (branch / merge / tag, including master and any deploy branch) runs full CI.
if [[ "${BUILDKITE_PULL_REQUEST:-false}" == "false" ]]; then
  upload_full
fi

BASE="${BUILDKITE_PULL_REQUEST_BASE_BRANCH:-master}"

# CI clones can be shallow; fetch the PR base so we can diff against it.
git fetch --no-tags origin "+refs/heads/${BASE}:refs/remotes/origin/${BASE}" >/dev/null 2>&1 || true

FILES="$(git diff --name-only "origin/${BASE}...HEAD" 2>/dev/null || true)"
echo "--- Changed files vs origin/${BASE}"
printf '%s\n' "$FILES"

# Fail-safe: if the diff is empty or couldn't be computed, run the full pipeline.
if [[ -z "${FILES//[[:space:]]/}" ]]; then
  echo "No diff computed; running full pipeline."
  upload_full
fi

# Docs allowlist: *.md, *.txt, README*, LICENSE, docs/**. If ANY changed file
# falls outside it, run the full pipeline; otherwise skip CI (upload nothing).
if printf '%s\n' "$FILES" | grep -qvE '(\.md|\.txt)$|(^|/)README[^/]*$|(^|/)LICENSE$|^docs/'; then
  upload_full
fi

echo "+++ Docs-only PR — skipping CI"
buildkite-agent annotate "Docs-only change — full CI skipped." --style "info" --context "docs-only" || true