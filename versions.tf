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

  # Backblaze B2 through its S3 API. B2 rejects the conditional writes that
  # use_lockfile needs, so there is no lock here: every workflow that runs
  # tofu shares one concurrency group instead. Credentials come from
  # AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY.
  backend "s3" {
    bucket                      = "divbast-tofu-state"
    key                         = "org/terraform.tfstate"
    region                      = "us-west-004"
    endpoints                   = { s3 = "https://s3.us-west-004.backblazeb2.com" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  # State and plans are encrypted before they leave the runner, and an
  # unencrypted state or plan is refused. Key providers are named by
  # version because the metadata stored with the state is keyed by name: to
  # rotate, add "v2" with "v1" as its fallback, apply once, then remove v1.
  encryption {
    key_provider "pbkdf2" "v1" {
      passphrase = var.state_passphrase
    }

    method "aes_gcm" "v1" {
      keys = key_provider.pbkdf2.v1
    }

    state {
      method   = method.aes_gcm.v1
      enforced = true
    }

    plan {
      method   = method.aes_gcm.v1
      enforced = true
    }
  }
}
