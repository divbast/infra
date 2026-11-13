# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

output "drifted" {
  description = "The names of the repos whose live settings differ from the config, by setting: the repos each failed check names."
  value       = local.drifted
}
