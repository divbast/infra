# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# The checks that read the org's own settings. The two reads are given in
# each run rather than for the whole file, since a run's own override of a
# read the file overrides too draws a warning.

mock_provider "github" {}

variables {
  repositories = {
    ci = { name = "ci" }
  }
  immutable_release_repositories = []
}

override_data {
  target = data.github_rest_api.repository
  values = { body = "{\"topics\":[],\"web_commit_signoff_required\":false,\"allow_forking\":true,\"default_branch\":\"main\"}" }
}
override_data {
  target = data.github_rest_api.immutable_releases
  values = { body = "{\"enabled\":false,\"enforced_by_owner\":false}" }
}
override_data {
  target = data.github_rest_api.private_vulnerability_reporting
  values = { body = "{\"enabled\":true}" }
}

run "the_org_as_infra_settings_leaves_it_passes" {
  command = plan

  override_data {
    target = data.github_rest_api.fork_pr_approval
    values = { body = "{\"approval_policy\":\"all_external_contributors\"}" }
  }
  override_data {
    target = data.github_rest_api.code_security_defaults
    values = { body = "[]" }
  }

  assert {
    condition     = alltrue([for setting, names in output.drifted : length(names) == 0])
    error_message = "No repo differs."
  }
}

run "fork_pr_approval_loosened" {
  command = plan

  override_data {
    target = data.github_rest_api.fork_pr_approval
    values = { body = "{\"approval_policy\":\"first_time_contributors\"}" }
  }
  override_data {
    target = data.github_rest_api.code_security_defaults
    values = { body = "[]" }
  }

  expect_failures = [check.fork_pr_approval]
}

run "a_default_code_security_configuration_set" {
  command = plan

  override_data {
    target = data.github_rest_api.fork_pr_approval
    values = { body = "{\"approval_policy\":\"all_external_contributors\"}" }
  }
  override_data {
    target = data.github_rest_api.code_security_defaults
    values = { body = "[{\"default_for_new_repos\":\"public\",\"configuration\":{\"id\":1}}]" }
  }

  expect_failures = [check.no_default_code_security_configuration]
}
