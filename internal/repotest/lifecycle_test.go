// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

package repotest_test

import (
	"regexp"
	"strings"
	"testing"
)

// guards are the lines that make a resource refuse destruction. Destroying
// these does not leave things as they were: a repo is deleted, the org's
// billing email becomes a placeholder, and the Actions policy and token
// defaults reset to GitHub's.
var guards = []struct {
	file, typ, name string
	line            *regexp.Regexp
}{
	{"modules/repository/main.tf", "github_repository", "this", regexp.MustCompile(`^\s+destroy\s+=\s+false$`)},
	{"modules/repository/main.tf", "github_repository", "this", regexp.MustCompile(`^\s+archive_on_destroy\s+=\s+true$`)},
	{"modules/organization/main.tf", "github_organization_settings", "this", regexp.MustCompile(`^\s+prevent_destroy\s+=\s+true$`)},
	{"modules/organization/main.tf", "github_actions_organization_permissions", "this", regexp.MustCompile(`^\s+prevent_destroy\s+=\s+true$`)},
	{"modules/organization/main.tf", "github_actions_organization_workflow_permissions", "this", regexp.MustCompile(`^\s+prevent_destroy\s+=\s+true$`)},
}

// resourceBlock returns the lines of one resource block of a .tf file, from
// its opening line to the first line after it that starts with }.
func resourceBlock(tf, typ, name string) []string {
	start := `resource "` + typ + `" "` + name + `" {`
	var out []string
	for l := range strings.Lines(tf) {
		l = strings.TrimRight(l, "\r\n")
		if out == nil && !strings.HasPrefix(l, start) {
			continue
		}
		out = append(out, l)
		if strings.HasPrefix(l, "}") {
			break
		}
	}
	return out
}

// lifecycleProblems returns each guard missing from its resource's block,
// given the .tf files by path.
func lifecycleProblems(files map[string]string) []string {
	var problems []string
	for _, g := range guards {
		found := false
		for _, l := range resourceBlock(files[g.file], g.typ, g.name) {
			found = found || g.line.MatchString(l)
		}
		if !found {
			problems = append(problems, g.typ+"."+g.name+" in "+g.file+" lacks "+g.line.String())
		}
	}
	return problems
}

// TestEveryGuardedResourceRefusesDestruction runs lifecycleProblems over
// the modules as they are, then over copies with one guard broken inside
// one resource's block, which it must refuse.
func TestEveryGuardedResourceRefusesDestruction(t *testing.T) {
	t.Parallel()
	const repo, org = "modules/repository/main.tf", "modules/organization/main.tf"
	files := map[string]string{repo: readFile(t, repo), org: readFile(t, org)}
	for _, p := range lifecycleProblems(files) {
		t.Error(p)
	}

	tests := []struct {
		name, file, typ string
		from, to        string // within the resource's block
		want            string
	}{
		{"a repo that destroys", repo, "github_repository", "destroy = false", "destroy = true", "github_repository.this in " + repo + " lacks ^\\s+destroy"},
		{"a repo guard commented out", repo, "github_repository", "    destroy = false", "    # destroy = false", "github_repository.this in " + repo + " lacks ^\\s+destroy"},
		{"a repo deleted rather than archived", repo, "github_repository", "archive_on_destroy     = true", "archive_on_destroy     = false", "lacks ^\\s+archive_on_destroy"},
		{"the guarded repo renamed", repo, "github_repository", `resource "github_repository" "this" {`, `resource "github_repository" "repo" {`, "github_repository.this in " + repo + " lacks"},
		{"org settings that destroy", org, "github_organization_settings", "prevent_destroy = true", "prevent_destroy = false", "github_organization_settings.this in " + org + " lacks"},
		{"an Actions policy that destroys", org, "github_actions_organization_permissions", "prevent_destroy = true", "prevent_destroy = false", "github_actions_organization_permissions.this in " + org + " lacks"},
		{"token defaults that destroy", org, "github_actions_organization_workflow_permissions", "prevent_destroy = true", "prevent_destroy = false", "github_actions_organization_workflow_permissions.this in " + org + " lacks"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			body := strings.Join(resourceBlock(files[tt.file], tt.typ, "this"), "\n")
			changed, err := replace(body, tt.from, tt.to)
			if err != nil {
				t.Fatalf("%s.this in %s: %v", tt.typ, tt.file, err)
			}
			mutant := map[string]string{repo: files[repo], org: files[org]}
			mutant[tt.file] = strings.Replace(files[tt.file], body, changed, 1)
			wantProblem(t, lifecycleProblems(mutant), tt.want)
		})
	}
}
