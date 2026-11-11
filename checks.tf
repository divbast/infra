# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# Settings the provider cannot manage, set by scripts/assert-unmanaged.sh
# and scripts/immutable-releases.sh after each apply and read back here. A
# failed check is a warning in a plan; the drift workflow turns any failed
# check into a red run. A repo created, or newly flagged, in the same
# change reads as 404 or off until its apply, so a PR's plan can warn
# about it without anything being wrong.

data "github_rest_api" "private_vulnerability_reporting" {
  for_each = local.repositories

  endpoint = "repos/divbast/${each.value.name}/private-vulnerability-reporting"
}

# Only the repos that ask for immutable releases; the rest are not read.
data "github_rest_api" "immutable_releases" {
  for_each = toset(local.immutable_release_repositories)

  endpoint = "repos/divbast/${each.value}/immutable-releases"
}

data "github_rest_api" "fork_pr_approval" {
  endpoint = "orgs/divbast/actions/permissions/fork-pr-contributor-approval"
}

data "github_rest_api" "code_security_defaults" {
  endpoint = "orgs/divbast/code-security/configurations/defaults"
}

check "private_vulnerability_reporting" {
  assert {
    condition = alltrue([
      for r in data.github_rest_api.private_vulnerability_reporting :
      try(jsondecode(r.body).enabled, false)
    ])
    error_message = "Private vulnerability reporting is off on a repo; scripts/assert-unmanaged.sh turns it on."
  }
}

check "immutable_releases" {
  assert {
    condition = alltrue([
      for r in data.github_rest_api.immutable_releases :
      try(jsondecode(r.body).enabled, false)
    ])
    error_message = "Immutable releases are off on a repo that asks for them; scripts/immutable-releases.sh turns them on."
  }
}

check "fork_pr_approval" {
  assert {
    condition     = try(jsondecode(data.github_rest_api.fork_pr_approval.body).approval_policy, "") == "all_external_contributors"
    error_message = "Fork PRs from outside contributors no longer wait for approval; scripts/assert-unmanaged.sh restores it."
  }
}

check "no_default_code_security_configuration" {
  assert {
    condition     = length(try(jsondecode(data.github_rest_api.code_security_defaults.body), [])) == 0
    error_message = "A default code security configuration is set and would fight the per-repo settings; remove it by hand."
  }
}
