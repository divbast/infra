<!--
SPDX-License-Identifier: BSD-2-Clause
SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>
-->

# infra

The divbast organisation, as OpenTofu: its settings, its Actions policy,
the maintainers team, and every repository with its rulesets,
environments and Renovate wiring. A hand edit in the UI to a setting the
config states, or to one `modules/checks` reads back, turns the next
daily drift run red.

- `modules/organization`: org settings, Actions policy, workflow token
  defaults, the maintainers team.
- `modules/repository`: one repository's baseline: public; merge commits
  and squash only; signed commits, a PR and passing checks on the default
  branch; tags guarded by two rulesets (below); Renovate's environment and
  kill switch.
- `main.tf`: every repository, as one entry in `local.repositories`.
- `modules/entries`: those entries as written. It fails the plan on an
  entry's own key that nothing reads, which conversion to the repository
  module's type would otherwise drop without a word, and on `ci`'s entry
  no longer setting `immutable_releases = true`.
- `modules/checks` and `cmd/infra-settings`: the settings the provider
  cannot manage (private vulnerability reporting, the fork-PR approval
  policy, no default code security configuration, immutable releases).
  `infra-settings` sets them through the REST API after each apply, and
  `modules/checks` reads them back. It also reads each repo's topics,
  commit signoff, forking and default branch, which the provider marks
  optional and computed: a plan never shows a hand edit to one the config
  leaves unset or empty.
- `cmd/infra-checks`: the drift run's filter over the JSON plan, which
  fails on any check that did not pass and prints only addresses.
- `internal/repotest`: Go tests of this repository's own files: the
  workflows' properties, the destroy guards, the graph orderings the
  provider does not know about, and the actions allowlist.

## Tags and releases

A ruleset's bypass list covers every rule in it, so each repository has
two tag rulesets, both over every tag:

- `tag-creation` blocks creating a tag. Org admins bypass it, and so do
  the GitHub Apps in the repo's `tag_creator_app_ids`, named by App ID
  (`gh api /apps/<slug> --jq .id`), not by installation ID.
- `tag-update-deletion` blocks moving and deleting a tag. Only org admins
  bypass it, whatever `tag_creator_app_ids` holds.

`ci` names `divbast-renovate` (App ID 5691200) as its tag creator: ci's
release workflow tags and releases every green merge to main as that
App, from ci's main-only `renovate` environment. A squash merge's
message starts as the messages of the commits it squashes
(`squash_merge_commit_message = "COMMIT_MESSAGES"`), so a
`Breaking-change:` trailer on any of them reaches main, where that
release workflow reads it.

`immutable_releases = true` turns on GitHub's immutable releases for a
repo: once a release is published, its tag and assets cannot change.
Provider 6.13.0 has no attribute for it, so `apply` sets it through the
REST API after each apply, and `modules/checks` reads it back on every
repo, which turns the drift run red if it is ever switched off, or
switched on for a repo that does not set it. `ci` sets it. Setting it to
false, or leaving it out, does not turn it off on GitHub; a person does
that in the repo's settings, and the drift run stays red until they do.

## How it runs

| Workflow | When | What |
|---|---|---|
| `ci` | every PR and push | every gate (`just lint`, through divbast/ci's `lint.yml`), no secrets |
| `plan` | PRs from this repository | the plan against the live org, on the run's summary page |
| `apply` | push to main, or by hand | a fresh plan, applied, then `infra-settings` |
| `drift` | daily, or by hand | red if a plan of main is not empty or a check fails |
| `renovate` | daily, on merges, on CI or the plan finishing | updates, through divbast/ci's `renovate.yml`; merges its own PRs only when their plan is empty |
| `stall` | daily, or by hand | red when updates stop flowing: a Renovate PR stuck or left open, or Renovate silent, through divbast/ci's `stall.yml` |

`ci`, `renovate` and `stall` call divbast/ci's shared workflows, all at
one pinned release, and Renovate moves that pin in one pull request.
`plan`, `apply` and `drift` stay here: they hold the org-admin token.

State lives in a private Backblaze B2 bucket, encrypted by OpenTofu
before it leaves the runner. B2 has no state locking, so every workflow
that runs tofu queues on one concurrency group.

## Working here

`just setup` checks divbast/ci out into `.ci` at the commit the
workflows pin, and installs the toolchain from `mise.toml`. `just ci`
runs every gate, as CI does: divbast/ci's shared lint recipes (pinact,
zizmor, actionlint, ShellCheck, shfmt and `reuse lint`), `tofu fmt`,
`validate`, TFLint, `tofu test` in each module, and the Go gates and
tests. The Go tests read the repository module's graph, so `just lint`
runs `just init` first, which needs no state or credentials. The gates
that call GitHub need a fine-grained `GITHUB_TOKEN`; see
[ci's README](https://github.com/divbast/ci#local-github-token).

## Adding a repository

Add one entry to `local.repositories` in `main.tf` and open a PR. A key
of the entry's own that nothing reads, a misspelling among them, fails
the PR's plan. Inside one of its values, such as `template` or an
`environments` entry, every key the module declares is required, so a
misspelt one fails the plan too, as missing. An extra key there is what
goes unseen: conversion drops it without a word. The likeliest is
`include_all_branches` in `template`, the provider's own name for it,
which the module always sets to false and never reads from the entry.
The `divbast-infra` and `divbast-renovate` Apps are installed on
all repositories, so a new one needs nothing by hand. A repo that runs
Renovate names its kill switch, e.g. `BAIKAL_AUTOMERGE`. A repo that
publishes releases may set `tag_creator_app_ids` and
`immutable_releases`, as `ci` does.

From here on, a new app repo is an entry with
`template = { owner = "divbast", repository = "oci-image-template" }`.
The provider uses `template` only to create the repo, but on every
refresh it reads back the template the repo was made from. So never add
it to an existing entry, and once the repo exists, keep the block in its
entry for good: either way, a block that disagrees with the repo shows a
diff in every plan, which turns the drift run red, and every Renovate
PR's `plan-empty` with it. The new repo arrives as one commit with
nothing renamed; the template's README lists what it must change, under
[Making a new app](https://github.com/divbast/oci-image-template#making-a-new-app).
The template repo itself is an ordinary `auto_init` entry with `is_template = true`,
not made from a template. Its Renovate kill switch is
`OCI_IMAGE_TEMPLATE_AUTOMERGE`; a repo made from it needs its own
variable name, in both its `renovate.yml` and its entry here.

## Stopping Renovate's merges

```sh
gh variable set BAIKAL_AUTOMERGE --body disabled -R divbast/baikal-oci-image
```

Any value but `enabled` stops merging from the next run. OpenTofu creates
the variable and then leaves its value alone, so an apply never turns
merging back on.

## Setup, done once by hand

1. Require two-factor authentication for members (org Settings, then
   Authentication security).
2. Backblaze B2: a private bucket, keeping all versions, and two
   application keys restricted to it, one read-only (`listBuckets`,
   `listFiles`, `readFiles`) and one read-write (those plus `writeFiles`,
   `deleteFiles`). The bucket's name and region go in `versions.tf`.
3. A state passphrase: `openssl rand -base64 48`.
4. The org-owned App `divbast-infra`, webhook off. Repository permissions:
   Administration, Contents, Environments, Secrets and Variables read and
   write; Actions and Metadata read. Organization permissions:
   Administration and Members read and write. Installed on all
   repositories.
5. The org-owned App `divbast-renovate`, webhook off. Repository
   permissions: Checks, Contents, Issues, Pull requests, Commit statuses
   and Workflows read and write; Dependabot alerts and Metadata read.
   Installed on all repositories. Every repository here has Dependabot
   alerts on, and without read access to them Renovate's dashboard warns
   that it cannot see them. Its App ID, 5691200, is `renovate_app_id` in
   `main.tf`.
6. This repository, created empty (its first commit is pushed as `main`),
   and its environments `plan` (any branch) and `apply` (main only), each
   holding:
   - variables `INFRA_APP_CLIENT_ID`, `RENOVATE_APP_CLIENT_ID`, `B2_KEY_ID`
   - secrets `INFRA_APP_PRIVATE_KEY`, `RENOVATE_APP_PRIVATE_KEY`,
     `STATE_PASSPHRASE`, `B2_APPLICATION_KEY`

   `plan` gets the read-only B2 key and `apply` the read-write one.
   OpenTofu manages the environments but never these values: it would
   need its own credentials as inputs.
7. Verify `divbast.ameri.coffee` (org Settings, then Verified and approved
   domains) with the DNS TXT record GitHub shows.
8. No payment method on the org: usage past the free allowance is then
   blocked, not billed.

## Settings with no API

These stay manual, and the drift run cannot see them:

- the two-factor requirement and domain verification;
- each package's visibility and its Actions access: a new image starts
  private and must be made public in its package settings.

## Break glass

Fix the problem in the UI first, then reconcile: dispatch `apply`, or
change the config by PR so the next apply agrees with what was done. To
run tofu locally, keep offline the read-write B2 key, the state
passphrase and the `divbast-infra` private key, and mint a short-lived
installation token from that key. Never use a long-lived personal token:
provider 6.13.0 can keep stale reads across runs with one
(integrations/terraform-provider-github#3519).

## Rotating the state passphrase

Add a `v2` key provider and method in `versions.tf`, with `v1` as the
method's `fallback`, and supply both passphrases. Apply once, which
rewrites state under `v2`, then remove `v1` and the old passphrase. The
key providers are named by version because the metadata stored with the
state is keyed by name.
