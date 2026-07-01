#!/usr/bin/env bash
# Decide whether to upload the full pipeline. See .buildkite/pipeline.yml.
set -uo pipefail

FULL=".buildkite/pipeline.steps.yml"

upload_full() {
  echo "+++ Uploading full pipeline"
  buildkite-agent pipeline upload "$FULL"
  exit $?
}

DEFAULT="${BUILDKITE_PIPELINE_DEFAULT_BRANCH:-master}"

# Always run full CI on the default branch and known deploy branches. The
# docs-only skip only ever applies to feature branches, so this works for both
# branch builds and PR builds — no dependency on PR context.
case "${BUILDKITE_BRANCH:-}" in
  "$DEFAULT"|master|percy_pre_prod|pre_master) upload_full ;;
esac

# Diff against the PR base when known, otherwise the default branch.
BASE="${BUILDKITE_PULL_REQUEST_BASE_BRANCH:-$DEFAULT}"

# CI clones can be shallow; fetch the base so we can diff against it.
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

echo "+++ Docs-only change — skipping CI"
buildkite-agent annotate "Docs-only change — full CI skipped." --style "info" --context "docs-only" || true