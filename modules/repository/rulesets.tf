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

# Bypass is per ruleset, not per rule, so tags take two rulesets: an App
# can then be let create tags without being let move or delete them.
resource "github_repository_ruleset" "tag_creation" {
  name        = "tag-creation"
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

  # An Integration's actor_id is the App ID (GET /apps/<slug>), not an
  # installation ID.
  dynamic "bypass_actors" {
    for_each = var.settings.tag_creator_app_ids

    content {
      actor_type  = "Integration"
      actor_id    = bypass_actors.value
      bypass_mode = "always"
    }
  }

  rules {
    creation = true
  }
}

# A tag, once it exists, is moved or deleted by an org admin or not at all.
# Never give this ruleset another bypass actor.
resource "github_repository_ruleset" "tag_update_deletion" {
  name        = "tag-update-deletion"
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
    update   = true
    deletion = true
  }

  # This ruleset drops creation only once tag_creation exists, so no apply
  # leaves tag creation open while the rule moves between them.
  depends_on = [github_repository_ruleset.tag_creation]
}

# The one tags ruleset before the split. It keeps its GitHub ID and its
# bypass list, and loses only its creation rule. Delete this block after
# the apply that runs it.
moved {
  from = github_repository_ruleset.tags
  to   = github_repository_ruleset.tag_update_deletion
}
