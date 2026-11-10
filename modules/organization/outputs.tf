# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

output "maintainers_team_id" {
  description = "ID of the maintainers team, for repo access."
  value       = github_team.maintainers.id
}

output "maintainers_team_slug" {
  description = "Slug of the maintainers team, as CODEOWNERS spells it."
  value       = github_team.maintainers.slug
}
