# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

mock_provider "github" {}

variables {
  billing_email           = "billing@example.test"
  description             = "test"
  allowed_action_patterns = ["jdx/mise-action@*"]
  maintainers             = ["octocat"]
}

run "actions_policy_is_an_allowlist" {
  command = plan

  assert {
    condition     = github_actions_organization_permissions.this.allowed_actions == "selected"
    error_message = "Only listed actions may run."
  }
  assert {
    condition     = github_actions_organization_permissions.this.enabled_repositories == "all"
    error_message = "Actions must stay enabled for every repo."
  }
  assert {
    condition     = github_actions_organization_permissions.this.sha_pinning_required == true
    error_message = "Every action must be pinned to a full SHA."
  }
  assert {
    condition     = github_actions_organization_permissions.this.allowed_actions_config[0].github_owned_allowed == true
    error_message = "GitHub's own actions must be allowed."
  }
  assert {
    condition     = github_actions_organization_permissions.this.allowed_actions_config[0].verified_allowed == false
    error_message = "Verified-creator actions must not be allowed wholesale."
  }
  assert {
    condition     = toset(github_actions_organization_permissions.this.allowed_actions_config[0].patterns_allowed) == toset(["jdx/mise-action@*"])
    error_message = "The allowlist must be exactly the patterns given."
  }
}

run "workflow_token_is_read_only" {
  command = plan

  assert {
    condition     = github_actions_organization_workflow_permissions.this.default_workflow_permissions == "read"
    error_message = "GITHUB_TOKEN must default to read-only."
  }
  assert {
    condition     = github_actions_organization_workflow_permissions.this.can_approve_pull_request_reviews == false
    error_message = "Actions must not approve pull requests."
  }
}

run "members_cannot_make_repos" {
  command = plan

  assert {
    condition     = github_organization_settings.this.default_repository_permission == "none"
    error_message = "Members get no access by default."
  }
  assert {
    condition = alltrue([
      github_organization_settings.this.members_can_create_repositories == false,
      github_organization_settings.this.members_can_create_public_repositories == false,
      github_organization_settings.this.members_can_create_private_repositories == false,
    ])
    error_message = "Repos come only from OpenTofu."
  }
  assert {
    condition     = github_organization_settings.this.members_can_create_pages == false
    error_message = "Members must not create Pages sites."
  }
  assert {
    condition     = github_organization_settings.this.members_can_fork_private_repositories == false
    error_message = "Members must not fork private repos."
  }
}

run "new_repos_get_security_defaults" {
  command = plan

  assert {
    condition = alltrue([
      github_organization_settings.this.secret_scanning_enabled_for_new_repositories,
      github_organization_settings.this.secret_scanning_push_protection_enabled_for_new_repositories,
      github_organization_settings.this.dependabot_alerts_enabled_for_new_repositories,
      github_organization_settings.this.dependency_graph_enabled_for_new_repositories,
    ])
    error_message = "New repos must get secret scanning, push protection, Dependabot alerts and the dependency graph."
  }
  assert {
    condition     = github_organization_settings.this.dependabot_security_updates_enabled_for_new_repositories == false
    error_message = "Renovate does the updates, not Dependabot."
  }
}

run "maintainers_team_is_closed" {
  command = plan

  assert {
    condition     = github_team.maintainers.privacy == "closed"
    error_message = "A secret team can be neither a bypass actor nor a code owner."
  }
  assert {
    condition     = github_team_membership.maintainers["octocat"].role == "maintainer"
    error_message = "Each listed maintainer joins the team as a maintainer."
  }
}

run "rejects_a_floating_pattern" {
  command = plan

  variables {
    allowed_action_patterns = ["jdx/*"]
  }

  expect_failures = [var.allowed_action_patterns]
}
