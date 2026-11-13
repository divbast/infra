# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

set shell := ["mise", "exec", "--", "bash", "-euo", "pipefail", "-c"]

# Tool versions live in mise.toml

default:
    @just --list

setup:
    #!/usr/bin/env bash
    # The one recipe that must not run through `mise exec`: it installs mise's tools
    set -euo pipefail
    mise install

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

# Verify every action is a SHA. The workflow recipes skip until .github/workflows
# exists; internal/repotest then fails if any expected workflow is missing
actions-check:
    if [[ -d .github/workflows ]]; then GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token)}" pinact run --verify --check; else echo "no workflows yet"; fi

# Rewrite tag references to the SHA
actions-pin:
    GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token)}" pinact run

# Move every action to its latest release
actions-update:
    GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token)}" pinact run --update

workflow-audit:
    if [[ -d .github/workflows ]]; then GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token)}" zizmor --persona=auditor .github/workflows; else echo "no workflows yet"; fi

actionlint:
    if [[ -d .github/workflows ]]; then actionlint; else echo "no workflows yet"; fi

# Untracked scripts count too, so a new script is linted before its first commit
shellcheck:
    git ls-files --cached --others --exclude-standard '*.sh' | xargs -r shellcheck

# Every test script under test/
scripts-test:
    #!/usr/bin/env -S mise exec -- bash
    set -euo pipefail
    shopt -s nullglob
    for t in test/*.sh; do
        echo "== ${t}"
        bash "${t}"
    done

# The Go tests, under the race detector. internal/repotest reads the
# module's graph, so it needs `just init` first
go-test:
    go test -race -count=1 ./...

lint: fmt-check init validate tflint actionlint workflow-audit actions-check shellcheck
    reuse lint

ci: lint test scripts-test go-test
