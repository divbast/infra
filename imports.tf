# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# Adopts baikal-oci-image, transferred in with its Renovate wiring already
# set up by hand. Deleted after the apply that runs these: tofu test cannot
# load a module tree containing import blocks (opentofu#4776), and they
# have no job once applied.

import {
  to = module.repository["baikal"].github_repository.this
  id = "baikal-oci-image"
}

import {
  to = module.repository["baikal"].github_repository_environment.renovate
  id = "baikal-oci-image:renovate"
}

# Creating a policy whose pattern already exists loops forever
# (integrations/terraform-provider-github#3611), so it is imported too.
import {
  to = module.repository["baikal"].github_repository_environment_deployment_policy.renovate
  id = "baikal-oci-image:renovate:63642532"
}

# Creating a variable that exists fails, so both are imported. The kill
# switch keeps its value: the module ignores changes to it.
import {
  to = module.repository["baikal"].github_actions_variable.automerge
  id = "baikal-oci-image:BAIKAL_AUTOMERGE"
}

import {
  to = module.repository["baikal"].github_actions_environment_variable.renovate_client_id
  id = "baikal-oci-image:renovate:RENOVATE_APP_CLIENT_ID"
}

# The value cannot be read back, so the plan rewrites it with the org
# App's key.
import {
  to = module.repository["baikal"].github_actions_environment_secret.renovate_private_key
  id = "baikal-oci-image:renovate:RENOVATE_APP_PRIVATE_KEY"
}
