# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# What a plan cannot compare, read back from GitHub for the checks in
# checks.tf: the settings the provider cannot manage, which infra-settings
# sets after each apply, and the repository attributes provider 6.13.0
# marks optional and computed, where a hand edit to one the config leaves
# unset or empty shows no diff. A failed check is a warning in a plan; the
# drift workflow turns any failed check into a red run. A repo created, or
# newly flagged, in the same change reads as 404 or off until its apply,
# so a PR's plan can warn about it without anything being wrong.

data "github_rest_api" "private_vulnerability_reporting" {
  for_each = var.repositories

  endpoint = "repos/divbast/${each.value.name}/private-vulnerability-reporting"
}

# Every repo, so that one switched on by hand shows as well as one
# switched off.
data "github_rest_api" "immutable_releases" {
  for_each = var.repositories

  endpoint = "repos/divbast/${each.value.name}/immutable-releases"
}

# Each repo's own record, for the optional and computed attributes.
data "github_rest_api" "repository" {
  for_each = var.repositories

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
  # decode, which every check on it counts as a difference.
  live_repositories = {
    for slug, r in data.github_rest_api.repository : slug => try(jsondecode(r.body), null)
  }

  # The names of the repos whose live settings differ from what the config
  # says, by setting.
  drifted = {
    private_vulnerability_reporting = [
      for slug, r in data.github_rest_api.private_vulnerability_reporting : var.repositories[slug].name
      if try(jsondecode(r.body).enabled, null) != true
    ]
    immutable_releases = [
      for slug, r in data.github_rest_api.immutable_releases : var.repositories[slug].name
      if try(jsondecode(r.body).enabled, null) != contains(var.immutable_release_repositories, var.repositories[slug].name)
    ]
    topics = [
      for slug, live in local.live_repositories : var.repositories[slug].name
      # Sorted lists, since an empty set of strings never equals the
      # empty set jsondecode gives.
      if !try(sort(live.topics) == sort(var.repositories[slug].topics), false)
    ]
    web_commit_signoff_required = [
      for slug, live in local.live_repositories : var.repositories[slug].name
      if try(live.web_commit_signoff_required, null) != false
    ]
    allow_forking = [
      for slug, live in local.live_repositories : var.repositories[slug].name
      if try(live.allow_forking, null) != true
    ]
    default_branch = [
      for slug, live in local.live_repositories : var.repositories[slug].name
      if try(live.default_branch, null) != "main"
    ]
  }
}
