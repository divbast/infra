# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

variable "repositories" {
  description = "The repos to read, by slug: each one's name, and the topics its entry sets."
  type = map(object({
    name   = string
    topics = optional(set(string), [])
  }))
  nullable = false
}

variable "immutable_release_repositories" {
  description = "The names of the repos whose entries set immutable_releases = true."
  type        = list(string)
  nullable    = false
}
