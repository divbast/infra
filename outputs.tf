# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

output "repository_names" {
  description = "Every managed repository, for infra-settings."
  value       = sort([for r in module.repository : r.name])
}

output "immutable_release_repositories" {
  description = "Repositories whose releases are immutable, for infra-settings."
  value       = local.immutable_release_repositories
}
