# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# Preconditions, not checks: a failed check is only a warning in a plan,
# and these must fail the pull request's.

output "repositories" {
  description = "The entries, unchanged, once every key in them is one something reads."
  value       = var.repositories

  precondition {
    condition     = length(local.unknown_keys) == 0
    error_message = "local.repositories sets a key nothing reads, which OpenTofu would drop without a word: ${join(", ", local.unknown_keys)}. Fix its spelling, or add it to allowed_keys in modules/entries once something reads it."
  }
}

output "immutable_release_repositories" {
  description = "The names of the repos whose entries set immutable_releases = true, sorted."
  value       = local.immutable_release_repositories

  precondition {
    condition     = contains(local.immutable_release_repositories, "ci")
    error_message = "ci's entry in local.repositories no longer sets immutable_releases = true. Every caller pins ci's releases, and infra-settings makes a repo's releases immutable only when its entry asks."
  }
}
