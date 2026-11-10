# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

mock_provider "github" {}

variables {
  name                     = "example"
  settings                 = { description = "Example" }
  maintainers_team_id      = "42"
  renovate_app_client_id   = "Iv1.test"
  renovate_app_private_key = "test-key"
}

run "defaults_are_the_baseline" {
  command = plan

  assert {
    condition     = github_repository.this.visibility == "public"
    error_message = "Every divbast repo is public: private repos would be billed."
  }
  assert {
    # The provider has no default for these, and an adopted repo loses
    # whichever one is left out.
    condition = alltrue([
      github_repository.this.has_issues == true,
      github_repository.this.has_wiki == false,
      github_repository.this.has_projects == false,
      github_repository.this.has_discussions == false,
    ])
    error_message = "Issues on; wiki, projects and discussions off, each set explicitly."
  }
  assert {
    condition = alltrue([
      github_repository.this.allow_merge_commit == true,
      github_repository.this.allow_squash_merge == true,
      github_repository.this.allow_rebase_merge == false,
      github_repository.this.allow_auto_merge == false,
    ])
    error_message = "Merge commits and squash only: GitHub cannot sign a rebase."
  }
  assert {
    condition = alltrue([
      github_repository.this.squash_merge_commit_title == "COMMIT_OR_PR_TITLE",
      github_repository.this.squash_merge_commit_message == "COMMIT_MESSAGES",
    ])
    error_message = "A one-commit squash must keep that commit's subject, body and trailers."
  }
  assert {
    condition = alltrue([
      github_repository.this.delete_branch_on_merge == true,
      github_repository.this.allow_update_branch == true,
      github_repository.this.archive_on_destroy == true,
    ])
    error_message = "Branches go on merge, PRs can be updated, and a destroy archives."
  }
  assert {
    condition = alltrue([
      github_repository.this.security_and_analysis[0].secret_scanning[0].status == "enabled",
      github_repository.this.security_and_analysis[0].secret_scanning_push_protection[0].status == "enabled",
    ])
    error_message = "Secret scanning and push protection on."
  }
  assert {
    condition     = github_repository_vulnerability_alerts.this.enabled == true
    error_message = "Dependabot alerts on."
  }
  assert {
    condition     = github_repository_dependabot_security_updates.this.enabled == false
    error_message = "Renovate does the updates, not Dependabot."
  }
  assert {
    condition     = github_team_repository.maintainers.permission == "maintain"
    error_message = "The maintainers team maintains the repo."
  }
}

run "default_branch_ruleset" {
  command = plan

  assert {
    condition = alltrue([
      github_repository_ruleset.default_branch.target == "branch",
      github_repository_ruleset.default_branch.enforcement == "active",
      github_repository_ruleset.default_branch.conditions[0].ref_name[0].include == tolist(["~DEFAULT_BRANCH"]),
    ])
    error_message = "An active ruleset on the default branch."
  }
  assert {
    condition = alltrue([
      github_repository_ruleset.default_branch.rules[0].deletion == true,
      github_repository_ruleset.default_branch.rules[0].non_fast_forward == true,
      github_repository_ruleset.default_branch.rules[0].required_signatures == true,
    ])
    error_message = "No deletion, no force push, signed commits only."
  }
  assert {
    condition = alltrue([
      github_repository_ruleset.default_branch.rules[0].pull_request[0].required_approving_review_count == 0,
      toset(github_repository_ruleset.default_branch.rules[0].pull_request[0].allowed_merge_methods) == toset(["merge", "squash"]),
    ])
    error_message = "A PR is required, with no approvals while there is one maintainer, merged by merge commit or squash."
  }
  assert {
    condition = alltrue([
      length(github_repository_ruleset.default_branch.bypass_actors) == 1,
      github_repository_ruleset.default_branch.bypass_actors[0].actor_type == "OrganizationAdmin",
      github_repository_ruleset.default_branch.bypass_actors[0].bypass_mode == "pull_request",
    ])
    error_message = "Only org admins bypass, and only by merging a PR."
  }
}

run "required_checks_come_from_actions" {
  command = plan

  variables {
    settings = { description = "x", required_checks = ["required", "plan"] }
  }

  assert {
    condition     = github_repository_ruleset.default_branch.rules[0].required_status_checks[0].strict_required_status_checks_policy == true
    error_message = "A branch must be up to date with main before it merges."
  }
  assert {
    condition     = toset([for c in github_repository_ruleset.default_branch.rules[0].required_status_checks[0].required_check : c.context]) == toset(["required", "plan"])
    error_message = "Exactly the named checks are required."
  }
  assert {
    condition     = alltrue([for c in github_repository_ruleset.default_branch.rules[0].required_status_checks[0].required_check : c.integration_id == 15368])
    error_message = "Each check must come from GitHub Actions, so nothing else can satisfy it."
  }
}

run "no_checks_no_status_rule" {
  command = plan

  variables {
    settings = { description = "x", required_checks = [] }
  }

  assert {
    condition     = length(github_repository_ruleset.default_branch.rules[0].required_status_checks) == 0
    error_message = "A repo without CI has no status-check rule."
  }
}

run "tags_are_admin_only" {
  command = plan

  assert {
    condition = alltrue([
      github_repository_ruleset.tags.target == "tag",
      github_repository_ruleset.tags.conditions[0].ref_name[0].include == tolist(["~ALL"]),
      github_repository_ruleset.tags.rules[0].creation == true,
      github_repository_ruleset.tags.rules[0].update == true,
      github_repository_ruleset.tags.rules[0].deletion == true,
    ])
    error_message = "Every tag is created, moved and deleted by bypass only."
  }
  assert {
    condition = alltrue([
      length(github_repository_ruleset.tags.bypass_actors) == 1,
      github_repository_ruleset.tags.bypass_actors[0].actor_type == "OrganizationAdmin",
      github_repository_ruleset.tags.bypass_actors[0].bypass_mode == "always",
    ])
    error_message = "Only org admins touch tags."
  }
}

run "renovate_environment_is_main_only" {
  command = plan

  variables {
    settings = { description = "x", renovate = { automerge_variable = "BAIKAL_AUTOMERGE" } }
  }

  assert {
    condition     = github_repository_environment.renovate.environment == "renovate"
    error_message = "Renovate's key lives in an environment called renovate."
  }
  assert {
    condition     = github_repository_environment_deployment_policy.renovate.branch_pattern == "main"
    error_message = "Only main may deploy to the renovate environment."
  }
  assert {
    condition = alltrue([
      github_actions_environment_variable.renovate_client_id.variable_name == "RENOVATE_APP_CLIENT_ID",
      github_actions_environment_variable.renovate_client_id.value == "Iv1.test",
      github_actions_environment_secret.renovate_private_key.secret_name == "RENOVATE_APP_PRIVATE_KEY",
    ])
    error_message = "The App's client ID and key land under the names renovate.yml reads."
  }
  assert {
    condition = alltrue([
      github_actions_variable.automerge.variable_name == "BAIKAL_AUTOMERGE",
      github_actions_variable.automerge.value == "enabled",
    ])
    error_message = "The kill switch is created enabled."
  }
}

run "no_renovate_no_environment" {
  command = plan

  assert {
    condition = alltrue([
      github_repository_environment.renovate == null,
      github_repository_environment_deployment_policy.renovate == null,
      github_actions_environment_variable.renovate_client_id == null,
      github_actions_environment_secret.renovate_private_key == null,
      github_actions_variable.automerge == null,
    ])
    error_message = "A repo without Renovate gets none of its resources."
  }
}

run "extra_environments" {
  command = plan

  variables {
    settings = { description = "x", environments = { apply = { main_only = true }, plan = { main_only = false } } }
  }

  assert {
    condition     = toset(keys(github_repository_environment.extra)) == toset(["apply", "plan"])
    error_message = "Both environments are planned."
  }
  assert {
    condition = alltrue([
      keys(github_repository_environment_deployment_policy.extra) == ["apply"],
      github_repository_environment_deployment_policy.extra["apply"].branch_pattern == "main",
    ])
    error_message = "Only a main-only environment gets a deployment policy, for main."
  }
}

run "rejects_a_bad_name" {
  command = plan

  variables {
    name = "bad name"
  }

  expect_failures = [var.name]
}
