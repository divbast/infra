# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

terraform {
  required_version = "~> 1.13.9"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "6.13.0"
    }
  }
}
