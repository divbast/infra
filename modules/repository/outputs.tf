# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

output "name" {
  description = "The repository's name."
  value       = github_repository.this.name
}

output "repo_id" {
  description = "The repository's numeric ID."
  value       = github_repository.this.repo_id
}
