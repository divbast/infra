# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# ci's entry as main.tf writes it, with every key the root or the
# repository module reads set on one entry or another.
variables {
  repositories = {
    ci = {
      name                = "ci"
      description         = "Reusable workflows"
      homepage_url        = "https://example.com"
      topics              = ["ci"]
      has_issues          = true
      has_discussions     = false
      auto_init           = true
      required_checks     = ["required"]
      tag_creator_app_ids = [5691200]
      renovate            = { automerge_variable = "CI_AUTOMERGE" }
      environments        = { plan = { main_only = false } }
      immutable_releases  = true
    }
    template = {
      name        = "oci-image-template"
      description = "A template"
      is_template = true
    }
    app = {
      name        = "app"
      description = "An app"
      template    = { owner = "divbast", repository = "oci-image-template" }
    }
  }
}

run "every_key_read_somewhere_is_allowed" {
  command = plan

  assert {
    condition     = output.immutable_release_repositories == tolist(["ci"])
    error_message = "Only ci's entry sets immutable_releases."
  }
  assert {
    condition     = output.repositories == var.repositories
    error_message = "The entries pass through unchanged."
  }
}

# Conversion to the repository module's object type drops a key it does
# not declare without a word: the template flag below would never reach
# GitHub.
run "a_misspelt_key_fails_the_plan" {
  command = plan

  variables {
    repositories = {
      ci = { name = "ci", description = "x", immutable_releases = true }
      template = {
        name        = "oci-image-template"
        description = "A template"
        is_templte  = true
      }
    }
  }

  expect_failures = [output.repositories]
}

# ci's releases are what every caller pins, and infra-settings makes them
# immutable only while ci's entry asks.
run "ci_without_immutable_releases_fails_the_plan" {
  command = plan

  variables {
    repositories = {
      ci         = { name = "ci", description = "x" }
      frankenphp = { name = "frankenphp", description = "x", immutable_releases = true }
    }
  }

  expect_failures = [output.immutable_release_repositories]
}
