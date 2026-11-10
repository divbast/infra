#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>
set -euo pipefail

# Placeholder until the workflows exist. Once they do, this fails until it
# checks them, so it can never pass vacuously over real workflows.
if [[ -d .github/workflows ]]; then
    echo "test/workflows.sh does not check the workflows yet" >&2
    exit 1
fi
echo "no workflows yet"
