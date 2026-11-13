// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

package main

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

// token has the shape of an App installation token, and is no token.
var token = "ghs_" + strings.Repeat("F", 36)

// outputs is what tofu output -json prints for two repos, one of them with
// immutable releases.
const outputs = `{
	"immutable_release_repositories": {"sensitive": false, "type": ["list", "string"], "value": ["two"]},
	"repository_names": {"sensitive": false, "type": ["list", "string"], "value": ["one", "two"]}
}`

// fakeGitHub answers every PUT with 204 and the defaults GET with
// defaults, or every call with status when it is set, and counts the
// calls.
func fakeGitHub(t *testing.T, defaults string, status int) (api string, calls *atomic.Int64) {
	t.Helper()
	calls = &atomic.Int64{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		switch {
		case status != 0:
			w.WriteHeader(status)
		case r.Method == http.MethodGet:
			_, _ = io.WriteString(w, defaults)
		default:
			w.WriteHeader(http.StatusNoContent)
		}
	}))
	t.Cleanup(srv.Close)
	return srv.URL, calls
}

// TestRun runs the command as apply.yml does, and checks its exit code,
// what it prints, and that it never prints the token.
func TestRun(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		args     []string // after -api
		token    string
		outputs  string
		tofu     error // from running tofu output -json
		defaults string
		status   int // every API call's, when set
		code     int
		stdout   string // all of it
		stderr   string // in it
		noCalls  bool
	}{
		{
			name: "every setting set", token: token, outputs: outputs, defaults: "[]", code: 0,
			stdout: "private vulnerability reporting on for 2 repos; fork PR approval required; " +
				"no default code security configuration; immutable releases on for 1 repos\n",
		},
		{
			name: "a default code security configuration", token: token, outputs: outputs, code: 1,
			defaults: `[{"default_for_new_repos":"all","configuration":{"name":"GitHub recommended"}}]`,
			stderr:   "GitHub recommended (default for all repos)",
		},
		{name: "GitHub refusing", token: token, outputs: outputs, status: http.StatusForbidden, code: 1, stderr: "403 Forbidden"},
		{name: "GitHub failing", token: token, outputs: outputs, status: http.StatusInternalServerError, code: 1, stderr: "500 Internal Server Error"},
		{name: "no token", outputs: outputs, code: 2, stderr: "GH_TOKEN", noCalls: true},
		{
			name: "no repos", token: token, code: 2, stderr: "no repositories", noCalls: true,
			outputs: `{"repository_names": {"value": []}, "immutable_release_repositories": {"value": []}}`,
		},
		{name: "tofu output unreadable", token: token, outputs: "not JSON", code: 2, stderr: "tofu output", noCalls: true},
		{name: "tofu failing", token: token, tofu: errors.New("exit status 1"), code: 2, stderr: "tofu output -json: exit status 1", noCalls: true},
		{name: "an empty org", args: []string{"-org", ""}, token: token, outputs: outputs, code: 2, stderr: "usage", noCalls: true},
		{name: "an argument", args: []string{"divbast"}, token: token, outputs: outputs, code: 2, stderr: "usage", noCalls: true},
		{name: "an unknown flag", args: []string{"-repo", "one"}, token: token, outputs: outputs, code: 2, stderr: "usage", noCalls: true},
		{name: "help", args: []string{"-h"}, token: token, outputs: outputs, code: 0, stderr: "usage", noCalls: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			api, calls := fakeGitHub(t, tt.defaults, tt.status)
			env := map[string]string{"GH_TOKEN": tt.token}
			tofu := func(context.Context) ([]byte, error) { return []byte(tt.outputs), tt.tofu }
			var stdout, stderr bytes.Buffer
			code := run(t.Context(), append([]string{"-api", api}, tt.args...), func(k string) string { return env[k] }, tofu, &stdout, &stderr)
			if code != tt.code {
				t.Errorf("exit %d, want %d; stderr:\n%s", code, tt.code, stderr.String())
			}
			if tt.stdout != "" || code != 0 {
				if stdout.String() != tt.stdout {
					t.Errorf("stdout %q, want %q", stdout.String(), tt.stdout)
				}
			}
			if !strings.Contains(stderr.String(), tt.stderr) {
				t.Errorf("stderr does not say %q:\n%s", tt.stderr, stderr.String())
			}
			if strings.Contains(stdout.String()+stderr.String(), token) {
				t.Error("printed the token")
			}
			if tt.noCalls && calls.Load() != 0 {
				t.Errorf("called GitHub %d times", calls.Load())
			}
		})
	}
}

// TestRunDefaultsToGitHub checks that the usage gives api.github.com and
// the divbast org as the defaults, which apply.yml relies on by passing
// no flags.
func TestRunDefaultsToGitHub(t *testing.T) {
	t.Parallel()
	var stderr bytes.Buffer
	run(t.Context(), []string{"-h"}, func(string) string { return "" }, nil, io.Discard, &stderr)
	for _, want := range []string{`(default "https://api.github.com")`, `(default "divbast")`} {
		if !strings.Contains(stderr.String(), want) {
			t.Errorf("usage does not say %s:\n%s", want, stderr.String())
		}
	}
}
