// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

package planchecks_test

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"

	"github.com/divbast/infra/internal/planchecks"
)

// secret stands for the sensitive values a JSON plan holds in full.
const secret = "s3cr3t-value"

// plan returns what tofu show -json prints for a plan whose check blocks
// ended with statuses, by address, beside a resource change and a
// variable holding secret.
func plan(statuses ...string) string {
	var checks []string
	for i := 0; i+1 < len(statuses); i += 2 {
		checks = append(checks, fmt.Sprintf(`{
			"address": {"kind": "check", "name": %[1]q, "to_display": "check.%[1]s"},
			"status": %[2]q,
			"instances": [{"address": {"to_display": "check.%[1]s"}, "status": %[2]q,
				"problems": [{"message": "x"}]}]
		}`, statuses[i], statuses[i+1]))
	}
	return `{
		"format_version": "1.2",
		"variables": {"renovate_app_private_key": {"value": "` + secret + `"}},
		"resource_changes": [{"address": "x", "change": {"after": {"value": "` + secret + `"}}}],
		"checks": [` + strings.Join(checks, ",") + `]
	}`
}

// TestRead decodes each check's address and status, and nothing else.
func TestRead(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		plan   string
		checks []planchecks.Check
		failed []string
	}{
		{
			name: "every check passed",
			plan: plan("a", "pass", "b", "pass"),
			checks: []planchecks.Check{
				{Address: "check.a", Status: "pass"}, {Address: "check.b", Status: "pass"},
			},
		},
		{
			name: "a check failed",
			plan: plan("a", "pass", "b", "fail"),
			checks: []planchecks.Check{
				{Address: "check.a", Status: "pass"}, {Address: "check.b", Status: "fail"},
			},
			failed: []string{"check.b"},
		},
		{
			name: "one in error and one unknown",
			plan: plan("a", "error", "b", "unknown", "c", "pass"),
			checks: []planchecks.Check{
				{Address: "check.a", Status: "error"}, {Address: "check.b", Status: "unknown"}, {Address: "check.c", Status: "pass"},
			},
			failed: []string{"check.a", "check.b"},
		},
		{name: "no checks", plan: plan()},
		{name: "no checks key", plan: `{"format_version": "1.2"}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			checks, err := planchecks.Read(strings.NewReader(tt.plan))
			if err != nil {
				t.Fatal(err)
			}
			if !slices.Equal(checks, tt.checks) {
				t.Errorf("checks %+v, want %+v", checks, tt.checks)
			}
			if failed := planchecks.Failed(checks); !slices.Equal(failed, tt.failed) {
				t.Errorf("failed %q, want %q", failed, tt.failed)
			}
		})
	}
}

// TestReadRefuses refuses what is not a plan's JSON, without echoing any
// of it.
func TestReadRefuses(t *testing.T) {
	t.Parallel()
	for name, data := range map[string]string{
		"empty":                 "",
		"not JSON":              secret,
		"truncated":             plan("a", "pass")[:40] + secret,
		"not an object":         `["` + secret + `"]`,
		"checks not a list":     `{"checks": {"value": "` + secret + `"}}`,
		"a status not a string": `{"checks": [{"address": {"to_display": "check.a"}, "status": 17}]}`,
		"no address":            `{"checks": [{"status": "pass"}]}`,
		"no status":             `{"checks": [{"address": {"to_display": "check.a"}}]}`,
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			_, err := planchecks.Read(strings.NewReader(data))
			if !errors.Is(err, planchecks.ErrUnreadable) {
				t.Fatalf("got %v, not ErrUnreadable", err)
			}
			if strings.Contains(err.Error(), secret) {
				t.Errorf("%q echoes the plan", err)
			}
		})
	}
}
