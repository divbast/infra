// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

package repotest_test

import (
	"maps"
	"regexp"
	"slices"
	"strings"
	"testing"
)

// usesRef matches a step's or a calling job's uses: line, block style, and
// captures the ref.
var usesRef = regexp.MustCompile(`^\s*(?:- )?uses:\s*["']?([^\s"']+)`)

// fullSHA is a commit SHA in full, the only ref the org lets an action run
// at.
var fullSHA = regexp.MustCompile(`^[0-9a-f]{40}$`)

// exemptOwners need no line in actions-allowlist.txt: GitHub's own actions,
// which the org allows separately, and divbast's own reusable workflows.
var exemptOwners = []string{"actions", "github", "divbast"}

// allowlistProblems returns each way the workflows break the org's Actions
// policy, which covers this repository too: a ref not pinned to a full
// commit SHA, or an action whose owner/repo@* is not a line of the
// allowlist and whose owner is not exempt. A local ./ ref is skipped. No
// uses: line at all is a problem too, since then nothing was checked.
func allowlistProblems(workflows map[string]string, allowlist string) []string {
	allowed := map[string]bool{}
	for l := range strings.Lines(allowlist) {
		l = strings.TrimRight(l, "\r\n")
		if t := strings.TrimSpace(l); t != "" && !strings.HasPrefix(t, "#") {
			allowed[l] = true
		}
	}
	refs := map[string]bool{}
	for _, w := range workflows {
		for l := range strings.Lines(w) {
			if m := usesRef.FindStringSubmatch(l); len(m) == 2 && !strings.HasPrefix(m[1], "./") {
				refs[m[1]] = true
			}
		}
	}
	if len(refs) == 0 {
		return []string{"no uses: lines found; is .github/workflows empty?"}
	}
	var problems []string
	for _, ref := range slices.Sorted(maps.Keys(refs)) {
		action, sha := ref, ref
		if i := strings.LastIndex(ref, "@"); i >= 0 {
			action, sha = ref[:i], ref[i+1:]
		}
		owner, rest, _ := strings.Cut(action, "/")
		name, _, _ := strings.Cut(rest, "/")
		if !fullSHA.MatchString(sha) {
			problems = append(problems, ref+": not pinned to a full SHA")
		}
		if repo := owner + "/" + name; !slices.Contains(exemptOwners, owner) && !allowed[repo+"@*"] {
			problems = append(problems, ref+": "+repo+"@* is not in actions-allowlist.txt")
		}
	}
	return problems
}

// TestEveryActionIsAllowedAndPinned runs allowlistProblems over the
// workflows and actions-allowlist.txt as they are, then over copies of
// them changed to break the policy, which it must refuse, and to use what
// the policy allows, which it must pass.
func TestEveryActionIsAllowedAndPinned(t *testing.T) {
	t.Parallel()
	workflows, allowlist := readWorkflows(t), readFile(t, "actions-allowlist.txt")
	for _, p := range allowlistProblems(workflows, allowlist) {
		t.Error(p)
	}

	const sha = "0123456789abcdef0123456789abcdef01234567"
	// A step of plan.yml's, a workflow that stays local
	const step = "      - uses: jdx/mise-action@"
	tests := []struct {
		name       string
		file, expr string // a regular expression in workflows[file]
		to         string
		allowlist  func(string) (string, error)
		want       string // in a problem; empty when there must be none
	}{
		{
			name: "an action pinned to a tag",
			file: "plan.yml", expr: `jdx/mise-action@[0-9a-f]{40}`, to: "jdx/mise-action@v5.2.8",
			want: "jdx/mise-action@v5.2.8: not pinned to a full SHA",
		},
		{
			name: "an action pinned to a short SHA",
			file: "plan.yml", expr: `jdx/mise-action@[0-9a-f]{40}`, to: "jdx/mise-action@0123456",
			want: "jdx/mise-action@0123456: not pinned to a full SHA",
		},
		{
			name:      "an allowlist without the action",
			allowlist: func(s string) (string, error) { return replace(s, "jdx/mise-action@*\n", "") },
			want:      "jdx/mise-action@* is not in actions-allowlist.txt",
		},
		{
			name: "an action the allowlist does not name",
			file: "plan.yml", expr: regexp.QuoteMeta(step), to: "      - uses: docker/build-push-action@" + sha + "\n" + step,
			want: "docker/build-push-action@* is not in actions-allowlist.txt",
		},
		{
			name: "a reusable workflow of divbast/ci at a tag",
			file: "plan.yml", expr: regexp.QuoteMeta(step), to: "      - uses: divbast/ci/.github/workflows/lint.yml@v1.12.0\n" + step,
			want: "divbast/ci/.github/workflows/lint.yml@v1.12.0: not pinned to a full SHA",
		},
		{
			name: "a reusable workflow of divbast/ci at a full SHA",
			file: "plan.yml", expr: regexp.QuoteMeta(step), to: "      - uses: divbast/ci/.github/workflows/lint.yml@" + sha + " # v1.12.0\n" + step,
		},
		{
			name: "a local action",
			file: "plan.yml", expr: regexp.QuoteMeta(step), to: "      - uses: ./.github/actions/local\n" + step,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			w, a := maps.Clone(workflows), allowlist
			var err error
			if tt.file != "" {
				if w[tt.file], err = replaceRE(w[tt.file], tt.expr, tt.to); err != nil {
					t.Fatalf("%s: %v", tt.file, err)
				}
			}
			if tt.allowlist != nil {
				if a, err = tt.allowlist(a); err != nil {
					t.Fatalf("actions-allowlist.txt: %v", err)
				}
			}
			problems := allowlistProblems(w, a)
			if tt.want == "" {
				for _, p := range problems {
					t.Error(p)
				}
				return
			}
			wantProblem(t, problems, tt.want)
		})
	}

	t.Run("no uses: lines", func(t *testing.T) {
		t.Parallel()
		wantProblem(t, allowlistProblems(map[string]string{"ci.yml": "name: ci\n"}, allowlist), "no uses: lines found")
	})
}
