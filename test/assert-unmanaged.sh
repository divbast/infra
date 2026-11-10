#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>
set -euo pipefail

# Runs scripts/assert-unmanaged.sh against a fake gh that records every
# call and answers the one GET it makes.

script="$(cd "$(dirname "$0")/.." && pwd)/scripts/assert-unmanaged.sh"
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

mkdir "${work}/bin"
cat > "${work}/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_LOG}"
case "$*" in
    *code-security/configurations/defaults*) printf '%s\n' "${DEFAULTS_JSON}" ;;
esac
FAKE
chmod +x "${work}/bin/gh"

failed=0
fail() { echo "FAIL $1: $2" >&2; failed=1; }

run() {
    : > "${work}/log"
    PATH="${work}/bin:${PATH}" GH_LOG="${work}/log" GH_TOKEN=fake \
        DEFAULTS_JSON="$1" "${script}" "${@:2}" \
        > "${work}/out" 2> "${work}/err"
}

# sets_both_and_passes
if run '[]' divbast one two; then
    for want in \
        "api -X PUT repos/divbast/one/private-vulnerability-reporting" \
        "api -X PUT repos/divbast/two/private-vulnerability-reporting" \
        "api -X PUT orgs/divbast/actions/permissions/fork-pr-contributor-approval -f approval_policy=all_external_contributors"; do
        grep -qxF -- "${want}" "${work}/log" || fail sets_both_and_passes "no call: ${want}"
    done
else
    fail sets_both_and_passes "exited non-zero: $(cat "${work}/err")"
fi

# fails_on_a_default_configuration
if run '[{"default_for_new_repos":"all","configuration":{"name":"GitHub recommended"}}]' divbast one; then
    fail fails_on_a_default_configuration "exited 0"
elif ! grep -qF "GitHub recommended" "${work}/err"; then
    fail fails_on_a_default_configuration "stderr does not name the configuration"
fi

# fails_without_repos
if run '[]' divbast; then
    fail fails_without_repos "exited 0"
elif ! grep -qi usage "${work}/err"; then
    fail fails_without_repos "no usage line"
fi

if [[ ${failed} -ne 0 ]]; then
    exit 1
fi
echo "assert-unmanaged: 3 cases pass"
