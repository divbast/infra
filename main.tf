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
      description     = "The shared Renovate presets for divbast's repositories"
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
    oci_image_template = {
      name            = "oci-image-template"
      description     = "A minimal working app to start a new divbast image from"
      auto_init       = true
      is_template     = true
      required_checks = ["required"]
      renovate        = { automerge_variable = "OCI_IMAGE_TEMPLATE_AUTOMERGE" }
      dhi             = true
    }
    writefreely = {
      name            = "writefreely-oci-image"
      description     = "Security hardened WriteFreely OCI Image"
      required_checks = ["required"]
      renovate        = { automerge_variable = "WRITEFREELY_AUTOMERGE" }
      template        = { owner = "divbast", repository = "oci-image-template" }
      dhi             = true
    }
    prowlarr = {
      name            = "prowlarr-oci-image"
      description     = "Security hardened Prowlarr OCI Image"
      required_checks = ["required"]
      renovate        = { automerge_variable = "PROWLARR_AUTOMERGE" }
      template        = { owner = "divbast", repository = "oci-image-template" }
      dhi             = true
    }
    sonarr = {
      name            = "sonarr-oci-image"
      description     = "Security hardened Sonarr OCI Image"
      required_checks = ["required"]
      renovate        = { automerge_variable = "SONARR_AUTOMERGE" }
      template        = { owner = "divbast", repository = "oci-image-template" }
      dhi             = true
    }
    lidarr = {
      name            = "lidarr-oci-image"
      description     = "Security hardened Lidarr OCI Image"
      required_checks = ["required"]
      renovate        = { automerge_variable = "LIDARR_AUTOMERGE" }
      template        = { owner = "divbast", repository = "oci-image-template" }
      dhi             = true
    }
    radarr = {
      name            = "radarr-oci-image"
      description     = "Security hardened Radarr OCI Image"
      required_checks = ["required"]
      renovate        = { automerge_variable = "RADARR_AUTOMERGE" }
      template        = { owner = "divbast", repository = "oci-image-template" }
      dhi             = true
    }
    sabnzbd = {
      name            = "sabnzbd-oci-image"
      description     = "Security hardened SABnzbd OCI Image"
      required_checks = ["required"]
      renovate        = { automerge_variable = "SABNZBD_AUTOMERGE" }
      template        = { owner = "divbast", repository = "oci-image-template" }
      dhi             = true
    }
    calibre = {
      name            = "calibre-oci-image"
      description     = "Security hardened Calibre and Calibre-Web OCI Image"
      required_checks = ["required"]
      renovate        = { automerge_variable = "CALIBRE_AUTOMERGE" }
      template        = { owner = "divbast", repository = "oci-image-template" }
      dhi             = true
    }
    pisati = {
      name            = "pisati"
      description     = "Pisati: a secure, minimalist, federated blogging platform"
      required_checks = ["required"]
      renovate        = { automerge_variable = "PISATI_AUTOMERGE" }
      template        = { owner = "divbast", repository = "oci-image-template" }
      dhi             = true
      # Releases are tagged by the Renovate App, as ci's are, and stay
      # immutable once published.
      tag_creator_app_ids = [local.renovate_app_id]
      immutable_releases  = true
    }
  }

  # Repos whose published releases can never change. Provider 6.13.0 has
  # no attribute for it: infra-settings sets it after each apply, and
  # modules/checks reads it back.
  immutable_release_repositories = module.entries.immutable_release_repositories
}

# Fails the plan on a key in local.repositories that nothing reads, and on
# ci's entry no longer setting immutable_releases = true.
module "entries" {
  source       = "./modules/entries"
  repositories = local.repositories
}

module "repository" {
  source = "./modules/repository"
  # Through module.entries, so that no entry reaches this module unchecked.
  for_each = module.entries.repositories

  name = each.value.name
  # Conversion to the module's object type drops the attributes it does
  # not declare: name, and immutable_releases, which the root handles.
  # module.entries has already refused any other key it would drop.
  settings                 = each.value
  maintainers_team_id      = module.organization.maintainers_team_id
  renovate_app_client_id   = var.renovate_app_client_id
  renovate_app_private_key = var.renovate_app_private_key
  dhi_username             = var.dhi_username
  dhi_token                = var.dhi_token
}

# Reads back what a plan cannot compare. A failed check is only a warning
# in a plan; the drift run fails on any.
module "checks" {
  source                         = "./modules/checks"
  repositories                   = module.entries.repositories
  immutable_release_repositories = local.immutable_release_repositories
}
