# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

resource "github_organization_settings" "this" {
  billing_email = var.billing_email
  name          = "divbast"
  description   = var.description

  # Repos come only from OpenTofu, and members get nothing by default.
  default_repository_permission           = "none"
  members_can_create_repositories         = false
  members_can_create_public_repositories  = false
  members_can_create_private_repositories = false
  members_can_create_pages                = false
  members_can_create_public_pages         = false
  members_can_create_private_pages        = false
  members_can_fork_private_repositories   = false
  web_commit_signoff_required             = false
  has_organization_projects               = false
  has_repository_projects                 = false

  # Defaults for repos created later. Renovate, not Dependabot, does the
  # updates. Advanced security is left unset: public repos always have it.
  secret_scanning_enabled_for_new_repositories                 = true
  secret_scanning_push_protection_enabled_for_new_repositories = true
  dependabot_alerts_enabled_for_new_repositories               = true
  dependency_graph_enabled_for_new_repositories                = true
  dependabot_security_updates_enabled_for_new_repositories     = false

  lifecycle {
    # Destroying this resource sets billing_email to email@example.com.
    prevent_destroy = true
  }
}

resource "github_actions_organization_permissions" "this" {
  enabled_repositories = "all"
  allowed_actions      = "selected"
  sha_pinning_required = true

  allowed_actions_config {
    github_owned_allowed = true
    verified_allowed     = false
    patterns_allowed     = var.allowed_action_patterns
  }

  lifecycle {
    # Destroying this resource lets every action run again, unpinned.
    prevent_destroy = true
  }
}

resource "github_actions_organization_workflow_permissions" "this" {
  organization_slug                = "divbast"
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false

  lifecycle {
    # Destroying this resource resets the token defaults GitHub chooses.
    prevent_destroy = true
  }
}

resource "github_team" "maintainers" {
  name        = "maintainers"
  description = "Maintain every divbast repository"
  # A secret team can be neither a ruleset bypass actor nor a code owner.
  privacy = "closed"
}

resource "github_team_membership" "maintainers" {
  for_each = var.maintainers

  team_id  = github_team.maintainers.id
  username = each.value
  role     = "maintainer"
}
