#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>
set -euo pipefail

# Sets what the GitHub provider cannot manage, after every apply. The plan
# reads each back through check blocks (checks.tf), and the drift run fails
# when one no longer holds.
#
# Usage: assert-unmanaged.sh <org> <repo>...    (needs GH_TOKEN)

if [[ $# -lt 2 ]]; then
    echo "usage: assert-unmanaged.sh <org> <repo>..." >&2
    exit 1
fi
: "${GH_TOKEN:?GH_TOKEN must hold a token from the divbast-infra App}"

org=$1
shift

# Security reports arrive privately on the affected repo; SECURITY.md has
# no email address to offer instead.
for repo in "$@"; do
    gh api -X PUT "repos/${org}/${repo}/private-vulnerability-reporting" >/dev/null
done

# A fork PR from anyone outside the org waits for a maintainer before its
# workflows run.
gh api -X PUT "orgs/${org}/actions/permissions/fork-pr-contributor-approval" \
    -f approval_policy=all_external_contributors >/dev/null

# Security features are set per repo in OpenTofu. A default code security
# configuration would fight those settings, so its presence is an error
# for a person to resolve, not something to undo here.
defaults=$(gh api "orgs/${org}/code-security/configurations/defaults")
if [[ $(jq 'length' <<<"${defaults}") -ne 0 ]]; then
    echo "a default code security configuration is set; remove it so OpenTofu's per-repo settings stand:" >&2
    jq -r '.[] | "  \(.configuration.name) (default for \(.default_for_new_repos) repos)"' <<<"${defaults}" >&2
    exit 1
fi

echo "private vulnerability reporting on for $# repos; fork PR approval required; no default code security configuration"
