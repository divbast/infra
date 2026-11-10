# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# Lint the root and the local child modules it calls.
config {
  call_module_type = "local"
}

# The terraform ruleset bundled with TFLint itself: no source, so no
# download and no API token. Every rule, as errors are errors here.
plugin "terraform" {
  enabled = true
  preset  = "all"
}
