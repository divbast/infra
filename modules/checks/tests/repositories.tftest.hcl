# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

# The checks that read each repo. Every run but the first two changes one
# answer GitHub gives, or the config, for one repo, and wants only the one
# check that covers it to fail, naming that repo.

mock_provider "github" {}

variables {
  repositories = {
    ci     = { name = "ci" }
    baikal = { name = "baikal-oci-image" }
  }
  immutable_release_repositories = []
}

# Every read as GitHub answers it with nothing changed by hand.
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
override_data {
  target = data.github_rest_api.fork_pr_approval
  values = { body = "{\"approval_policy\":\"all_external_contributors\"}" }
}
override_data {
  target = data.github_rest_api.code_security_defaults
  values = { body = "[]" }
}

run "nothing_changed_by_hand_passes" {
  command = plan

  assert {
    condition     = alltrue([for setting, names in output.drifted : length(names) == 0])
    error_message = "No repo differs."
  }
}

# The config as main has it: ci flagged and on, and a repo whose entry sets
# topics that GitHub reports too, in another order.
run "flagged_and_on_with_topics_set_passes" {
  command = plan

  variables {
    repositories = {
      ci     = { name = "ci" }
      baikal = { name = "baikal-oci-image", topics = ["caldav", "carddav"] }
    }
    immutable_release_repositories = ["ci"]
  }
  override_data {
    target = data.github_rest_api.immutable_releases["ci"]
    values = { body = "{\"enabled\":true,\"enforced_by_owner\":false}" }
  }
  override_data {
    target = data.github_rest_api.repository["baikal"]
    values = { body = "{\"topics\":[\"carddav\",\"caldav\"],\"web_commit_signoff_required\":false,\"allow_forking\":true,\"default_branch\":\"main\"}" }
  }

  assert {
    condition     = alltrue([for setting, names in output.drifted : length(names) == 0])
    error_message = "No repo differs."
  }
}

run "a_topic_added_by_hand" {
  command = plan

  override_data {
    target = data.github_rest_api.repository["baikal"]
    values = { body = "{\"topics\":[\"caldav\"],\"web_commit_signoff_required\":false,\"allow_forking\":true,\"default_branch\":\"main\"}" }
  }

  expect_failures = [check.topics]

  assert {
    condition     = output.drifted.topics == ["baikal-oci-image"]
    error_message = "The topics check names baikal-oci-image alone."
  }
}

run "a_topic_the_entry_sets_taken_off_by_hand" {
  command = plan

  variables {
    repositories = {
      ci     = { name = "ci", topics = ["ci"] }
      baikal = { name = "baikal-oci-image" }
    }
  }

  expect_failures = [check.topics]

  assert {
    condition     = output.drifted.topics == ["ci"]
    error_message = "The topics check names ci alone."
  }
}

run "signoff_required_by_hand" {
  command = plan

  override_data {
    target = data.github_rest_api.repository["ci"]
    values = { body = "{\"topics\":[],\"web_commit_signoff_required\":true,\"allow_forking\":true,\"default_branch\":\"main\"}" }
  }

  expect_failures = [check.web_commit_signoff_required]

  assert {
    condition     = output.drifted.web_commit_signoff_required == ["ci"]
    error_message = "The signoff check names ci alone."
  }
}

run "forking_turned_off_by_hand" {
  command = plan

  override_data {
    target = data.github_rest_api.repository["baikal"]
    values = { body = "{\"topics\":[],\"web_commit_signoff_required\":false,\"allow_forking\":false,\"default_branch\":\"main\"}" }
  }

  expect_failures = [check.allow_forking]

  assert {
    condition     = output.drifted.allow_forking == ["baikal-oci-image"]
    error_message = "The forking check names baikal-oci-image alone."
  }
}

run "default_branch_renamed_by_hand" {
  command = plan

  override_data {
    target = data.github_rest_api.repository["ci"]
    values = { body = "{\"topics\":[],\"web_commit_signoff_required\":false,\"allow_forking\":true,\"default_branch\":\"trunk\"}" }
  }

  expect_failures = [check.default_branch]

  assert {
    condition     = output.drifted.default_branch == ["ci"]
    error_message = "The default branch check names ci alone."
  }
}

# A repo that does not read, as before its apply creates it, is never
# taken to match.
run "a_repo_that_does_not_read" {
  command = plan

  override_data {
    target = data.github_rest_api.repository["baikal"]
    values = { body = "{\"message\":\"Not Found\"}" }
  }

  expect_failures = [
    check.topics,
    check.web_commit_signoff_required,
    check.allow_forking,
    check.default_branch,
  ]

  assert {
    condition = alltrue([
      for setting in ["topics", "web_commit_signoff_required", "allow_forking", "default_branch"] :
      output.drifted[setting] == ["baikal-oci-image"]
    ])
    error_message = "Each of the four checks names baikal-oci-image alone."
  }
}

run "immutable_releases_switched_on_by_hand" {
  command = plan

  override_data {
    target = data.github_rest_api.immutable_releases["baikal"]
    values = { body = "{\"enabled\":true,\"enforced_by_owner\":false}" }
  }

  expect_failures = [check.immutable_releases]

  assert {
    condition     = output.drifted.immutable_releases == ["baikal-oci-image"]
    error_message = "The immutable releases check names baikal-oci-image alone."
  }
}

run "immutable_releases_off_on_ci" {
  command = plan

  variables {
    immutable_release_repositories = ["ci"]
  }

  expect_failures = [check.immutable_releases]

  assert {
    condition     = output.drifted.immutable_releases == ["ci"]
    error_message = "The immutable releases check names ci alone."
  }
}

run "immutable_releases_that_do_not_read" {
  command = plan

  override_data {
    target = data.github_rest_api.immutable_releases["baikal"]
    values = { body = "{\"message\":\"Not Found\"}" }
  }

  expect_failures = [check.immutable_releases]

  assert {
    condition     = output.drifted.immutable_releases == ["baikal-oci-image"]
    error_message = "The immutable releases check names baikal-oci-image alone."
  }
}

run "private_vulnerability_reporting_turned_off" {
  command = plan

  override_data {
    target = data.github_rest_api.private_vulnerability_reporting["ci"]
    values = { body = "{\"enabled\":false}" }
  }

  expect_failures = [check.private_vulnerability_reporting]

  assert {
    condition     = output.drifted.private_vulnerability_reporting == ["ci"]
    error_message = "The reporting check names ci alone."
  }
}
