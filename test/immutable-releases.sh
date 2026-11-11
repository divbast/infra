#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>
set -euo pipefail

# Runs scripts/immutable-releases.sh against a fake gh that records every
# call and exits with GH_EXIT.

script="$(cd "$(dirname "$0")/.." && pwd)/scripts/immutable-releases.sh"
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
mkdir "${work}/bin"
cat > "${work}/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_LOG}"
exit "${GH_EXIT}"
FAKE
chmod +x "${work}/bin/gh"

failed=0
fail() { echo "FAIL $1: $2" >&2; failed=1; }
run() {
    : > "${work}/log"
    PATH="${work}/bin:${PATH}" GH_LOG="${work}/log" GH_TOKEN=fake GH_EXIT=$1 \
        "${script}" "${@:2}" > "${work}/out" 2> "${work}/err"
}

if ! run 0 divbast one two; then
    fail enables_each_repo "exited non-zero: $(cat "${work}/err")"
elif ! printf 'api -X PUT repos/divbast/%s/immutable-releases\n' one two | diff - "${work}/log" >&2; then
    fail enables_each_repo "gh calls differ as shown"
fi
if ! run 0 divbast || [[ -s "${work}/log" ]]; then
    fail none_asked_for "failed, or called gh"
fi
if run 1 divbast one; then fail fails_when_gh_fails "exited 0"; fi
if run 0; then fail fails_without_an_org "exited 0"; fi
grep -qi usage "${work}/err" || fail fails_without_an_org "no usage line"

[[ ${failed} -eq 0 ]] || exit 1
echo "immutable-releases: 4 cases pass"
