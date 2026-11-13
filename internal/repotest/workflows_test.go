// SPDX-License-Identifier: BSD-2-Clause
// SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

package repotest_test

import (
	"maps"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"
)

// tofuWorkflows are the workflows that run tofu with the org-admin App
// token.
var tofuWorkflows = []string{"plan.yml", "apply.yml", "drift.yml"}

// installArgs is what each tofu workflow's mise step installs: only what
// the job runs, since every other tool in mise.toml would be one more
// download executing next to the admin token.
var installArgs = map[string]string{
	"plan.yml":  "aqua:opentofu/opentofu",
	"apply.yml": "aqua:opentofu/opentofu core:go",
	"drift.yml": "aqua:opentofu/opentofu core:go",
}

// workflowCheck is one property of the workflows that no linter checks,
// each a way the tofu jobs could quietly do the wrong thing.
type workflowCheck struct {
	name    string
	check   func(workflows map[string]string) []string
	mutants []workflowMutant
}

// workflowMutant changes the workflows to break the property its check
// holds. from must be in file, so that a mutant never equals the original.
type workflowMutant struct {
	name, file, from, to string
	remove               bool // the file, instead
}

var workflowChecks = []workflowCheck{
	{
		name:  "every expected workflow exists",
		check: expectedWorkflowsExist,
		mutants: []workflowMutant{
			{name: "drift.yml removed", file: "drift.yml", remove: true},
		},
	},
	{
		// An empty token makes the provider fall back to gh's token or to
		// anonymous access without an error
		// (integrations/terraform-provider-github#3562).
		name:  "an empty-token guard comes before the first tofu init",
		check: emptyTokenGuarded,
		mutants: []workflowMutant{
			{
				name: "apply.yml without the guard", file: "apply.yml",
				from: `run: ': "${GITHUB_TOKEN:?the App token is empty}"'`, to: "run: 'true'",
			},
			{
				name: "drift.yml initialising before the guard", file: "drift.yml",
				from: "      - name: Refuse an empty token\n", to: "      - run: tofu init -input=false\n      - name: Refuse an empty token\n",
			},
			{
				name: "plan.yml without tofu init", file: "plan.yml",
				from: "run: tofu init -input=false -lockfile=readonly", to: "run: tofu version",
			},
		},
	},
	// B2 has no locking, so every tofu run queues on one group.
	{
		name:  "every tofu job is in concurrency group tofu",
		check: tofuConcurrency("group", "tofu"),
		mutants: []workflowMutant{
			{name: "drift.yml in its own group", file: "drift.yml", from: "      group: tofu\n", to: "      group: tofu-drift\n"},
		},
	},
	{
		name:  "every tofu job's concurrency queues",
		check: tofuConcurrency("queue", "max"),
		mutants: []workflowMutant{
			{name: "apply.yml replacing its pending run", file: "apply.yml", from: "      queue: max\n", to: "      queue: single\n"},
		},
	},
	{
		name:  "no newer run cancels a tofu job, such as an apply",
		check: tofuConcurrency("cancel-in-progress", "false"),
		mutants: []workflowMutant{
			{name: "plan.yml cancelling", file: "plan.yml", from: "      cancel-in-progress: false\n", to: "      cancel-in-progress: true\n"},
		},
	},
	// A skipped job reports success, even as a required check, so a fork's
	// PR must fail the plan job rather than skip it.
	{
		name:  "the plan job has no job-level if",
		check: planJobHasNoIf,
		mutants: []workflowMutant{
			{
				name: "plan.yml skipping a fork's PR", file: "plan.yml",
				from: "  plan:\n    name: plan\n", to: "  plan:\n    name: plan\n    if: github.event.pull_request.head.repo.full_name == github.repository\n",
			},
		},
	},
	{
		name:  "a step fails a fork's pull request",
		check: planRefusesForks,
		mutants: []workflowMutant{
			{name: "plan.yml without the step", file: "plan.yml", from: "- name: Refuse a fork's pull request", to: "- name: Read the head repository"},
		},
	},
	{
		name:  "the jobs holding the admin token install only what they run",
		check: installOnlyWhatTheyRun,
		mutants: []workflowMutant{
			{
				name: "apply.yml installing one more", file: "apply.yml",
				from: "install_args: " + installArgs["apply.yml"] + "\n", to: "install_args: " + installArgs["apply.yml"] + " aqua:casey/just\n",
			},
			{
				name: "drift.yml installing everything", file: "drift.yml",
				from: "        with:\n          install_args: " + installArgs["drift.yml"] + "\n", to: "",
			},
		},
	},
	// Secrets reach only the steps that use them, never every step.
	{
		name:  "no credentials in job-level env",
		check: noJobLevelCredentials,
		mutants: []workflowMutant{
			{
				name: "plan.yml giving every step the passphrase", file: "plan.yml",
				from: "      TF_IN_AUTOMATION: 'true'\n", to: "      TF_IN_AUTOMATION: 'true'\n      TF_VAR_state_passphrase: ${{ secrets.STATE_PASSPHRASE }}\n",
			},
			{
				name: "apply.yml giving every step the B2 key", file: "apply.yml",
				from: "      TF_IN_AUTOMATION: 'true'\n", to: "      TF_IN_AUTOMATION: 'true'\n      AWS_SECRET_ACCESS_KEY: ${{ secrets.B2_APPLICATION_KEY }}\n",
			},
		},
	},
	// tofu show -json prints sensitive values in full; the repo is public.
	{
		name:  "tofu show -json goes only straight into a filter printing addresses",
		check: planJSONFiltered,
		mutants: []workflowMutant{
			{name: "plan.yml summarising the JSON plan", file: "plan.yml", from: "tofu show -no-color tfplan", to: "tofu show -json tfplan"},
			{name: "drift.yml keeping a copy", file: "drift.yml", from: "tofu show -json tfplan | ", to: "tofu show -json tfplan | tee plan.json | "},
			{name: "drift.yml filtering with jq", file: "drift.yml", from: "| .bin/infra-checks", to: "| jq -e '.checks'"},
			{
				name: "drift.yml printing the plan when a check fails", file: "drift.yml",
				from: "| .bin/infra-checks", to: "| .bin/infra-checks || tofu show -json tfplan",
			},
		},
	},
	// What the provider cannot manage is set after each apply; a repo
	// created by that apply would otherwise not exist yet.
	{
		name:  "the settings outside the provider are set after tofu apply",
		check: settingsAfterApply,
		mutants: []workflowMutant{
			{name: "apply.yml applying nothing", file: "apply.yml", from: "run: tofu apply -input=false tfplan", to: "run: tofu show -no-color tfplan"},
			{
				name: "apply.yml setting them before the apply", file: "apply.yml",
				from: "      - name: Apply\n", to: "      - run: .bin/infra-settings\n      - name: Apply\n",
			},
			{
				name: "apply.yml running a binary it did not build", file: "apply.yml",
				from: "run: go build -o .bin/ ./cmd/infra-settings", to: "run: 'true'",
			},
		},
	},
	// Nothing checks a process substitution's exit status: a failing tofu
	// there leaves its output empty, and the step carries on with none.
	{
		name:  "no tofu runs inside a process substitution",
		check: noTofuProcessSubstitution,
		mutants: []workflowMutant{
			{name: "apply.yml reading the apply's output", file: "apply.yml", from: "run: tofu apply -input=false tfplan", to: "run: cat <(tofu apply -input=false tfplan)"},
		},
	},
	// checks.tf reads the settings back, and a failed check is only a
	// warning in a plan: the drift run must turn one red.
	{
		name:  "a failed check fails the drift run",
		check: failedCheckFailsDrift,
		mutants: []workflowMutant{
			{name: "drift.yml ignoring the filter", file: "drift.yml", from: "| .bin/infra-checks", to: "| .bin/infra-checks || true"},
			{
				name: "drift.yml running a filter it did not build", file: "drift.yml",
				from: "run: go build -o .bin/ ./cmd/infra-checks", to: "run: 'true'",
			},
			{
				name: "drift.yml carrying on", file: "drift.yml",
				from: "      - name: Fail on any failed check\n", to: "      - name: Fail on any failed check\n        continue-on-error: true\n",
			},
		},
	},
	// These override the provider's owner or token (#3576, and the
	// documented GITHUB_OWNER bug).
	{
		name:  "no workflow overrides the provider's owner or auth",
		check: noProviderOverrides,
		mutants: []workflowMutant{
			{
				name: "apply.yml naming the owner", file: "apply.yml",
				from: "          GITHUB_TOKEN: ${{ steps.token.outputs.token }}\n", to: "          GITHUB_TOKEN: ${{ steps.token.outputs.token }}\n          GITHUB_OWNER: divbast\n",
			},
		},
	},
	// A skipped required check counts as passing, so the aggregator always
	// runs.
	{
		name:  "the required job runs always()",
		check: requiredRunsAlways,
		mutants: []workflowMutant{
			{name: "ci.yml's required job skipping", file: "ci.yml", from: "    if: always()\n", to: ""},
		},
	},
}

// TestWorkflowProperties runs each check over the workflows as they are,
// then over each of its mutants, which it must refuse.
func TestWorkflowProperties(t *testing.T) {
	t.Parallel()
	workflows := readWorkflows(t)
	for _, c := range workflowChecks {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			for _, p := range c.check(workflows) {
				t.Error(p)
			}
			if len(c.mutants) == 0 {
				t.Fatal("no mutant shows this check can fail")
			}
			for _, m := range c.mutants {
				t.Run(m.name, func(t *testing.T) {
					t.Parallel()
					mutant := maps.Clone(workflows)
					if m.remove {
						delete(mutant, m.file)
					} else {
						var err error
						if mutant[m.file], err = replace(workflows[m.file], m.from, m.to); err != nil {
							t.Fatalf("%s: %v", m.file, err)
						}
					}
					if len(c.check(mutant)) == 0 {
						t.Error("passes")
					}
				})
			}
		})
	}
}

func expectedWorkflowsExist(workflows map[string]string) []string {
	var problems []string
	for _, f := range []string{"ci.yml", "plan.yml", "apply.yml", "drift.yml", "renovate.yml"} {
		if _, ok := workflows[f]; !ok {
			problems = append(problems, ".github/workflows/"+f+" is missing")
		}
	}
	return problems
}

// firstLine returns the number of the first line holding s, or 0.
func firstLine(lines []line, s string) int {
	if i := slices.IndexFunc(lines, func(l line) bool { return strings.Contains(l.text, s) }); i >= 0 {
		return lines[i].n
	}
	return 0
}

func emptyTokenGuarded(workflows map[string]string) []string {
	var problems []string
	for _, f := range present(workflows, tofuWorkflows) {
		lines := linesOf(workflows[f])
		guard, init := firstLine(lines, "GITHUB_TOKEN:?"), firstLine(lines, "tofu init")
		switch {
		case init == 0:
			problems = append(problems, f+": runs no tofu init")
		case guard == 0 || guard > init:
			problems = append(problems, f+": no empty-token guard before the first tofu init")
		}
	}
	return problems
}

// present returns the files of names that workflows holds: a missing one
// is expectedWorkflowsExist's to report.
func present(workflows map[string]string, names []string) []string {
	return slices.DeleteFunc(slices.Clone(names), func(f string) bool {
		_, ok := workflows[f]
		return !ok
	})
}

// tofuRun matches a line that runs tofu.
var tofuRun = regexp.MustCompile(`(^|[\s;|&(])tofu (init|plan|apply|show|output)\b`)

// tofuJobs returns each job of a workflow that runs tofu, by name.
func tofuJobs(workflow string) map[string][]line {
	jobs := jobsOf(linesOf(workflow))
	maps.DeleteFunc(jobs, func(_ string, job []line) bool {
		return !slices.ContainsFunc(job, func(l line) bool { return tofuRun.MatchString(l.text) })
	})
	return jobs
}

// tofuConcurrency returns a check that every job running tofu sets key to
// want in its own concurrency.
func tofuConcurrency(key, want string) func(map[string]string) []string {
	return func(workflows map[string]string) []string {
		var problems []string
		for _, f := range present(workflows, tofuWorkflows) {
			jobs := tofuJobs(workflows[f])
			if len(jobs) == 0 {
				problems = append(problems, f+": no job runs tofu")
			}
			for _, name := range slices.Sorted(maps.Keys(jobs)) {
				if got, ok := block(jobs[name], 4, "concurrency")[key]; !ok || got != want {
					problems = append(problems, f+": job "+name+" does not set concurrency "+key+": "+want)
				}
			}
		}
		return problems
	}
}

func planJobHasNoIf(workflows map[string]string) []string {
	job, ok := jobsOf(linesOf(workflows["plan.yml"]))["plan"]
	if !ok {
		return []string{"plan.yml: no plan job"}
	}
	if _, ok := field(job, 4, "if"); ok {
		return []string{"plan.yml: the plan job has a job-level if, which skips (and so passes) on a fork's PR"}
	}
	return nil
}

func planRefusesForks(workflows map[string]string) []string {
	for _, step := range steps(jobsOf(linesOf(workflows["plan.yml"]))["plan"]) {
		if name, _ := stepField(step, "name"); name == "Refuse a fork's pull request" {
			return nil
		}
	}
	return []string{"plan.yml: no step failing a fork's pull request"}
}

// usesMise reports whether l is a step's uses: line for jdx/mise-action.
func usesMise(l line) bool {
	return strings.HasPrefix(strings.TrimPrefix(strings.TrimSpace(l.text), "- "), "uses: jdx/mise-action@")
}

func installOnlyWhatTheyRun(workflows map[string]string) []string {
	var problems []string
	for _, f := range present(workflows, tofuWorkflows) {
		found := false
		for _, job := range jobsOf(linesOf(workflows[f])) {
			for _, step := range steps(job) {
				if !slices.ContainsFunc(step, usesMise) {
					continue
				}
				found = true
				if args := block(step, indent(step[0].text)+2, "with")["install_args"]; args != installArgs[f] {
					problems = append(problems, f+":"+strconv.Itoa(step[0].n)+": mise-action installs "+
						strconv.Quote(args)+", not only "+strconv.Quote(installArgs[f]))
				}
			}
		}
		if !found {
			problems = append(problems, f+": no mise-action step")
		}
	}
	return problems
}

// credential matches a credential set for a whole workflow or job.
var credential = regexp.MustCompile(`^( {2}| {6})(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|TF_VAR_[a-z_]+):`)

func noJobLevelCredentials(workflows map[string]string) []string {
	var problems []string
	for _, f := range present(workflows, tofuWorkflows) {
		for _, l := range linesOf(workflows[f]) {
			if credential.MatchString(l.text) {
				problems = append(problems, f+":"+strconv.Itoa(l.n)+": credentials in job-level env are visible to every step")
			}
		}
	}
	return problems
}

// filteredPlanJSON is the one way tofu show -json may run: piped straight
// into infra-checks, which decodes only the checks' addresses and statuses
// and prints only addresses, and into nothing after it.
var filteredPlanJSON = regexp.MustCompile(`^(?:run:\s+)?tofu show -json\s+[^\s|;&<>]+\s*\|\s*\.bin/infra-checks$`)

func planJSONFiltered(workflows map[string]string) []string {
	var problems []string
	for _, f := range slices.Sorted(maps.Keys(workflows)) {
		for _, l := range linesOf(workflows[f]) {
			if strings.Contains(l.text, "tofu show -json") && !filteredPlanJSON.MatchString(strings.TrimSpace(l.text)) {
				problems = append(problems, f+":"+strconv.Itoa(l.n)+
					": tofu show -json not piped straight into .bin/infra-checks, which prints only addresses")
			}
		}
	}
	return problems
}

func settingsAfterApply(workflows map[string]string) []string {
	lines := linesOf(workflows["apply.yml"])
	built := firstLine(lines, "go build -o .bin/ ./cmd/infra-settings")
	applied, set := firstLine(lines, "run: tofu apply"), firstLine(lines, ".bin/infra-settings")
	switch {
	case applied == 0 || set == 0 || set < applied:
		return []string{"apply.yml: .bin/infra-settings does not run after tofu apply"}
	case built == 0 || built > set:
		return []string{"apply.yml: .bin/infra-settings is not built from ./cmd/infra-settings before it runs"}
	}
	return nil
}

// substitution matches tofu run inside a process substitution.
var substitution = regexp.MustCompile(`<\(\s*tofu `)

func noTofuProcessSubstitution(workflows map[string]string) []string {
	var problems []string
	for _, f := range slices.Sorted(maps.Keys(workflows)) {
		for _, l := range linesOf(workflows[f]) {
			if substitution.MatchString(l.text) {
				problems = append(problems, f+":"+strconv.Itoa(l.n)+
					": tofu runs inside a process substitution, where its failure goes unnoticed")
			}
		}
	}
	return problems
}

// failedCheckFailsDrift wants a drift.yml step piping the plan into
// infra-checks, whose own tests see it fail on a check that did not pass,
// built from this commit before it runs, and a step that does not carry on
// when it fails.
func failedCheckFailsDrift(workflows map[string]string) []string {
	lines := linesOf(workflows["drift.yml"])
	built := firstLine(lines, "go build -o .bin/ ./cmd/infra-checks")
	for _, job := range jobsOf(lines) {
		for _, step := range steps(job) {
			at := slices.IndexFunc(step, func(l line) bool { return filteredPlanJSON.MatchString(strings.TrimSpace(l.text)) })
			if at < 0 {
				continue
			}
			if v, ok := stepField(step, "continue-on-error"); ok && v != "false" {
				return []string{"drift.yml:" + strconv.Itoa(step[0].n) + ": the step that fails on a failed check carries on"}
			}
			if built == 0 || built > step[at].n {
				return []string{"drift.yml: .bin/infra-checks is not built from ./cmd/infra-checks before it runs"}
			}
			return nil
		}
	}
	return []string{"drift.yml: a failed check does not fail the drift run"}
}

// override matches a variable that overrides the provider's owner or auth.
var override = regexp.MustCompile(`GITHUB_OWNER|GITHUB_ORGANIZATION|GITHUB_APP_`)

func noProviderOverrides(workflows map[string]string) []string {
	var problems []string
	for _, f := range slices.Sorted(maps.Keys(workflows)) {
		for _, l := range linesOf(workflows[f]) {
			if override.MatchString(l.text) {
				problems = append(problems, f+":"+strconv.Itoa(l.n)+": sets a variable that overrides the provider's owner or auth")
			}
		}
	}
	return problems
}

func requiredRunsAlways(workflows map[string]string) []string {
	job, ok := jobsOf(linesOf(workflows["ci.yml"]))["required"]
	if !ok {
		return []string{"ci.yml: no required job"}
	}
	if v, _ := field(job, 4, "if"); v != "always()" {
		return []string{"ci.yml: the required job does not run always()"}
	}
	return nil
}
