// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

// Package settings sets, through GitHub's REST API, what provider 6.13.0
// cannot manage: private vulnerability reporting on every repository, the
// org's approval policy for fork pull requests, immutable releases on the
// repositories that ask for them, and the absence of any default code
// security configuration, which would fight the per-repository security
// settings OpenTofu makes. checks.tf reads each back, so the drift run
// fails when one no longer holds.
package settings

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
)

// Client calls GitHub's REST API with one token.
type Client struct {
	// API is the API's base URL, such as https://api.github.com.
	API string
	// Token is sent as a bearer token, and never printed.
	Token string
	// HTTP sends the requests.
	HTTP *http.Client
}

// Repos are the repositories the settings are for, as the root module's
// outputs name them.
type Repos struct {
	// All is every managed repository, from repository_names.
	All []string
	// Immutable are those whose releases are made immutable, from
	// immutable_release_repositories.
	Immutable []string
}

// StatusError is an answer outside 2xx.
type StatusError struct {
	// Call is the request, as "METHOD /path".
	Call string
	// Status is the answer's HTTP status code.
	Status int
	// Message is GitHub's own message from the answer, if any.
	Message string
}

func (e *StatusError) Error() string {
	msg := e.Call + ": " + strconv.Itoa(e.Status) + " " + http.StatusText(e.Status)
	if e.Message != "" {
		msg += ": " + e.Message
	}
	return msg
}

// Default is one default code security configuration.
type Default struct {
	// Name is the configuration's name.
	Name string
	// For is the repositories it is the default for: all, public,
	// private_and_internal or none.
	For string
}

// DefaultsError is the refusal when the org has a default code security
// configuration. Removing one is a person's decision, so it is never
// undone here.
type DefaultsError struct {
	// Defaults names each default configuration.
	Defaults []Default
}

func (e *DefaultsError) Error() string {
	var b strings.Builder
	b.WriteString("a default code security configuration is set; remove it so OpenTofu's per-repo settings stand:")
	for _, d := range e.Defaults {
		fmt.Fprintf(&b, "\n  %s (default for %s repos)", d.Name, d.For)
	}
	return b.String()
}

// Apply makes every setting, in the order the shell scripts it replaces
// did, and stops at the first call that fails:
//
//   - private vulnerability reporting on, for each repository, so that
//     security reports arrive privately on the affected repo;
//   - the org's fork pull requests from anyone outside it waiting for a
//     maintainer's approval before their workflows run;
//   - no default code security configuration, or a *DefaultsError;
//   - immutable releases on, for each repository asking for them.
//
// A failed call is a *StatusError, or the transport's error. It returns
// one line saying what was set.
func Apply(ctx context.Context, c *Client, org string, r Repos) (string, error) {
	o := url.PathEscape(org)
	for _, repo := range r.All {
		if err := c.call(ctx, http.MethodPut, "/repos/"+o+"/"+url.PathEscape(repo)+"/private-vulnerability-reporting", nil, nil); err != nil {
			return "", err
		}
	}
	policy := map[string]string{"approval_policy": "all_external_contributors"}
	if err := c.call(ctx, http.MethodPut, "/orgs/"+o+"/actions/permissions/fork-pr-contributor-approval", policy, nil); err != nil {
		return "", err
	}
	var defaults []struct {
		For           string `json:"default_for_new_repos"`
		Configuration struct {
			Name string `json:"name"`
		} `json:"configuration"`
	}
	if err := c.call(ctx, http.MethodGet, "/orgs/"+o+"/code-security/configurations/defaults", nil, &defaults); err != nil {
		return "", err
	}
	if len(defaults) > 0 {
		refused := &DefaultsError{}
		for _, d := range defaults {
			refused.Defaults = append(refused.Defaults, Default{Name: d.Configuration.Name, For: d.For})
		}
		return "", refused
	}
	for _, repo := range r.Immutable {
		if err := c.call(ctx, http.MethodPut, "/repos/"+o+"/"+url.PathEscape(repo)+"/immutable-releases", nil, nil); err != nil {
			return "", err
		}
	}
	return fmt.Sprintf("private vulnerability reporting on for %d repos; fork PR approval required; "+
		"no default code security configuration; immutable releases on for %d repos", len(r.All), len(r.Immutable)), nil
}

// maxAnswer bounds how much of an answer is read.
const maxAnswer = 1 << 20

// call sends one request, with body as JSON when it is not nil, and
// decodes a 2xx answer into into when that is not nil.
func (c *Client) call(ctx context.Context, method, path string, body, into any) error {
	name := method + " " + path
	var payload io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("%s: %w", name, err)
		}
		payload = bytes.NewReader(data)
	}
	req, err := http.NewRequestWithContext(ctx, method, strings.TrimSuffix(c.API, "/")+path, payload)
	if err != nil {
		return fmt.Errorf("%s: %w", name, err)
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("Authorization", "Bearer "+c.Token)
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("User-Agent", "infra-settings")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return fmt.Errorf("%s: %w", name, err)
	}
	defer func() { _ = resp.Body.Close() }()
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxAnswer))
	if err != nil {
		return fmt.Errorf("%s: read the answer: %w", name, err)
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		var answer struct {
			Message string `json:"message"`
		}
		// GitHub's error answers carry a message; anything else leaves it out.
		_ = json.Unmarshal(data, &answer)
		return &StatusError{Call: name, Status: resp.StatusCode, Message: answer.Message}
	}
	if into != nil {
		if err := json.Unmarshal(data, into); err != nil {
			return fmt.Errorf("%s: an answer that is not what GitHub documents: %w", name, err)
		}
	}
	return nil
}

// ErrOutputs is wrapped by every error ParseOutputs returns.
var ErrOutputs = errors.New("unreadable tofu output -json")

// ParseOutputs reads the two outputs Repos is made of from what tofu output
// -json prints. tofu prints sensitive outputs there in full, so no error
// echoes any of it: each names only the output and what is wrong with it.
func ParseOutputs(data []byte) (Repos, error) {
	var outputs map[string]json.RawMessage
	if json.Unmarshal(data, &outputs) != nil {
		return Repos{}, fmt.Errorf("%w: not a JSON object", ErrOutputs)
	}
	all, err := names(outputs, "repository_names")
	if err != nil {
		return Repos{}, err
	}
	immutable, err := names(outputs, "immutable_release_repositories")
	if err != nil {
		return Repos{}, err
	}
	return Repos{All: all, Immutable: immutable}, nil
}

// names reads one output's value as a list of non-empty names.
func names(outputs map[string]json.RawMessage, output string) ([]string, error) {
	raw, ok := outputs[output]
	if !ok {
		return nil, fmt.Errorf("%w: no output %s", ErrOutputs, output)
	}
	var o struct {
		Value []string `json:"value"`
	}
	if json.Unmarshal(raw, &o) != nil {
		return nil, fmt.Errorf("%w: output %s is not a list of names", ErrOutputs, output)
	}
	if slices.Contains(o.Value, "") {
		return nil, fmt.Errorf("%w: output %s holds an empty name", ErrOutputs, output)
	}
	return o.Value, nil
}
