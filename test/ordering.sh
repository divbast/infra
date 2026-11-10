#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>
set -euo pipefail

# Orderings GitHub enforces and the provider does not know about. Without
# an edge in the graph, tofu runs the two resources in parallel and the
# apply fails half-way. Reads the module's graph, so it needs `just init`.

graph=$(tofu -chdir=modules/repository graph)

# GitHub refuses to configure Dependabot security updates while the repo's
# vulnerability alerts are off (422), and an adopted repo can arrive with
# them off: baikal-oci-image did.
edge='"[root] github_repository_dependabot_security_updates.this (expand)" -> "[root] github_repository_vulnerability_alerts.this (expand)"'
if ! grep -qF -- "${edge}" <<<"${graph}"; then
    echo "github_repository_dependabot_security_updates does not wait for github_repository_vulnerability_alerts" >&2
    exit 1
fi

echo "every ordering GitHub enforces is in the graph"
