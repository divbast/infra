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

locals {
  # The divbast-renovate App's App ID, which is what a ruleset bypass
  # names: not its client ID, nor an installation ID.
  renovate_app_id = 5691200

  # Keyed by a stable slug, with the name separate, so renaming a repo is
  # an in-place update rather than a new resource.
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
      description     = "Security hardened Baikal OCI Image"
      required_checks = ["required"]
      renovate        = { automerge_variable = "BAIKAL_AUTOMERGE" }
    }
    librespeed = {
      name            = "librespeed-oci-image"
      description     = "Security hardened LibreSpeed OCI Image"
      auto_init       = true
      required_checks = ["required"]
      renovate        = { automerge_variable = "LIBRESPEED_AUTOMERGE" }
    }
    ci = {
      name            = "ci"
      description     = "Reusable workflows, shared tooling and the acceptance harness for divbast's repositories"
      auto_init       = true
      required_checks = ["required"]
      renovate        = { automerge_variable = "CI_AUTOMERGE" }
      # Every green merge to main is released as vX.Y.Z by the Renovate App,
      # from the main-only renovate environment, and callers pin those.
      tag_creator_app_ids = [local.renovate_app_id]
      immutable_releases  = true
    }
    renovate_config = {
      name            = "renovate-config"
      description     = "The shared Renovate preset for divbast's repositories"
      auto_init       = true
      required_checks = ["required"]
      renovate        = { automerge_variable = "RENOVATE_CONFIG_AUTOMERGE" }
    }
    frankenphp = {
      name            = "frankenphp"
      description     = "Static FrankenPHP binaries for divbast's images, one per app, built and attested in CI"
      auto_init       = true
      required_checks = ["required"]
      renovate        = { automerge_variable = "FRANKENPHP_AUTOMERGE" }
    }
  }

  # Repos whose published releases can never change. Provider 6.13.0 has
  # no attribute for it: scripts/immutable-releases.sh sets it after each
  # apply, and checks.tf reads it back.
  immutable_release_repositories = sort([
    for r in local.repositories : r.name if try(r.immutable_releases, false)
  ])
}

module "repository" {
  source   = "./modules/repository"
  for_each = local.repositories

  name = each.value.name
  # Conversion to the module's object type drops the attributes it does
  # not declare: name, and immutable_releases, which the root handles.
  settings                 = each.value
  maintainers_team_id      = module.organization.maintainers_team_id
  renovate_app_client_id   = var.renovate_app_client_id
  renovate_app_private_key = var.renovate_app_private_key
}
