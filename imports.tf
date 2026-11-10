# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# Adopts what exists before OpenTofu manages it. Deleted after the first
# apply that runs these: tofu test cannot load a module tree containing
# import blocks (opentofu#4776), and they have no job once applied.

# Imported rather than created: the create path drops booleans set to
# false (integrations/terraform-provider-github#3493).
import {
  to = module.organization.github_organization_settings.this
  id = "327878364"
}

import {
  to = module.organization.github_actions_organization_permissions.this
  id = "divbast"
}

import {
  to = module.organization.github_actions_organization_workflow_permissions.this
  id = "divbast"
}

import {
  to = module.repository["infra"].github_repository.this
  id = "infra"
}

import {
  to = module.repository["infra"].github_repository_environment.extra["plan"]
  id = "infra:plan"
}

import {
  to = module.repository["infra"].github_repository_environment.extra["apply"]
  id = "infra:apply"
}

# Creating a policy whose pattern already exists loops forever
# (integrations/terraform-provider-github#3611), so it is imported too.
import {
  to = module.repository["infra"].github_repository_environment_deployment_policy.extra["apply"]
  id = "infra:apply:66136973"
}
