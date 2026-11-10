# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

resource "github_repository" "this" {
  name         = var.name
  description  = var.settings.description
  homepage_url = var.settings.homepage_url
  topics       = var.settings.topics
  auto_init    = var.settings.auto_init

  # Private repos are billed; every divbast repo is public.
  visibility = "public"

  # The provider has no default for these, and an adopted repo loses any
  # feature left unset, so each is stated.
  has_issues      = var.settings.has_issues
  has_discussions = var.settings.has_discussions
  has_wiki        = false
  has_projects    = false

  # Rebase merges are unsigned, and main requires signatures. A one-commit
  # squash keeps that commit's subject, body and trailers.
  allow_merge_commit          = true
  allow_squash_merge          = true
  allow_rebase_merge          = false
  allow_auto_merge            = false
  squash_merge_commit_title   = "COMMIT_OR_PR_TITLE"
  squash_merge_commit_message = "COMMIT_MESSAGES"

  delete_branch_on_merge = true
  allow_update_branch    = true
  archive_on_destroy     = true

  # Only these two: 6.13.0 never sends the other toggles, so setting them
  # is a permanent diff (integrations/terraform-provider-github#3501).
  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }

  lifecycle {
    # Removing a repo from the config forgets it rather than deleting it;
    # archive_on_destroy is the backstop if it is ever destroyed anyway.
    destroy = false
  }
}

resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = true
}

resource "github_repository_dependabot_security_updates" "this" {
  repository = github_repository.this.name
  # Renovate does the updates.
  enabled = false
}

resource "github_team_repository" "maintainers" {
  repository = github_repository.this.name
  team_id    = var.maintainers_team_id
  permission = "maintain"
}
