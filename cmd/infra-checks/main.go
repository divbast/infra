// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

// Command infra-checks fails when any check block in a plan did not pass.
// A failed check is only a warning in a plan, so the drift run pipes its
// plan through this to turn one red:
//
//	tofu show -json tfplan | infra-checks
//
// The JSON plan holds sensitive values in full, and this repository's
// logs are public, so it decodes nothing of it but each check's address
// and status, and prints only addresses: one "check failed: ADDRESS" line
// on stdout for each check whose status is not pass, or one line saying
// they all passed.
//
// Exit codes:
//
//	0  every check passed, or -h asked for the usage
//	1  a check failed, ended in error or is unknown, or the plan holds no
//	   check results at all, which checks.tf would never leave it
//	2  the command line is wrong, or stdin is not the JSON of a plan
package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/divbast/infra/internal/planchecks"
)

const name = "infra-checks"

func main() {
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}

func run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet(name, flag.ContinueOnError)
	flags.SetOutput(stderr)
	flags.Usage = func() {
		// As for complain: nowhere better to report a failed write.
		_, _ = fmt.Fprintf(stderr, "usage: tofu show -json PLAN | %s\n", name)
	}
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}
	if flags.NArg() > 0 {
		complain(stderr, "unexpected argument %q: the plan comes on stdin", flags.Arg(0))
		flags.Usage()
		return 2
	}

	checks, err := planchecks.Read(stdin)
	if err != nil {
		complain(stderr, "stdin is %v", err)
		return 2
	}
	if len(checks) == 0 {
		complain(stderr, "the plan holds no check results, so nothing was checked")
		return 1
	}
	failed := planchecks.Failed(checks)
	for _, address := range failed {
		if _, err := fmt.Fprintln(stdout, "check failed:", address); err != nil {
			complain(stderr, "write a failed check: %v", err)
			return 1
		}
	}
	if len(failed) > 0 {
		complain(stderr, "%d of %d checks did not pass", len(failed), len(checks))
		return 1
	}
	if _, err := fmt.Fprintf(stdout, "%s: %d checks, all passed\n", name, len(checks)); err != nil {
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
