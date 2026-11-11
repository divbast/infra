#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>
set -euo pipefail

# Turns on immutable releases for each repo named, after every apply:
# provider 6.13.0 has no attribute for it. Once a release is published,
# neither its tag nor its assets can change. The plan reads the setting
# back through a check block (checks.tf), and the drift run fails when a
# repo that asks for it has it off. Repos left out are not touched.
#
# Usage: immutable-releases.sh <org> [<repo>...]    (needs GH_TOKEN)

if [[ $# -lt 1 ]]; then
    echo "usage: immutable-releases.sh <org> [<repo>...]" >&2
    exit 1
fi
: "${GH_TOKEN:?GH_TOKEN must hold a token from the divbast-infra App}"

org=$1
shift

for repo in "$@"; do
    gh api -X PUT "repos/${org}/${repo}/immutable-releases" >/dev/null
done

echo "immutable releases on for $# repos"
