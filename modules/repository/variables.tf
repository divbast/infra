# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

variable "name" {
  description = "The repository's name on GitHub."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.name))
    error_message = "A repository name is letters, digits, dots, hyphens and underscores."
  }
}

variable "settings" {
  description = "What differs between repos. Everything else is the divbast baseline."
  type = object({
    description     = string
    homepage_url    = optional(string)
    topics          = optional(set(string), [])
    has_issues      = optional(bool, true)
    has_discussions = optional(bool, false)
    auto_init       = optional(bool, false)
    # Marks the repo as a template others can be created from.
    is_template = optional(bool, false)
    # Create the repo from a template. Only an entry that creates a new repo
    # may set it: the provider reads it on create alone, so on an existing
    # repo it shows a diff in every plan.
    template = optional(object({
      owner      = string
      repository = string
    }))
    # Job names whose checks must pass before a PR merges. Empty for a repo
    # with no CI.
    required_checks = optional(list(string), ["required"])
    # App IDs of the GitHub Apps that may create tags here. Moving or
    # deleting a tag stays with org admins whatever is listed.
    tag_creator_app_ids = optional(list(number), [])
    # The repo-variable name of Renovate's kill switch. Null: no Renovate.
    renovate = optional(object({
      automerge_variable = string
    }))
    # Further environments, holding secrets set by hand. main_only limits
    # deployments to main.
    environments = optional(map(object({
      main_only = bool
    })), {})
  })
  nullable = false
}

variable "maintainers_team_id" {
  description = "ID of the team that maintains every repo."
  type        = string
  nullable    = false
}

variable "renovate_app_client_id" {
  description = "Client ID of the divbast-renovate App."
  type        = string
  nullable    = false
}

variable "renovate_app_private_key" {
  description = "Private key of the divbast-renovate App."
  type        = string
  sensitive   = true
  nullable    = false
}
