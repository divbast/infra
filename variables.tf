# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

variable "state_passphrase" {
  description = "Passphrase that encrypts state and plans."
  type        = string
  sensitive   = true
  # Never written into a saved plan, where it would be useless anyway: a
  # saved plan still needs it supplied again to apply.
  ephemeral = true
  nullable  = false

  validation {
    condition     = length(var.state_passphrase) >= 32
    error_message = "Use at least 32 random characters, e.g. openssl rand -base64 48."
  }
}

variable "renovate_app_client_id" {
  description = "Client ID of the divbast-renovate App, written into each repo's renovate environment."
  type        = string
  nullable    = false
}

variable "renovate_app_private_key" {
  description = "Private key of the divbast-renovate App, written into each repo's renovate environment."
  type        = string
  sensitive   = true
  # Not ephemeral: the key lands in a resource attribute, and provider
  # 6.13.0 has no write-only attributes (integrations/terraform-provider-github#3202).
  nullable = false
}
