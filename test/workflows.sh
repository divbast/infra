#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>
set -euo pipefail

# Properties of the workflows that no linter checks, each one a way the
# tofu jobs could quietly do the wrong thing.

dir=.github/workflows
failed=0
fail() { echo "$1" >&2; failed=1; }

for f in ci plan apply drift renovate; do
    [[ -f "${dir}/${f}.yml" ]] || fail "${dir}/${f}.yml is missing"
done

for f in plan apply drift; do
    file="${dir}/${f}.yml"
    [[ -f "${file}" ]] || continue

    # An empty token makes the provider fall back to gh's token or to
    # anonymous access without an error (integrations/terraform-provider-github#3562).
    guard=$(grep -n 'GITHUB_TOKEN:?' "${file}" | head -n1 | cut -d: -f1 || true)
    init=$(grep -n 'tofu init' "${file}" | head -n1 | cut -d: -f1 || true)
    if [[ -z ${init} ]]; then
        fail "${file}: runs no tofu init"
    elif [[ -z ${guard} || ${guard} -gt ${init} ]]; then
        fail "${file}: no empty-token guard before the first tofu init"
    fi

    # B2 has no locking, so every tofu run queues on one group.
    grep -q 'group: tofu$' "${file}" || fail "${file}: not in concurrency group tofu"
    grep -q 'queue: max$' "${file}" || fail "${file}: concurrency does not queue"
    grep -q 'cancel-in-progress: false$' "${file}" || fail "${file}: a newer run could cancel an apply"
done

# A skipped job reports success, even as a required check, so a fork's PR
# must fail the plan job rather than skip it.
plan_job=$(awk '/^  plan:/{inside=1; next} inside && /^  [a-z]/{inside=0} inside' "${dir}/plan.yml" 2>/dev/null || true)
if grep -qE '^    if:' <<<"${plan_job}"; then
    fail "${dir}/plan.yml: the plan job has a job-level if, which skips (and so passes) on a fork's PR"
fi
grep -q "Refuse a fork's pull request" <<<"${plan_job}" \
    || fail "${dir}/plan.yml: no step failing a fork's pull request"

for f in plan apply drift; do
    file="${dir}/${f}.yml"
    [[ -f "${file}" ]] || continue
    # The jobs holding the admin token install only what they run.
    grep -qE '^          install_args: aqua:opentofu/opentofu aqua:jqlang/jq$' "${file}" \
        || fail "${file}: mise-action installs more than tofu and jq"
    # Secrets reach only the steps that use them, never every step.
    if grep -nE '^      (AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|TF_VAR_[a-z_]+):' "${file}"; then
        fail "${file}: credentials in job-level env are visible to every step"
    fi
done

# tofu show -json prints sensitive values in full; the repo is public.
while IFS= read -r line; do
    [[ ${line} =~ tofu\ show\ -json[^|]*\|\ *jq\ -e.*\.address ]] \
        || fail "tofu show -json not piped straight into jq -e printing only addresses: ${line}"
done < <(grep -h 'tofu show -json' "${dir}"/*.yml || true)

# These override the provider's owner or token (#3576, and the documented
# GITHUB_OWNER bug).
if grep -nE 'GITHUB_OWNER|GITHUB_ORGANIZATION|GITHUB_APP_' "${dir}"/*.yml; then
    fail "a workflow sets a variable that overrides the provider's owner or auth"
fi

# A skipped required check counts as passing, so the aggregator always runs.
awk '/^  required:/{inside=1; next} inside && /^  [a-z]/{inside=0} inside' "${dir}/ci.yml" 2>/dev/null \
    | grep -q 'if: always()' || fail "${dir}/ci.yml: the required job does not run always()"

if [[ ${failed} -ne 0 ]]; then
    exit 1
fi
echo "workflow properties hold"
