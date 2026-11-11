#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>
set -euo pipefail

# Orderings the provider does not know about. Without an edge in the
# graph, tofu runs the two resources in parallel: the apply fails half-way,
# or a protection lapses while it runs. Reads the module's graph, so it
# needs `just init`.

graph=$(tofu -chdir=modules/repository graph)
failed=0

need() {
    local from=$1 to=$2 why=$3
    if ! grep -qF -- "\"[root] ${from} (expand)\" -> \"[root] ${to} (expand)\"" <<<"${graph}"; then
        echo "${from} does not wait for ${to}: ${why}" >&2
        failed=1
    fi
}

# baikal-oci-image arrived with its vulnerability alerts off.
need github_repository_dependabot_security_updates.this github_repository_vulnerability_alerts.this \
    "GitHub refuses to configure security updates while alerts are off (422)"
need github_repository_ruleset.tag_update_deletion github_repository_ruleset.tag_creation \
    "a rule moving into tag_creation would go unenforced mid-apply"

if [[ ${failed} -ne 0 ]]; then
    exit 1
fi
echo "every ordering the provider does not know about is in the graph"
