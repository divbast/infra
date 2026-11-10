# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# The token comes from GITHUB_TOKEN, minted per run from the divbast-infra
# App. The owner is explicit: with none, an installation token fails the
# provider's GET /user. GITHUB_OWNER, GITHUB_ORGANIZATION and GITHUB_APP_*
# would override this, so no workflow sets them.
provider "github" {
  owner = "divbast"
}
