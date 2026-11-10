# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

resource "github_repository_ruleset" "default_branch" {
  name        = "default-branch"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  # Org admins may merge a PR whose checks are stuck, but nobody pushes to
  # the default branch directly. actor_id stays unset for OrganizationAdmin.
  bypass_actors {
    actor_type  = "OrganizationAdmin"
    bypass_mode = "pull_request"
  }

  rules {
    deletion            = true
    non_fast_forward    = true
    required_signatures = true

    pull_request {
      # Raised when a second maintainer joins; one person cannot review
      # their own PRs.
      required_approving_review_count = 0
      allowed_merge_methods           = ["merge", "squash"]
    }

    dynamic "required_status_checks" {
      for_each = length(var.settings.required_checks) > 0 ? [1] : []

      content {
        strict_required_status_checks_policy = true

        dynamic "required_check" {
          for_each = var.settings.required_checks

          content {
            context = required_check.value
            # The GitHub Actions app: no other integration can satisfy the
            # check, and the ruleset does not drift on a null source.
            integration_id = 15368
          }
        }
      }
    }
  }
}

resource "github_repository_ruleset" "tags" {
  name        = "tags"
  repository  = github_repository.this.name
  target      = "tag"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  bypass_actors {
    actor_type  = "OrganizationAdmin"
    bypass_mode = "always"
  }

  rules {
    creation = true
    update   = true
    deletion = true
  }
}
