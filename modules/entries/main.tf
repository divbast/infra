# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# The entries of local.repositories as written. The root passes each one to
# the repository module, whose object type drops any key it does not
# declare without a word, so a misspelt key would change nothing on GitHub
# and no plan would show it. Here every key is still there to check.

locals {
  # Every key something reads: the repository module's settings, and the
  # root's own name and immutable_releases. A new key goes here too.
  allowed_keys = [
    "name", "description", "homepage_url", "topics", "has_issues",
    "has_discussions", "auto_init", "required_checks", "tag_creator_app_ids",
    "renovate", "environments", "immutable_releases", "is_template",
    "template",
  ]

  # Each key nothing reads, as entry.key.
  unknown_keys = sort(flatten([
    for slug, entry in var.repositories : [
      for key in keys(entry) : "${slug}.${key}" if !contains(local.allowed_keys, key)
    ]
  ]))

  immutable_release_repositories = sort([
    for r in var.repositories : r.name if try(r.immutable_releases, false)
  ])
}
