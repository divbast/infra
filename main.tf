# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

module "organization" {
  source = "./modules/organization"

  billing_email = "github@aryan.ameri.coffee"
  description   = "Hardened container images of self-hosted open-source apps"
  allowed_action_patterns = [
    for line in split("\n", trimspace(file("${path.module}/actions-allowlist.txt"))) :
    line if line != "" && !startswith(line, "#")
  ]
  maintainers = ["aryonoco"]
}

# Keyed by a stable slug, with the name separate, so renaming a repo is an
# in-place update rather than a new resource.
locals {
  repositories = {
    infra = {
      name            = "infra"
      description     = "OpenTofu for the divbast organisation"
      required_checks = ["required", "plan"]
      renovate        = { automerge_variable = "INFRA_AUTOMERGE" }
      # Their secrets are set by hand: OpenTofu would need its own key as
      # an input to manage the credentials it runs with.
      environments = {
        plan  = { main_only = false }
        apply = { main_only = true }
      }
    }
    github = {
      name        = ".github"
      description = "divbast's profile and community health defaults"
      auto_init   = true
      # GitHub reserves variable names starting with GITHUB_.
      renovate = { automerge_variable = "DOTGITHUB_AUTOMERGE" }
    }
    baikal = {
      name            = "baikal-oci-image"
      description     = "Baikal OCI Image using FrankenPHP + distroless debian. Security hardened: zero capabilities, read-only root, no shell"
      required_checks = ["required"]
      renovate        = { automerge_variable = "BAIKAL_AUTOMERGE" }
    }
    librespeed = {
      name            = "librespeed-oci-image"
      description     = "LibreSpeed OCI Image using FrankenPHP + distroless debian. Security hardened: zero capabilities, read-only root, no shell"
      auto_init       = true
      required_checks = ["required"]
      renovate        = { automerge_variable = "LIBRESPEED_AUTOMERGE" }
    }
  }
}

module "repository" {
  source   = "./modules/repository"
  for_each = local.repositories

  name = each.value.name
  # Conversion to the module's object type drops the extra name attribute.
  settings                 = each.value
  maintainers_team_id      = module.organization.maintainers_team_id
  renovate_app_client_id   = var.renovate_app_client_id
  renovate_app_private_key = var.renovate_app_private_key
}
