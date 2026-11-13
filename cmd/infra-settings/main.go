// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

// Command infra-settings sets what the GitHub provider cannot manage,
// after every apply: private vulnerability reporting on every managed
// repository, the org's fork pull request approval policy, immutable
// releases on the repositories that ask for them, and it refuses a default
// code security configuration, naming each. checks.tf reads every one
// back, and the drift run fails when one no longer holds.
//
// Usage:
//
//	infra-settings [-org divbast] [-api https://api.github.com]
//
// It runs tofu output -json in the working directory, the root module
// after an apply, and reads the repositories from its repository_names and
// immutable_release_repositories outputs; tofu needs the state's
// credentials in the environment for that. It calls GitHub with the token
// in GH_TOKEN, in a workflow one from the divbast-infra App, and never
// prints it. On success it prints one line saying what it set.
//
// Exit codes:
//
//	0  every setting is set, or -h asked for the usage
//	1  GitHub answered a call with anything but 2xx, or could not be
//	   reached, or a default code security configuration is set; stderr
//	   says which
//	2  the command line is wrong, GH_TOKEN is empty, tofu output -json
//	   failed or is unreadable, or it names no repository
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"

	"github.com/divbast/infra/internal/settings"
)

const name = "infra-settings"

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	code := run(ctx, os.Args[1:], os.Getenv, tofuOutputs, os.Stdout, os.Stderr)
	stop()
	os.Exit(code)
}

// tofuOutputs runs tofu output -json in the working directory. Its stderr
// goes to this command's: tofu's errors carry no output values.
func tofuOutputs(ctx context.Context) ([]byte, error) {
	cmd := exec.CommandContext(ctx, "tofu", "output", "-json")
	cmd.Stderr = os.Stderr
	return cmd.Output()
}

func run(ctx context.Context, args []string, getenv func(string) string,
	outputs func(context.Context) ([]byte, error), stdout, stderr io.Writer,
) int {
	flags := flag.NewFlagSet(name, flag.ContinueOnError)
	flags.SetOutput(stderr)
	flags.Usage = func() {
		// As for complain: nowhere better to report a failed write.
		_, _ = fmt.Fprintf(stderr, "usage: %s [-org ORG] [-api URL]   (needs GH_TOKEN)\n", name)
		flags.PrintDefaults()
	}
	org := flags.String("org", "divbast", "the `ORG`anisation")
	api := flags.String("api", "https://api.github.com", "the REST API's base `URL`")
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}
	if flags.NArg() > 0 || *org == "" || *api == "" {
		complain(stderr, "unexpected argument, or an empty -org or -api")
		flags.Usage()
		return 2
	}
	token := getenv("GH_TOKEN")
	if token == "" {
		complain(stderr, "GH_TOKEN must hold a token from the divbast-infra App")
		return 2
	}

	data, err := outputs(ctx)
	if err != nil {
		complain(stderr, "tofu output -json: %v", err)
		return 2
	}
	repos, err := settings.ParseOutputs(data)
	if err != nil {
		complain(stderr, "%v", err)
		return 2
	}
	if len(repos.All) == 0 {
		complain(stderr, "tofu output names no repositories in repository_names")
		return 2
	}

	client := &settings.Client{API: *api, Token: token, HTTP: &http.Client{Timeout: time.Minute}}
	summary, err := settings.Apply(ctx, client, *org, repos)
	if err != nil {
		complain(stderr, "%v", err)
		return 1
	}
	if _, err := fmt.Fprintln(stdout, summary); err != nil {
		complain(stderr, "write the summary: %v", err)
		return 1
	}
	return 0
}

// complain writes to stderr, after the command's name.
func complain(stderr io.Writer, format string, args ...any) {
	// A failed write to stderr leaves nowhere better to report it.
	_, _ = fmt.Fprintln(stderr, name+":", fmt.Sprintf(format, args...))
}
