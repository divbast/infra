// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

package repotest_test

import (
	"regexp"
	"slices"
	"strings"
	"testing"
)

const (
	entriesFile   = "modules/entries/main.tf"
	variablesFile = "modules/repository/variables.tf"
)

// entryOnlyKeys are the keys of an entry that the root reads itself and the
// repository module's settings do not declare.
var entryOnlyKeys = []string{"name", "immutable_releases"}

var (
	allowedKeysBlock = regexp.MustCompile(`(?s)allowed_keys\s*=\s*\[(.*?)\]`)
	quoted           = regexp.MustCompile(`"([^"]+)"`)
	settingsAttr     = regexp.MustCompile(`^ {4}([a-z_]+)\s+= `)
)

// allowedKeys returns the keys modules/entries lets an entry carry.
func allowedKeys(entries string) []string {
	m := allowedKeysBlock.FindStringSubmatch(entries)
	if m == nil {
		return nil
	}
	var keys []string
	for _, k := range quoted.FindAllStringSubmatch(m[1], -1) {
		keys = append(keys, k[1])
	}
	return keys
}

// settingsKeys returns the attributes of the repository module's settings
// variable: the object type's own, four columns in, never a nested one's.
func settingsKeys(variables string) []string {
	var keys []string
	in := false
	for l := range strings.Lines(variables) {
		l = strings.TrimRight(l, "\n")
		switch {
		case strings.HasPrefix(l, `variable "settings" {`):
			in = true
		case in && l == "}":
			return keys
		case in:
			if m := settingsAttr.FindStringSubmatch(l); m != nil {
				keys = append(keys, m[1])
			}
		}
	}
	return keys
}

// entryKeyProblems compares allowed_keys with the settings variable. A key
// allowed but not declared is dropped without a word when the entry is
// converted to the module's type, and a key declared but not allowed fails
// every plan that sets it.
func entryKeyProblems(entries, variables string) []string {
	allowed, declared := allowedKeys(entries), settingsKeys(variables)
	if len(allowed) == 0 {
		return []string{entriesFile + ": no allowed_keys found"}
	}
	if len(declared) == 0 {
		return []string{variablesFile + ": no settings attributes found"}
	}
	var problems []string
	for _, k := range allowed {
		if !slices.Contains(declared, k) && !slices.Contains(entryOnlyKeys, k) {
			problems = append(problems, entriesFile+`: allowed key "`+k+`" is no attribute of `+variablesFile+`'s settings, and no key the root reads`)
		}
	}
	for _, k := range declared {
		if !slices.Contains(allowed, k) {
			problems = append(problems, variablesFile+`: settings attribute "`+k+`" is not in `+entriesFile+"'s allowed_keys")
		}
	}
	return problems
}

// TestAllowedKeysMatchTheRepositorySettings is IN-5: allowed_keys is a
// second list of the settings' keys, and a rename in one alone would bring
// back the silent drop it exists to prevent.
func TestAllowedKeysMatchTheRepositorySettings(t *testing.T) {
	t.Parallel()
	entries, variables := readFile(t, entriesFile), readFile(t, variablesFile)
	for _, p := range entryKeyProblems(entries, variables) {
		t.Error(p)
	}

	tests := []struct {
		name      string
		inEntries bool
		from, to  string
		want      string
	}{
		{"a setting renamed in the variables only", false, "    has_discussions = optional", "    has_discussion = optional", `allowed key "has_discussions" is no attribute`},
		{"a setting removed from the variables", false, "    auto_init       = optional(bool, false)\n", "", `allowed key "auto_init" is no attribute`},
		{"a setting renamed in allowed_keys only", true, `"has_issues"`, `"has_issue"`, `allowed key "has_issue" is no attribute`},
		{"a setting left out of allowed_keys", true, `"is_template",`, "", `settings attribute "is_template" is not in`},
		{"a nested attribute is not a setting", false, "      main_only = bool", "      main_only_two = bool", ""},
		{"no allowed_keys", true, "allowed_keys = [", "allowed = [", "no allowed_keys found"},
		{"no settings variable", false, `variable "settings" {`, `variable "setting" {`, "no settings attributes found"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e, v := entries, variables
			var err error
			if tt.inEntries {
				e, err = replace(entries, tt.from, tt.to)
			} else {
				v, err = replace(variables, tt.from, tt.to)
			}
			if err != nil {
				t.Fatal(err)
			}
			if tt.want == "" { // a nested attribute's name is not a setting's key
				if got := entryKeyProblems(e, v); len(got) != 0 {
					t.Errorf("a nested attribute changed the verdict: %q", got)
				}
				return
			}
			wantProblem(t, entryKeyProblems(e, v), tt.want)
		})
	}
}
