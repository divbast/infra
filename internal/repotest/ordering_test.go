// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

package repotest_test

import (
	"errors"
	"io/fs"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// orderings are edges the provider does not know about. Without one in the
// graph, tofu runs the two resources in parallel: the apply fails half-way,
// or a protection lapses while it runs.
var orderings = []struct{ from, to, why string }{
	// baikal-oci-image arrived with its vulnerability alerts off.
	{
		"github_repository_dependabot_security_updates.this", "github_repository_vulnerability_alerts.this",
		"GitHub refuses to configure security updates while alerts are off (422)",
	},
	{
		"github_repository_ruleset.tag_update_deletion", "github_repository_ruleset.tag_creation",
		"a rule moving into tag_creation would go unenforced mid-apply",
	},
}

// module is the module whose graph holds the orderings.
var module = filepath.Join("modules", "repository")

// graph returns tofu graph for the module in dir. It fails the test, and
// never skips it, when tofu cannot draw one, as it cannot until just init
// has installed the module's providers; -no-color keeps colour codes out
// of what tofu says then.
func graph(t *testing.T, dir string) string {
	t.Helper()
	cmd := exec.CommandContext(t.Context(), "tofu", "graph", "-no-color")
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		if exit, ok := errors.AsType[*exec.ExitError](err); ok {
			t.Fatalf("tofu graph in %s: %v; run just init first\n%s", dir, err, exit.Stderr)
		}
		t.Fatalf("tofu graph in %s: %v; run just init first", dir, err)
	}
	return string(out)
}

// orderingProblems returns each ordering missing from a module's graph.
func orderingProblems(graph string) []string {
	var problems []string
	for _, o := range orderings {
		edge := `"[root] ` + o.from + ` (expand)" -> "[root] ` + o.to + ` (expand)"`
		if !strings.Contains(graph, edge) {
			problems = append(problems, o.from+" does not wait for "+o.to+": "+o.why)
		}
	}
	return problems
}

// copyModule copies the module's configuration into a new directory, with
// from replaced by to in file, and links the module's .terraform there, so
// that tofu draws the changed module's graph with the providers just init
// installed.
func copyModule(t *testing.T, file, from, to string) string {
	t.Helper()
	entries, err := fs.ReadDir(openRoot(t).FS(), module)
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	dst := openDir(t, dir)
	changed := false
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || (filepath.Ext(name) != ".tf" && name != ".terraform.lock.hcl") {
			continue
		}
		text := readFile(t, filepath.Join(module, name))
		if name == file {
			if text, err = replace(text, from, to); err != nil {
				t.Fatalf("%s: %v", file, err)
			}
			changed = true
		}
		if err = dst.WriteFile(name, []byte(text), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if !changed {
		t.Fatalf("%s is not in %s", file, module)
	}
	installed, err := filepath.Abs(filepath.Join(root, module, ".terraform"))
	if err != nil {
		t.Fatal(err)
	}
	if err = dst.Symlink(installed, ".terraform"); err != nil {
		t.Fatal(err)
	}
	return dir
}

// TestEveryOrderingTheProviderDoesNotKnowAboutIsInTheGraph reads the
// module's graph and finds each ordering in it, then draws the graph of
// copies of the module with one ordering taken out, and must find it
// missing.
func TestEveryOrderingTheProviderDoesNotKnowAboutIsInTheGraph(t *testing.T) {
	t.Parallel()
	for _, p := range orderingProblems(graph(t, filepath.Join(root, module))) {
		t.Error(p)
	}

	tests := []struct {
		name, file, from, to, want string
	}{
		{
			"security updates name the repository directly", "main.tf",
			"repository = github_repository_vulnerability_alerts.this.repository", "repository = github_repository.this.name",
			"github_repository_dependabot_security_updates.this does not wait for github_repository_vulnerability_alerts.this",
		},
		{
			"tag_update_deletion without its depends_on", "rulesets.tf",
			"  depends_on = [github_repository_ruleset.tag_creation]\n", "",
			"github_repository_ruleset.tag_update_deletion does not wait for github_repository_ruleset.tag_creation",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			wantProblem(t, orderingProblems(graph(t, copyModule(t, tt.file, tt.from, tt.to))), tt.want)
		})
	}
}
