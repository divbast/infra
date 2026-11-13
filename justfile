# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

set shell := ["mise", "exec", "--", "bash", "-euo", "pipefail", "-c"]

# actions-check, actions-pin, actions-update, workflow-audit, actionlint,
# shell-lint, go-lint, go-test and reuse-lint come from divbast/ci's
# common.just. Each is run from a recipe's body, never named as a
# dependency, so `just setup` still runs before .ci exists.
import? '.ci/just/common.just'

# Tool versions live in mise.toml

default:
    @just --list

# Fetch divbast/ci at the commit the workflows pin, then install the toolchain
setup: ci-checkout
    #!/usr/bin/env bash
    # Not through the mise exec shell: this is what installs what it runs
    set -euo pipefail
    mise install

# Fetch divbast/ci at the commit the workflows pin, into .ci, and nothing else
ci-checkout:
    #!/usr/bin/env bash
    # Not through the mise exec shell, which would first install what is missing
    set -euo pipefail
    # The one commit the workflows call divbast/ci at, spelt in any case
    uses="^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*[\"']?divbast/ci/[^@[:space:]\"']+@[^[:space:]\"'#]+"
    sha=$(grep -hoiE "${uses}" .github/workflows/*.y*ml | sed 's/.*@//' | sort -u | paste -sd ' ' - || true)
    if [[ ! "${sha}" =~ ^[0-9a-f]{40}$ ]]; then
        echo "ci-checkout: the workflows must call divbast/ci at one full commit SHA, not at: ${sha:-none}" >&2
        exit 1
    elif [[ "$(git -C .ci rev-parse HEAD 2>/dev/null || true)" == "${sha}" ]]; then
        echo "ci-checkout: .ci is already at ${sha}"
        exit 0
    fi
    changed=$([[ ! -e .ci/.git ]] || git -C .ci status --porcelain)
    if [[ -n "${changed}" ]]; then
        printf 'ci-checkout: moving .ci to %s would carry its own changes across, or stop on them; save or discard them first:\n%s\n' "${sha}" "${changed}" >&2
        exit 1
    fi
    git init -q .ci
    git -C .ci fetch -q --depth 1 https://github.com/divbast/ci "${sha}"
    git -C .ci checkout -q FETCH_HEAD && rm -rf .ci/bin

# Rewrite every file into canonical style
fmt:
    tofu fmt -recursive

fmt-check:
    tofu fmt -check -recursive -diff

# Fetch providers for the root and every module, never touching state
init:
    #!/usr/bin/env -S mise exec -- bash
    set -euo pipefail
    shopt -s nullglob
    for dir in . modules/*/; do
        tofu -chdir="${dir}" init -backend=false -input=false >/dev/null
    done

validate:
    #!/usr/bin/env -S mise exec -- bash
    set -euo pipefail
    shopt -s nullglob
    for dir in . modules/*/; do
        tofu -chdir="${dir}" validate
    done

# --recursive lints each module on its own as well as through the root
tflint:
    tflint --recursive --config "$(pwd)/.tflint.hcl"

# The modules carry the logic and the tests; the root holds imports, which
# tofu test cannot load (opentofu#4776)
test:
    #!/usr/bin/env -S mise exec -- bash
    set -euo pipefail
    shopt -s nullglob
    for dir in modules/*/; do
        if [[ -d "${dir}tests" ]]; then
            tofu -chdir="${dir}" test
        fi
    done

# Every lint gate, and the tests: CI runs this recipe through divbast/ci's
# lint.yml, so the tests gate every pull request. init comes first, since
# validate and the Go tests, which read the module's graph, need the
# providers it installs
lint: init
    {{ just_executable() }} ci-fresh actions-check workflow-audit actionlint shell-lint reuse-lint fmt-check validate tflint test go-lint go-test

# Every gate. Run before committing
ci: lint
