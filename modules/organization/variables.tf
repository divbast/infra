# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

variable "billing_email" {
  description = "The org's billing address. GitHub requires one even on the Free plan."
  type        = string
  nullable    = false
}

variable "description" {
  description = "One line shown on the org's profile."
  type        = string
  nullable    = false
}

variable "allowed_action_patterns" {
  description = "Third-party actions allowed to run, one owner/repo@* each. GitHub's own actions are allowed separately."
  type        = list(string)
  nullable    = false

  validation {
    # A whole owner, or a tag, would admit actions nobody reviewed.
    condition     = alltrue([for p in var.allowed_action_patterns : can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+@\\*$", p))])
    error_message = "Each pattern must name one repository, as owner/repo@*."
  }
}

variable "maintainers" {
  description = "GitHub usernames in the maintainers team."
  type        = set(string)
  nullable    = false
}
