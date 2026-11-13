// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

package settings_test

import (
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/divbast/infra/internal/settings"
)

// token has the shape of an App installation token, and is no token.
var token = "ghs_" + strings.Repeat("F", 36)

// github is a fake of the four REST endpoints settings calls, which
// records each request it is sent.
type github struct {
	t        *testing.T
	defaults string         // the defaults GET's body
	fail     map[string]int // status by "METHOD /path", instead of success

	mu    sync.Mutex
	calls []string // "METHOD /path", and " body" when it has one
}

// serve starts g, closed when the test ends, and returns a client for it.
func (g *github) serve() *settings.Client {
	mux := http.NewServeMux()
	ok := func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) }
	mux.HandleFunc("PUT /repos/{owner}/{repo}/private-vulnerability-reporting", ok)
	mux.HandleFunc("PUT /repos/{owner}/{repo}/immutable-releases", ok)
	mux.HandleFunc("PUT /orgs/{org}/actions/permissions/fork-pr-contributor-approval", ok)
	mux.HandleFunc("GET /orgs/{org}/code-security/configurations/defaults", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, g.defaults)
	})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			g.t.Error(err)
		}
		call := r.Method + " " + r.URL.EscapedPath()
		g.mu.Lock()
		g.calls = append(g.calls, strings.TrimSpace(call+" "+string(body)))
		g.mu.Unlock()
		for header, want := range map[string]string{
			"Authorization":        "Bearer " + token,
			"Accept":               "application/vnd.github+json",
			"X-Github-Api-Version": "2022-11-28",
		} {
			if got := r.Header.Get(header); got != want {
				g.t.Errorf("%s: %s is %q, not %q", call, header, got, want)
			}
		}
		if len(body) > 0 && r.Header.Get("Content-Type") != "application/json" {
			g.t.Errorf("%s: a body sent as %q", call, r.Header.Get("Content-Type"))
		}
		if status, ok := g.fail[call]; ok {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(status)
			_, _ = io.WriteString(w, `{"message":"refused by the fake","status":"`+http.StatusText(status)+`"}`)
			return
		}
		mux.ServeHTTP(w, r)
	}))
	g.t.Cleanup(srv.Close)
	return &settings.Client{API: srv.URL, Token: token, HTTP: srv.Client()}
}

func (g *github) recorded() []string {
	g.mu.Lock()
	defer g.mu.Unlock()
	return slices.Clone(g.calls)
}

const (
	pvrOne    = "PUT /repos/divbast/one/private-vulnerability-reporting"
	pvrTwo    = "PUT /repos/divbast/two/private-vulnerability-reporting"
	forkPR    = "PUT /orgs/divbast/actions/permissions/fork-pr-contributor-approval"
	forkBody  = ` {"approval_policy":"all_external_contributors"}`
	defaults  = "GET /orgs/divbast/code-security/configurations/defaults"
	immutable = "PUT /repos/divbast/two/immutable-releases"
)

// TestApply sets everything against a fake GitHub and compares every call
// it made, in order, with what each case asks for. Three cases keep the
// names of the shell scripts' cases they port: sets_both_and_passes from
// assert-unmanaged.sh, enables_each_repo and none_asked_for from
// immutable-releases.sh. Their four failure cases are TestRun's, in
// cmd/infra-settings, since each was about the exit status.
func TestApply(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		repos    settings.Repos
		defaults string
		calls    []string
		summary  string
	}{
		{
			// Private vulnerability reporting and the fork PR policy, the
			// two settings assert-unmanaged.sh made, beside one immutable repo
			name:     "sets_both_and_passes",
			repos:    settings.Repos{All: []string{"one", "two"}, Immutable: []string{"two"}},
			defaults: "[]",
			calls:    []string{pvrOne, pvrTwo, forkPR + forkBody, defaults, immutable},
			summary:  "private vulnerability reporting on for 2 repos; fork PR approval required; no default code security configuration; immutable releases on for 1 repos",
		},
		{
			// No repo asks for immutable releases: none is set, and nothing
			// else changes
			name:     "none_asked_for",
			repos:    settings.Repos{All: []string{"one", "two"}},
			defaults: "[]",
			calls:    []string{pvrOne, pvrTwo, forkPR + forkBody, defaults},
			summary:  "private vulnerability reporting on for 2 repos; fork PR approval required; no default code security configuration; immutable releases on for 0 repos",
		},
		{
			name:     "enables_each_repo",
			repos:    settings.Repos{All: []string{"one", "two"}, Immutable: []string{"one", "two"}},
			defaults: "[]",
			calls: []string{
				pvrOne, pvrTwo, forkPR + forkBody, defaults,
				"PUT /repos/divbast/one/immutable-releases", "PUT /repos/divbast/two/immutable-releases",
			},
			summary: "private vulnerability reporting on for 2 repos; fork PR approval required; no default code security configuration; immutable releases on for 2 repos",
		},
		{
			name:     "a_name_to_escape",
			repos:    settings.Repos{All: []string{".github", "a b"}, Immutable: []string{".github"}},
			defaults: "[]",
			calls: []string{
				"PUT /repos/divbast/.github/private-vulnerability-reporting", "PUT /repos/divbast/a%20b/private-vulnerability-reporting",
				forkPR + forkBody, defaults, "PUT /repos/divbast/.github/immutable-releases",
			},
			summary: "private vulnerability reporting on for 2 repos; fork PR approval required; no default code security configuration; immutable releases on for 1 repos",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			g := &github{t: t, defaults: tt.defaults}
			summary, err := settings.Apply(t.Context(), g.serve(), "divbast", tt.repos)
			if err != nil {
				t.Fatal(err)
			}
			if summary != tt.summary {
				t.Errorf("summary %q, want %q", summary, tt.summary)
			}
			if got := g.recorded(); !slices.Equal(got, tt.calls) {
				t.Errorf("calls\n%s\nwant\n%s", strings.Join(got, "\n"), strings.Join(tt.calls, "\n"))
			}
		})
	}
}

// TestApplyRefusesDefaults has a default code security configuration
// answer the GET, and wants each one named and nothing set after it.
func TestApplyRefusesDefaults(t *testing.T) {
	t.Parallel()
	g := &github{t: t, defaults: `[
		{"default_for_new_repos":"all","configuration":{"id":17,"name":"GitHub recommended"}},
		{"default_for_new_repos":"public","configuration":{"id":18,"name":"Our own"}}
	]`}
	repos := settings.Repos{All: []string{"one", "two"}, Immutable: []string{"two"}}
	_, err := settings.Apply(t.Context(), g.serve(), "divbast", repos)
	if _, ok := errors.AsType[*settings.DefaultsError](err); !ok {
		t.Fatalf("got %v, not a *settings.DefaultsError", err)
	}
	for _, want := range []string{"GitHub recommended (default for all repos)", "Our own (default for public repos)"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("%q does not name %q", err, want)
		}
	}
	if got := g.recorded(); slices.Contains(got, immutable) {
		t.Errorf("set immutable releases after refusing: %q", got)
	}
}

// TestApplyFailsOnAnError answers each call in turn with 403, 404 and 500,
// and wants an error naming the call and its status, nothing called after
// it, and never the token.
func TestApplyFailsOnAnError(t *testing.T) {
	t.Parallel()
	all := []string{pvrOne, pvrTwo, forkPR + forkBody, defaults, immutable}
	for i, call := range all {
		for _, status := range []int{http.StatusForbidden, http.StatusNotFound, http.StatusInternalServerError} {
			name, _, _ := strings.Cut(call, " {")
			t.Run(name+"/"+http.StatusText(status), func(t *testing.T) {
				t.Parallel()
				g := &github{t: t, defaults: "[]", fail: map[string]int{name: status}}
				repos := settings.Repos{All: []string{"one", "two"}, Immutable: []string{"two"}}
				_, err := settings.Apply(t.Context(), g.serve(), "divbast", repos)
				if failed, ok := errors.AsType[*settings.StatusError](err); !ok || failed.Status != status {
					t.Fatalf("got %v, not a *settings.StatusError with %d", err, status)
				}
				for _, want := range []string{name, http.StatusText(status), "refused by the fake"} {
					if !strings.Contains(err.Error(), want) {
						t.Errorf("%q does not say %q", err, want)
					}
				}
				if strings.Contains(err.Error(), token) {
					t.Error("the error holds the token")
				}
				if got := g.recorded(); !slices.Equal(got, all[:i+1]) {
					t.Errorf("calls\n%s\nwant\n%s", strings.Join(got, "\n"), strings.Join(all[:i+1], "\n"))
				}
			})
		}
	}
}

// TestApplyFailsOnAnUnreadableAnswer has the defaults GET answer with
// what is not a list of configurations.
func TestApplyFailsOnAnUnreadableAnswer(t *testing.T) {
	t.Parallel()
	for _, body := range []string{"", "{}", `{"message":"x"}`, "[{"} {
		t.Run(body, func(t *testing.T) {
			t.Parallel()
			g := &github{t: t, defaults: body}
			_, err := settings.Apply(t.Context(), g.serve(), "divbast", settings.Repos{All: []string{"one"}})
			if err == nil {
				t.Fatal("passes")
			}
			if !strings.Contains(err.Error(), defaults) {
				t.Errorf("%q does not name %s", err, defaults)
			}
		})
	}
}

// TestApplyFailsWhenGitHubIsUnreachable closes the fake before the first
// call.
func TestApplyFailsWhenGitHubIsUnreachable(t *testing.T) {
	t.Parallel()
	srv := httptest.NewServer(http.NotFoundHandler())
	c := &settings.Client{API: srv.URL, Token: token, HTTP: srv.Client()}
	srv.Close()
	_, err := settings.Apply(t.Context(), c, "divbast", settings.Repos{All: []string{"one"}})
	if err == nil {
		t.Fatal("passes")
	}
	if strings.Contains(err.Error(), token) {
		t.Error("the error holds the token")
	}
}

// TestParseOutputs reads tofu output -json, and refuses each way it can be
// unreadable without echoing any of it: tofu prints sensitive outputs in
// full there.
func TestParseOutputs(t *testing.T) {
	t.Parallel()
	const secret = "s3cr3t-value"
	good := `{
		"repository_names": {"sensitive": false, "type": ["list", "string"], "value": ["ci", "infra"]},
		"immutable_release_repositories": {"sensitive": false, "type": ["list", "string"], "value": ["ci"]},
		"other": {"sensitive": true, "type": "string", "value": "` + secret + `"}
	}`
	repos, err := settings.ParseOutputs([]byte(good))
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(repos.All, []string{"ci", "infra"}) || !slices.Equal(repos.Immutable, []string{"ci"}) {
		t.Errorf("got %+v", repos)
	}
	empty, err := settings.ParseOutputs([]byte(`{
		"repository_names": {"value": ["ci"]},
		"immutable_release_repositories": {"value": []}
	}`))
	if err != nil || len(empty.Immutable) != 0 {
		t.Errorf("an empty immutable list: %+v, %v", empty, err)
	}

	bad := map[string]string{
		"not JSON":                          secret,
		"not an object":                     `["` + secret + `"]`,
		"no repository_names":               `{"immutable_release_repositories": {"value": []}}`,
		"no immutable_release_repositories": `{"repository_names": {"value": ["ci"]}}`,
		"a name not a string":               `{"repository_names": {"value": [17]}, "immutable_release_repositories": {"value": []}}`,
		"a value not a list":                `{"repository_names": {"value": "` + secret + `"}, "immutable_release_repositories": {"value": []}}`,
		"an empty name":                     `{"repository_names": {"value": ["ci", ""]}, "immutable_release_repositories": {"value": []}}`,
		"an empty immutable name":           `{"repository_names": {"value": ["ci"]}, "immutable_release_repositories": {"value": [""]}}`,
	}
	for name, data := range bad {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			_, err := settings.ParseOutputs([]byte(data))
			if err == nil {
				t.Fatal("passes")
			}
			if strings.Contains(err.Error(), secret) {
				t.Errorf("%q echoes the output", err)
			}
		})
	}
}
