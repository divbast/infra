# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# A repo that builds on Docker Hardened Images (dhi.io) logs in with these:
# ci's app-check.yml and renovate.yml take them as the input dhi-username
# and the secret DHI_TOKEN.

resource "github_actions_secret" "dhi_token" {
  repository  = github_repository.this.name
  secret_name = "DHI_TOKEN"
  value       = var.dhi_token

  lifecycle {
    enabled = var.settings.dhi
    precondition {
      condition     = var.dhi_token != "" && var.dhi_username != ""
      error_message = "an entry with dhi = true needs DHI_TOKEN and DHI_USERNAME in infra's environments"
    }
  }
}

resource "github_actions_variable" "dhi_username" {
  repository    = github_repository.this.name
  variable_name = "DHI_USERNAME"
  value         = var.dhi_username

  lifecycle {
    enabled = var.settings.dhi
    precondition {
      condition     = var.dhi_token != "" && var.dhi_username != ""
      error_message = "an entry with dhi = true needs DHI_TOKEN and DHI_USERNAME in infra's environments"
    }
  }
}
