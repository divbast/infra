// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

// Package repotest_test checks properties of this repository's own files
// that no linter checks: the workflows, the OpenTofu modules and the
// actions allowlist. Each check runs against the files as they are, and
// then against copies changed to break the one property it holds, which it
// must refuse, so that a check that can no longer fail fails instead.
package repotest_test

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

// root is the repository's root, from this package's directory, where go
// test runs it.
const root = "../.."

// openRoot opens the repository's root, closed when the test ends.
func openRoot(t *testing.T) *os.Root {
	t.Helper()
	return openDir(t, root)
}

// openDir opens dir as an os.Root, closed when the test ends.
func openDir(t *testing.T, dir string) *os.Root {
	t.Helper()
	r, err := os.OpenRoot(dir)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = r.Close() })
	return r
}

// readFile returns a file of the repository, by its path from the root.
func readFile(t *testing.T, name string) string {
	t.Helper()
	data, err := openRoot(t).ReadFile(name)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// readWorkflows returns every workflow in .github/workflows, by file name.
func readWorkflows(t *testing.T) map[string]string {
	t.Helper()
	dir := filepath.Join(".github", "workflows")
	r := openRoot(t)
	entries, err := fs.ReadDir(r.FS(), dir)
	if err != nil {
		t.Fatal(err)
	}
	workflows := map[string]string{}
	for _, e := range entries {
		if ext := filepath.Ext(e.Name()); ext != ".yml" && ext != ".yaml" {
			continue
		}
		data, err := r.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			t.Fatal(err)
		}
		workflows[e.Name()] = string(data)
	}
	if len(workflows) == 0 {
		t.Fatalf("no workflows in %s", dir)
	}
	return workflows
}

// replace returns s with the first from replaced by to, or an error when s
// holds no from, so that a mutant never quietly equals the original.
func replace(s, from, to string) (string, error) {
	if !strings.Contains(s, from) {
		return "", fmt.Errorf("holds no %q", from)
	}
	return strings.Replace(s, from, to, 1), nil
}

// replaceRE is replace for the first match of a regular expression, for
// text such as a commit SHA that Renovate moves.
func replaceRE(s, expr, to string) (string, error) {
	loc := regexp.MustCompile(expr).FindStringIndex(s)
	if loc == nil {
		return "", fmt.Errorf("holds no match for %s", expr)
	}
	return s[:loc[0]] + to + s[loc[1]:], nil
}

// wantProblem fails the test unless one of problems contains want. It logs
// each problem, so that go test -v shows every refusal a mutant drew.
func wantProblem(t *testing.T, problems []string, want string) {
	t.Helper()
	for _, p := range problems {
		t.Log("refused: " + p)
	}
	if !slices.ContainsFunc(problems, func(p string) bool { return strings.Contains(p, want) }) {
		t.Errorf("no problem says %q; got %q", want, problems)
	}
}

// line is one line of a file and its 1-based number in it.
type line struct {
	n    int
	text string
}

// linesOf returns a workflow's lines, leaving out blank lines and
// comments.
func linesOf(workflow string) []line {
	var lines []line
	n := 0
	for text := range strings.Lines(workflow) {
		n++
		text = strings.TrimRight(text, "\r\n")
		if trimmed := strings.TrimSpace(text); trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		lines = append(lines, line{n: n, text: text})
	}
	return lines
}

// jobsOf returns each job under the workflow's top-level jobs key, by name,
// as its lines. It relies on the two-space indentation every workflow here
// uses.
func jobsOf(lines []line) map[string][]line {
	jobs := map[string][]line{}
	inJobs, name := false, ""
	for _, l := range lines {
		switch indent(l.text) {
		case 0:
			inJobs, name = l.text == "jobs:", ""
			continue
		case 2:
			if inJobs {
				name = strings.TrimSuffix(strings.TrimSpace(l.text), ":")
				jobs[name] = nil
				continue
			}
		}
		if inJobs && name != "" {
			jobs[name] = append(jobs[name], l)
		}
	}
	return jobs
}

// steps splits a job's steps list into its steps, each from its "- " line
// to the line before the next one.
func steps(job []line) [][]line {
	var out [][]line
	in, at := false, -1
	for _, l := range job {
		ind, trimmed := indent(l.text), strings.TrimSpace(l.text)
		if ind <= 4 {
			in = trimmed == "steps:"
			continue
		}
		if !in {
			continue
		}
		if strings.HasPrefix(trimmed, "- ") && (at < 0 || ind == at) {
			at = ind
			out = append(out, nil)
		}
		if len(out) > 0 {
			out[len(out)-1] = append(out[len(out)-1], l)
		}
	}
	return out
}

// block returns the lines of the mapping under the key written at indent
// among lines, such as a job's concurrency or env, by key, values as
// written.
func block(lines []line, at int, key string) map[string]string {
	out := map[string]string{}
	in := false
	for _, l := range lines {
		ind, trimmed := indent(l.text), strings.TrimSpace(l.text)
		switch {
		case ind <= at:
			in = ind == at && trimmed == key+":"
		case in && ind == at+2:
			if k, v, ok := strings.Cut(trimmed, ":"); ok {
				out[k] = unquote(v)
			}
		}
	}
	return out
}

// field returns the value of the key written at indent among lines, and
// whether there is one, as for a job's if or a step's name.
func field(lines []line, at int, key string) (string, bool) {
	for _, l := range lines {
		if indent(l.text) != at {
			continue
		}
		trimmed := strings.TrimPrefix(strings.TrimSpace(l.text), "- ")
		if v, ok := strings.CutPrefix(trimmed, key+":"); ok {
			return unquote(v), true
		}
	}
	return "", false
}

// stepField is field for one step, whose first key shares its line with
// the step's "- " and whose others sit two columns further in.
func stepField(step []line, key string) (string, bool) {
	if len(step) == 0 {
		return "", false
	}
	at := indent(step[0].text)
	if v, ok := field(step[:1], at, key); ok {
		return v, true
	}
	return field(step[1:], at+2, key)
}

// unquote returns a plain YAML scalar's value: without a trailing comment,
// surrounding blanks or quotes.
func unquote(v string) string {
	v, _, _ = strings.Cut(v, " #")
	return strings.Trim(strings.TrimSpace(v), `"'`)
}

func indent(s string) int {
	return len(s) - len(strings.TrimLeft(s, " "))
}
