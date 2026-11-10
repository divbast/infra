#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>
set -euo pipefail

# The org lets only GitHub's own actions and actions-allowlist.txt run, all
# pinned to a full SHA, and that policy covers this repo too. An action
# missing from the list breaks CI the moment the policy applies.

allowed=$(grep -vE '^\s*(#|$)' actions-allowlist.txt)
failed=0
found=0

while IFS= read -r ref; do
    found=1
    action=${ref%@*}
    sha=${ref##*@}
    owner=${action%%/*}
    rest=${action#*/}
    repo="${owner}/${rest%%/*}"
    if [[ ! ${sha} =~ ^[0-9a-f]{40}$ ]]; then
        echo "${ref}: not pinned to a full SHA" >&2
        failed=1
    fi
    if [[ ${owner} != actions && ${owner} != github ]] \
            && ! grep -qxF "${repo}@*" <<<"${allowed}"; then
        echo "${ref}: ${repo}@* is not in actions-allowlist.txt" >&2
        failed=1
    fi
done < <(grep -hoE '^\s*(- )?uses:\s*[^ ]+' .github/workflows/*.yml \
    | sed -E 's/^\s*(- )?uses:\s*//' | grep -v '^\./' | sort -u)

if [[ ${found} -eq 0 ]]; then
    echo "no uses: lines found; is .github/workflows empty?" >&2
    exit 1
fi
if [[ ${failed} -ne 0 ]]; then
    exit 1
fi
echo "every action is allowed and pinned"
