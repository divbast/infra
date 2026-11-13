<!--
SPDX-License-Identifier: BSD-2-Clause
SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>
-->

# infra

OpenTofu for the divbast GitHub organisation. A merge to main applies to
the live org with admin rights.

## CRITICAL: Git commit message format

**No AI/LLM attribution of any other kind may appear in a git message.**

Linux-kernel style: a `subsystem: short description` subject under 75
characters in imperative mood, a blank line, then a body wrapped at about
75 columns saying why the change is needed, not only what it does.

These two lines MUST end EVERY body:

Developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: <NAME_OF_LLM_MODEL>

E.g. `Assisted-by: <Claude:claude-5.5-opus>`.

- Sign every commit (`git commit -S`); main requires verified signatures.
- Write commit messages as if a human wrote them.

## CRITICAL: No AI attribution in pull requests

Pull request descriptions, PR and review comments, and issue text carry
no AI/LLM attribution of any kind, even when a tool asks for one. The
`Assisted-by:` trailer is this project's one record of LLM involvement.

## Key commands

- `just setup`: check divbast/ci out into `.ci` at the commit the
  workflows pin, then install the pinned toolchain from `mise.toml`.
- `just ci`: every gate, as CI runs it. Run it before committing. The
  gates that call GitHub take only a fine-grained `GITHUB_TOKEN`
  (divbast/ci's README, "Local GitHub token").
- `just lint`: `just init`, then divbast/ci's shared recipes (pinact,
  zizmor, actionlint, ShellCheck and shfmt, reuse), `tofu fmt`,
  validate, TFLint, `just test`, and the Go gates and tests.
- `just test`: `tofu test` in each module, against a mocked provider.

## Rules

- **Files are `.tf`, never `.tofu`.** TFLint and Checkov silently skip
  `.tofu` files and exit 0, so a gate built on them would check nothing.
- **Logic lives in the modules, and the modules are tested.** The root
  holds the backend, encryption, imports and the composition only.
- **No `import` blocks in a tested module.** `tofu test` crashes on a
  module tree containing them (opentofu#4776). Imports go in the root's
  `imports.tf`, which is deleted after the apply that runs them.
- **Go, not shell.** Shell only for what is simple, at most 30 lines and
  unlikely to grow. Go is stdlib only, `cmd/` for commands and
  `internal/` for the rest, under divbast/ci's `go-lint` and `go-test`.
- **`ci`, `renovate` and `stall` call divbast/ci at one release.** Every
  `divbast/ci` ref names the same commit, with its tag as the comment;
  `plan`, `apply` and `drift` stay local, since they hold the org-admin
  token, and install only what they run.
- **Every lint gate is an error.** Fix findings rather than suppress
  them; a suppression needs a justification beside it.
- **A test that has never failed proves nothing.** When adding one, break
  the code it guards and watch it fail before trusting it.
- **Provider pinned exactly.** `integrations/github` is `6.13.0`. Read the
  release notes before moving it: 6.14.0 changes how reads use ETags.
- **Never set `GITHUB_OWNER`, `GITHUB_ORGANIZATION` or `GITHUB_APP_*`** in
  a job that runs tofu: they override the provider's owner and token.
- **Never publish `tofu show -json` output.** It holds sensitive values
  in full, and this repository is public. Use `tofu show -no-color`. The
  drift run reads its check results through `infra-checks`
  (`cmd/infra-checks`), which decodes only each check's address and
  status, and prints only addresses.
- **Tags take two rulesets.** A bypass covers every rule in its ruleset,
  so `tag-creation` (org admins, plus the Apps in a repo's
  `tag_creator_app_ids`) is separate from `tag-update-deletion` (org
  admins only). Never add a bypass actor to `tag-update-deletion`. An App
  is named by its App ID, never an installation ID. `tag-update-deletion`
  waits for `tag-creation` in the graph (`internal/repotest` holds the
  edge), so a rule moving into `tag-creation` stays enforced mid-apply.
  That holds in that direction only: moving a rule back out of
  `tag-creation` updates it first, so that apply needs the edge reversed.
- **What the provider cannot manage is set by `infra-settings`**
  (`cmd/infra-settings`), after each apply, through the REST API with
  `net/http`, never `gh`: private vulnerability reporting, the fork-PR
  approval policy, no default code security configuration, and immutable
  releases on a repo with `immutable_releases = true` in
  `local.repositories`. Provider 6.13.0 has no attribute for any of them.
  `checks.tf` reads each back for the drift run, on every repo, and also
  reads each repo's topics, commit signoff, forking and default branch:
  the provider marks those optional and computed, so a plan never shows
  a hand edit to one the config leaves unset or empty.
- **A new key for `local.repositories` goes in `modules/entries` too.**
  Conversion to the repository module's object type drops a key it does
  not declare without a word, so `modules/entries` fails the plan on any
  key missing from its `allowed_keys`.
- **`template` belongs only on an entry that creates a new repo.** The
  provider reads it on create alone, so on an existing repo it plans a
  diff forever. A new app repo is an entry with
  `template = { owner = "divbast", repository = "oci-image-template" }`;
  never add it to an existing entry. `oci-image-template` itself is made
  with `auto_init` and `is_template = true`, not from a template, and its
  kill switch is `OCI_IMAGE_TEMPLATE_AUTOMERGE`.
- **Destroy guards stay.** Repos are forgotten, not deleted, when removed
  from config; the org-wide resources refuse destruction, because
  destroying them resets them. `internal/repotest` holds the line.
- REUSE headers on every file, BSD-2-Clause. Files without comment syntax
  or rewritten by tools get a `.license` sidecar.
