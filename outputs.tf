# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

output "repository_names" {
  description = "Every managed repository, for the post-apply script."
  value       = sort([for r in module.repository : r.name])
}
