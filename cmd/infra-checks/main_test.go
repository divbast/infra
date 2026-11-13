// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

package main

import (
	"bytes"
	"strings"
	"testing"
)

// secret stands for the sensitive values a JSON plan holds in full.
const secret = "s3cr3t-value"

func plan(checks string) string {
	return `{"variables": {"key": {"value": "` + secret + `"}}, "checks": [` + checks + `]}`
}

const (
	good = `{"address": {"to_display": "check.fork_pr_approval"}, "status": "pass"}`
	bad  = `{"address": {"to_display": "check.immutable_releases"}, "status": "fail"}`
)

// TestRun pipes plans into the command as drift.yml does, and checks its
// exit code, what it prints, and that it never prints the plan.
func TestRun(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name           string
		args           []string
		stdin          string
		code           int
		stdout, stderr string // all of stdout; in stderr
	}{
		{name: "every check passed", stdin: plan(good + "," + good), code: 0, stdout: "infra-checks: 2 checks, all passed\n"},
		{
			name: "a check failed", stdin: plan(good + "," + bad), code: 1,
			stdout: "check failed: check.immutable_releases\n", stderr: "1 of 2 checks did not pass",
		},
		{name: "no checks", stdin: plan(""), code: 1, stderr: "no check results"},
		{name: "not a plan", stdin: secret, code: 2, stderr: "not the JSON of a plan"},
		{name: "nothing", stdin: "", code: 2, stderr: "not the JSON of a plan"},
		{name: "an argument", args: []string{"tfplan"}, stdin: plan(good), code: 2, stderr: "usage"},
		{name: "help", args: []string{"-h"}, stdin: plan(good), code: 0, stderr: "usage"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			var stdout, stderr bytes.Buffer
			code := run(tt.args, strings.NewReader(tt.stdin), &stdout, &stderr)
			if code != tt.code {
				t.Errorf("exit %d, want %d; stderr:\n%s", code, tt.code, stderr.String())
			}
			if stdout.String() != tt.stdout {
				t.Errorf("stdout %q, want %q", stdout.String(), tt.stdout)
			}
			if !strings.Contains(stderr.String(), tt.stderr) {
				t.Errorf("stderr does not say %q:\n%s", tt.stderr, stderr.String())
			}
			if strings.Contains(stdout.String()+stderr.String(), secret) {
				t.Error("printed the plan")
			}
		})
	}
}
