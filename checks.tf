# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# Settings the provider cannot manage, set by infra-settings after each
# apply and read back here, and the repository attributes provider 6.13.0
# marks optional and computed: with nothing set in config, a hand edit to
# one of those leaves no diff, so only a check here sees it. A failed
# check is a warning in a plan; the drift workflow turns any failed check
# into a red run. A repo created, or newly flagged, in the same change
# reads as 404 or off until its apply, so a PR's plan can warn about it
# without anything being wrong.

data "github_rest_api" "private_vulnerability_reporting" {
  for_each = local.repositories

  endpoint = "repos/divbast/${each.value.name}/private-vulnerability-reporting"
}

# Every repo, so that one switched on by hand shows as well as one
# switched off.
data "github_rest_api" "immutable_releases" {
  for_each = local.repositories

  endpoint = "repos/divbast/${each.value.name}/immutable-releases"
}

# Each repo's own record, for the optional and computed attributes.
data "github_rest_api" "repository" {
  for_each = local.repositories

  endpoint = "repos/divbast/${each.value.name}"
}

data "github_rest_api" "fork_pr_approval" {
  endpoint = "orgs/divbast/actions/permissions/fork-pr-contributor-approval"
}

data "github_rest_api" "code_security_defaults" {
  endpoint = "orgs/divbast/code-security/configurations/defaults"
}

locals {
  # Each repo as GitHub reports it, by slug, or null where the read did not
  # decode, which every check below counts as a difference.
  live_repositories = {
    for slug, r in data.github_rest_api.repository : slug => try(jsondecode(r.body), null)
  }

  # The names of the repos whose live settings differ from what the config
  # says, by setting.
  drifted = {
    immutable_releases = [
      for slug, r in data.github_rest_api.immutable_releases : local.repositories[slug].name
      if try(jsondecode(r.body).enabled, null) != contains(local.immutable_release_repositories, local.repositories[slug].name)
    ]
    topics = [
      for slug, live in local.live_repositories : local.repositories[slug].name
      if !try(toset(live.topics) == toset(try(local.repositories[slug].topics, [])), false)
    ]
    web_commit_signoff_required = [
      for slug, live in local.live_repositories : local.repositories[slug].name
      if try(live.web_commit_signoff_required, null) != false
    ]
    allow_forking = [
      for slug, live in local.live_repositories : local.repositories[slug].name
      if try(live.allow_forking, null) != true
    ]
    default_branch = [
      for slug, live in local.live_repositories : local.repositories[slug].name
      if try(live.default_branch, null) != "main"
    ]
  }
}

check "private_vulnerability_reporting" {
  assert {
    condition = alltrue([
      for r in data.github_rest_api.private_vulnerability_reporting :
      try(jsondecode(r.body).enabled, false)
    ])
    error_message = "Private vulnerability reporting is off on a repo; infra-settings turns it on."
  }
}

check "immutable_releases" {
  assert {
    condition     = length(local.drifted.immutable_releases) == 0
    error_message = "Immutable releases on ${join(", ", local.drifted.immutable_releases)} differ from immutable_releases in their entries in local.repositories; infra-settings turns them on where an entry sets it, and a person turns them off in the repo's settings."
  }
}

check "topics" {
  assert {
    condition     = length(local.drifted.topics) == 0
    error_message = "Topics on ${join(", ", local.drifted.topics)} differ from their entries in local.repositories; put them in the entry, or take them off by hand."
  }
}

check "web_commit_signoff_required" {
  assert {
    condition     = length(local.drifted.web_commit_signoff_required) == 0
    error_message = "Commit signoff is required on ${join(", ", local.drifted.web_commit_signoff_required)}, and nothing here asks for it; turn it off in the repo's settings."
  }
}

check "allow_forking" {
  assert {
    condition     = length(local.drifted.allow_forking) == 0
    error_message = "Forking is off on ${join(", ", local.drifted.allow_forking)}, and nothing here turns it off; turn it back on in the repo's settings."
  }
}

check "default_branch" {
  assert {
    condition     = length(local.drifted.default_branch) == 0
    error_message = "The default branch is not main on ${join(", ", local.drifted.default_branch)}; make main the default again in the repo's settings."
  }
}

check "fork_pr_approval" {
  assert {
    condition     = try(jsondecode(data.github_rest_api.fork_pr_approval.body).approval_policy, "") == "all_external_contributors"
    error_message = "Fork PRs from outside contributors no longer wait for approval; infra-settings restores it."
  }
}

check "no_default_code_security_configuration" {
  assert {
    condition     = length(try(jsondecode(data.github_rest_api.code_security_defaults.body), [])) == 0
    error_message = "A default code security configuration is set and would fight the per-repo settings; remove it by hand."
  }
}
