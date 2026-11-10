#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>
set -euo pipefail

# Destroying these resources does not leave things as they were: a repo is
# deleted, the org's billing email becomes a placeholder, and the Actions
# policy and token defaults reset to GitHub's. Each must refuse it.

failed=0

# Print one resource block, from its opening line to its closing brace.
block() {
    awk -v start="resource \"$2\" \"$3\" {" '
        index($0, start) == 1 { inside = 1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$1"
}

need() {
    local file=$1 type=$2 name=$3 pattern=$4
    if ! block "${file}" "${type}" "${name}" | grep -qE "${pattern}"; then
        echo "${type}.${name} in ${file} lacks ${pattern}" >&2
        failed=1
    fi
}

repo=modules/repository/main.tf
org=modules/organization/main.tf

need "${repo}" github_repository this '^\s+destroy\s+=\s+false$'
need "${repo}" github_repository this '^\s+archive_on_destroy\s+=\s+true$'
for r in github_organization_settings github_actions_organization_permissions \
        github_actions_organization_workflow_permissions; do
    need "${org}" "${r}" this '^\s+prevent_destroy\s+=\s+true$'
done

if [[ ${failed} -ne 0 ]]; then
    exit 1
fi
echo "every guarded resource refuses destruction"
