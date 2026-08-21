package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/openshift-online/aro-ai-tools/oncall-cli/internal/ado"
	"github.com/openshift-online/aro-ai-tools/oncall-cli/internal/auth"
	"github.com/openshift-online/aro-ai-tools/oncall-cli/internal/ev2"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "builds":
		if err := runBuilds(os.Args[2:]); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "ev2":
		if err := runEV2(os.Args[2:]); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "e2e":
		if err := runE2E(os.Args[2:]); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "help", "--help", "-h":
		printUsage()
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", os.Args[1])
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println(`oncall - ARO HCP oncall dashboard CLI

Usage:
  oncall builds [--hours N] [--path PATH]   List running/recent HCP pipeline builds
  oncall ev2    [--hours N] [--path PATH]   List EV2 rollouts from HCP pipeline builds
  oncall e2e    [--hours N] [--path PATH]   List E2E step status from EV2 rollouts

Options:
  --hours N        Show builds from last N hours (default: 24)
  --path PATH      ADO folder path (default: \OneBranch\sdp-pipelines\hcp\Incremental)
  --ev2-host URL   EV2 RolloutInfra host (default: https://ev2.azure.net)

Environment:
  ADO_PAT      Personal Access Token for Azure DevOps (fallback: az CLI)
  EV2_HOST     EV2 RolloutInfra host URL (alternative to --ev2-host flag)`)
}

type options struct {
	hours   int
	path    string
	ev2Host string
}

func parseArgs(args []string) options {
	opts := options{hours: 24}
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--hours", "--hour":
			if i+1 < len(args) {
				i++
				opts.hours, _ = strconv.Atoi(args[i])
			}
		case "--path":
			if i+1 < len(args) {
				i++
				opts.path = args[i]
			}
		case "--ev2-host":
			if i+1 < len(args) {
				i++
				opts.ev2Host = args[i]
			}
		}
	}
	if opts.ev2Host == "" {
		opts.ev2Host = os.Getenv("EV2_HOST")
	}
	return opts
}

func newClient() (*ado.Client, error) {
	token, err := auth.Token()
	if err != nil {
		return nil, fmt.Errorf("authentication failed: %w", err)
	}
	return ado.NewClient(token), nil
}

func getDefinitionIDs(client *ado.Client, path string) ([]int, error) {
	defs, err := client.ListDefinitions(path)
	if err != nil {
		return nil, fmt.Errorf("list definitions: %w", err)
	}
	if len(defs) == 0 {
		return nil, fmt.Errorf("no pipeline definitions found under path %q", path)
	}
	ids := make([]int, len(defs))
	for i, d := range defs {
		ids[i] = d.ID
	}
	return ids, nil
}

func runBuilds(args []string) error {
	opts := parseArgs(args)
	client, err := newClient()
	if err != nil {
		return err
	}

	ids, err := getDefinitionIDs(client, opts.path)
	if err != nil {
		return err
	}

	builds, err := client.ListBuilds(ids, opts.hours)
	if err != nil {
		return fmt.Errorf("list builds: %w", err)
	}

	if len(builds) == 0 {
		if opts.hours > 0 {
			fmt.Printf("No builds found in the last %d hours.\n", opts.hours)
		} else {
			fmt.Println("No builds currently running.")
		}
		return nil
	}

	printBuildsTable(builds)
	return nil
}

func runEV2(args []string) error {
	opts := parseArgs(args)
	client, err := newClient()
	if err != nil {
		return err
	}

	ids, err := getDefinitionIDs(client, opts.path)
	if err != nil {
		return err
	}

	builds, err := client.ListBuilds(ids, opts.hours)
	if err != nil {
		return fmt.Errorf("list builds: %w", err)
	}

	if len(builds) == 0 {
		if opts.hours > 0 {
			fmt.Printf("No builds found in the last %d hours.\n", opts.hours)
		} else {
			fmt.Println("No builds currently running.")
		}
		return nil
	}

	type ev2Row struct {
		pipeline     string
		buildID      int
		rolloutID    string
		serviceModel string
		url          string
	}

	var rows []ev2Row
	for _, b := range builds {
		rollouts, err := client.FindEV2URLs(b.ID)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Warning: could not get EV2 URLs for build %d: %v\n", b.ID, err)
			continue
		}
		for _, r := range rollouts {
			rows = append(rows, ev2Row{
				pipeline:     b.Definition.Name,
				buildID:      b.ID,
				rolloutID:    r.RolloutID,
				serviceModel: r.ServiceModel,
				url:          r.URL,
			})
		}
	}

	if len(rows) == 0 {
		fmt.Println("No EV2 rollouts found in build logs.")
		return nil
	}

	// Print EV2 table
	fmt.Println("| # | Pipeline | Build | Rollout ID | Service Model | Link |")
	fmt.Println("|---|----------|-------|-----------|---------------|------|")
	for i, r := range rows {
		shortID := r.rolloutID
		if len(shortID) > 8 {
			shortID = shortID[:8]
		}
		fmt.Printf("| %d | %s | %d | %s | %s | [EV2](%s) |\n",
			i+1, r.pipeline, r.buildID, shortID, r.serviceModel, r.url)
	}
	return nil
}

func runE2E(args []string) error {
	opts := parseArgs(args)
	client, err := newClient()
	if err != nil {
		return err
	}

	ids, err := getDefinitionIDs(client, opts.path)
	if err != nil {
		return err
	}

	builds, err := client.ListBuilds(ids, opts.hours)
	if err != nil {
		return fmt.Errorf("list builds: %w", err)
	}

	if len(builds) == 0 {
		if opts.hours > 0 {
			fmt.Printf("No builds found in the last %d hours.\n", opts.hours)
		} else {
			fmt.Println("No builds currently running.")
		}
		return nil
	}

	// Get EV2 token
	ev2Token, err := auth.EV2Token(opts.ev2Host)
	if err != nil {
		return fmt.Errorf("EV2 authentication failed: %w", err)
	}
	ev2Client := ev2.NewClient(opts.ev2Host, ev2Token)

	type e2eRow struct {
		pipeline  string
		buildID   int
		rolloutID string
		region    string
		stepName  string
		status    string
		duration  string
		errMsg    string
	}

	var rows []e2eRow
	for _, b := range builds {
		rollouts, err := client.FindEV2URLs(b.ID)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Warning: could not get EV2 URLs for build %d: %v\n", b.ID, err)
			continue
		}
		for _, r := range rollouts {
			rollout, err := ev2Client.GetRollout(r.RolloutID, "")
			if err != nil {
				fmt.Fprintf(os.Stderr, "Warning: could not fetch rollout %s: %v\n", r.RolloutID, err)
				continue
			}
			steps := ev2.GetE2ESteps(rollout)
			for _, s := range steps {
				dur := formatDuration(s.StartTime, s.EndTime)
				rows = append(rows, e2eRow{
					pipeline:  b.Definition.Name,
					buildID:   b.ID,
					rolloutID: r.RolloutID,
					region:    s.Region,
					stepName:  s.StepName,
					status:    s.Status,
					duration:  dur,
					errMsg:    s.Error,
				})
			}
		}
	}

	if len(rows) == 0 {
		fmt.Println("No E2E steps found in rollouts.")
		return nil
	}

	// Print E2E table
	fmt.Println("| # | Pipeline | Build | Region | Step | Status | Duration | Error |")
	fmt.Println("|---|----------|-------|--------|------|--------|----------|-------|")
	for i, r := range rows {
		status := formatEV2Status(r.status)
		shortErr := r.errMsg
		if len(shortErr) > 40 {
			shortErr = shortErr[:40] + "..."
		}
		fmt.Printf("| %d | %s | %d | %s | %s | %s | %s | %s |\n",
			i+1, r.pipeline, r.buildID, r.region, r.stepName, status, r.duration, shortErr)
	}
	return nil
}

func printBuildsTable(builds []ado.Build) {
	fmt.Println("| # | Pipeline | Build | Status | Started | Duration | Link |")
	fmt.Println("|---|----------|-------|--------|---------|----------|------|")

	for i, b := range builds {
		status := formatStatus(b.Status, b.Result)
		started := formatTimeAgo(b.StartTime)
		duration := formatDuration(b.StartTime, b.FinishTime)
		link := b.Links.Web.Href
		if link == "" {
			link = fmt.Sprintf("https://dev.azure.com/msazure/AzureRedHatOpenShift/_build/results?buildId=%d", b.ID)
		}

		fmt.Printf("| %d | %s | %d | %s | %s | %s | [ADO](%s) |\n",
			i+1, b.Definition.Name, b.ID, status, started, duration, link)
	}
}

func formatStatus(status, result string) string {
	switch strings.ToLower(status) {
	case "inprogress":
		return "🟡 In Progress"
	case "completed":
		switch strings.ToLower(result) {
		case "succeeded":
			return "✅ Succeeded"
		case "failed":
			return "❌ Failed"
		case "canceled":
			return "⚪ Canceled"
		case "partiallysucceeded":
			return "🟠 Partial"
		default:
			return "✅ Completed"
		}
	case "cancelling":
		return "⚪ Cancelling"
	case "notstarted":
		return "⏳ Not Started"
	default:
		return status
	}
}

func formatEV2Status(status string) string {
	switch strings.ToLower(status) {
	case "running":
		return "🟡 Running"
	case "succeeded":
		return "✅ Succeeded"
	case "failed":
		return "❌ Failed"
	case "canceling", "canceled":
		return "⚪ Canceled"
	default:
		return status
	}
}

func formatTimeAgo(t time.Time) string {
	d := time.Since(t)
	if d < time.Minute {
		return "just now"
	}
	if d < time.Hour {
		return fmt.Sprintf("%dm ago", int(d.Minutes()))
	}
	hours := int(d.Hours())
	mins := int(d.Minutes()) % 60
	if hours < 24 {
		return fmt.Sprintf("%dh %dm ago", hours, mins)
	}
	return fmt.Sprintf("%dd %dh ago", hours/24, hours%24)
}

func formatDuration(start time.Time, finish *time.Time) string {
	end := time.Now()
	if finish != nil {
		end = *finish
	}
	d := end.Sub(start)
	if d < time.Minute {
		return "<1m"
	}
	hours := int(d.Hours())
	mins := int(d.Minutes()) % 60
	if hours == 0 {
		return fmt.Sprintf("%dm", mins)
	}
	return fmt.Sprintf("%dh %dm", hours, mins)
}
