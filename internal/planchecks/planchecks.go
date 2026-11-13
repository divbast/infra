// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

// Package planchecks reads the results of a plan's check blocks from what
// tofu show -json prints, and nothing else of it. That JSON holds
// sensitive values in full, so only each check's address and status are
// decoded, and no error echoes any of it.
package planchecks

import (
	"encoding/json"
	"errors"
	"io"
)

// Check is one check's result in a plan.
type Check struct {
	// Address is the check's address as tofu displays it, such as
	// module.checks.check.fork_pr_approval.
	Address string
	// Status is pass, fail, error or unknown.
	Status string
}

// ErrUnreadable is every error Read returns.
var ErrUnreadable = errors.New("not the JSON of a plan, as tofu show -json prints it")

// Read decodes the checks of a plan from r. A plan without any is not an
// error: Read returns none.
func Read(r io.Reader) ([]Check, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, ErrUnreadable
	}
	var plan struct {
		Checks []struct {
			Address struct {
				ToDisplay string `json:"to_display"`
			} `json:"address"`
			Status string `json:"status"`
		} `json:"checks"`
	}
	// The decoder's own error can quote a value it met, so it is dropped.
	if json.Unmarshal(data, &plan) != nil {
		return nil, ErrUnreadable
	}
	checks := make([]Check, 0, len(plan.Checks))
	for _, c := range plan.Checks {
		if c.Address.ToDisplay == "" || c.Status == "" {
			return nil, ErrUnreadable
		}
		checks = append(checks, Check{Address: c.Address.ToDisplay, Status: c.Status})
	}
	return checks, nil
}

// Failed returns the address of each check whose status is not pass:
// fail, but also error and unknown, since neither shows the setting
// holds.
func Failed(checks []Check) []string {
	var failed []string
	for _, c := range checks {
		if c.Status != "pass" {
			failed = append(failed, c.Address)
		}
	}
	return failed
}
