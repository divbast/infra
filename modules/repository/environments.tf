# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

locals {
  renovate = var.settings.renovate != null
  # Read through try() so a disabled instance still evaluates.
  automerge_variable = try(var.settings.renovate.automerge_variable, "")
  main_only_environments = {
    for name, env in var.settings.environments : name => env if env.main_only
  }
}

resource "github_repository_environment" "extra" {
  for_each = var.settings.environments

  repository  = github_repository.this.name
  environment = each.key

  dynamic "deployment_branch_policy" {
    for_each = each.value.main_only ? [1] : []

    content {
      protected_branches     = false
      custom_branch_policies = true
    }
  }
}

resource "github_repository_environment_deployment_policy" "extra" {
  for_each = local.main_only_environments

  repository     = github_repository.this.name
  environment    = github_repository_environment.extra[each.key].environment
  branch_pattern = "main"
}

# Renovate's App key, readable only by workflows running on main.
resource "github_repository_environment" "renovate" {
  repository  = github_repository.this.name
  environment = "renovate"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }

  lifecycle {
    enabled = local.renovate
  }
}

resource "github_repository_environment_deployment_policy" "renovate" {
  repository     = github_repository.this.name
  environment    = "renovate"
  branch_pattern = "main"

  depends_on = [github_repository_environment.renovate]

  lifecycle {
    enabled = local.renovate
  }
}

resource "github_actions_environment_variable" "renovate_client_id" {
  repository    = github_repository.this.name
  environment   = "renovate"
  variable_name = "RENOVATE_APP_CLIENT_ID"
  value         = var.renovate_app_client_id

  depends_on = [github_repository_environment.renovate]

  lifecycle {
    enabled = local.renovate
  }
}

resource "github_actions_environment_secret" "renovate_private_key" {
  repository  = github_repository.this.name
  environment = "renovate"
  secret_name = "RENOVATE_APP_PRIVATE_KEY"
  value       = var.renovate_app_private_key

  depends_on = [github_repository_environment.renovate]

  lifecycle {
    enabled = local.renovate
  }
}

# Renovate merges only while this reads `enabled`.
resource "github_actions_variable" "automerge" {
  repository    = github_repository.this.name
  variable_name = local.automerge_variable
  value         = "enabled"

  lifecycle {
    enabled = local.renovate
    # The kill switch is flipped by hand in an incident, and an apply must
    # never turn automerge back on. The one documented drift exception.
    ignore_changes = [value]
  }
}
