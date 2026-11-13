# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# Each check names the repos that differ, where it reads per repo, so that
# a red drift run says where to look.

check "private_vulnerability_reporting" {
  assert {
    condition     = length(local.drifted.private_vulnerability_reporting) == 0
    error_message = "Private vulnerability reporting is off on ${join(", ", local.drifted.private_vulnerability_reporting)}; infra-settings turns it on."
  }
}

check "immutable_releases" {
  assert {
    condition     = length(local.drifted.immutable_releases) == 0
    error_message = "Immutable releases on ${join(", ", local.drifted.immutable_releases)} differ from immutable_releases in their entries in local.repositories; infra-settings turns them on where an entry sets it, and a person turns them off in the repo's settings."
  }
}

check "topics" {
  assert {
    condition     = length(local.drifted.topics) == 0
    error_message = "Topics on ${join(", ", local.drifted.topics)} differ from their entries in local.repositories; put them in the entry, or take them off by hand."
  }
}

check "web_commit_signoff_required" {
  assert {
    condition     = length(local.drifted.web_commit_signoff_required) == 0
    error_message = "Commit signoff is required on ${join(", ", local.drifted.web_commit_signoff_required)}, and nothing here asks for it; turn it off in the repo's settings."
  }
}

check "allow_forking" {
  assert {
    condition     = length(local.drifted.allow_forking) == 0
    error_message = "Forking is off on ${join(", ", local.drifted.allow_forking)}, and nothing here turns it off; turn it back on in the repo's settings."
  }
}

check "default_branch" {
  assert {
    condition     = length(local.drifted.default_branch) == 0
    error_message = "The default branch is not main on ${join(", ", local.drifted.default_branch)}; make main the default again in the repo's settings."
  }
}

check "fork_pr_approval" {
  assert {
    condition     = try(jsondecode(data.github_rest_api.fork_pr_approval.body).approval_policy, "") == "all_external_contributors"
    error_message = "Fork PRs from outside contributors no longer wait for approval; infra-settings restores it."
  }
}

check "no_default_code_security_configuration" {
  assert {
    condition     = length(try(jsondecode(data.github_rest_api.code_security_defaults.body), [])) == 0
    error_message = "A default code security configuration is set and would fight the per-repo settings; remove it by hand."
  }
}
