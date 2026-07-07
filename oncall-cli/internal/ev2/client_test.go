package ev2

import (
	"testing"
)

func TestGetE2ESteps(t *testing.T) {
	rollout := &Rollout{
		RolloutID:   "test-rollout-id",
		RolloutName: "test-rollout",
		Status:      "Running",
		ResourceGroups: []ResourceGroup{
			{
				Name:     "rg-uksouth",
				Location: "uksouth",
				Resources: []Resource{
					{
						Name: "myResource",
						Actions: []Action{
							{
								Name:     "Deploy",
								StepName: "E2E.service.regionalGating-uksouth-1",
								Status:   "Running",
							},
							{
								Name:     "Deploy",
								StepName: "Rollout_Stamp1",
								Status:   "Succeeded",
							},
						},
					},
				},
			},
			{
				Name:     "rg-eastus",
				Location: "eastus",
				Resources: []Resource{
					{
						Name: "myResource",
						Actions: []Action{
							{
								Name:     "Deploy",
								StepName: "E2E.service.regionalGating-eastus-1",
								Status:   "Succeeded",
							},
						},
					},
				},
			},
		},
	}

	steps := GetE2ESteps(rollout)
	if len(steps) != 2 {
		t.Fatalf("expected 2 E2E steps, got %d", len(steps))
	}

	if steps[0].Region != "uksouth" {
		t.Errorf("step[0].Region = %q, want %q", steps[0].Region, "uksouth")
	}
	if steps[0].Status != "Running" {
		t.Errorf("step[0].Status = %q, want %q", steps[0].Status, "Running")
	}
	if steps[0].StepName != "E2E.service.regionalGating-uksouth-1" {
		t.Errorf("step[0].StepName = %q, want %q", steps[0].StepName, "E2E.service.regionalGating-uksouth-1")
	}

	if steps[1].Region != "eastus" {
		t.Errorf("step[1].Region = %q, want %q", steps[1].Region, "eastus")
	}
	if steps[1].Status != "Succeeded" {
		t.Errorf("step[1].Status = %q, want %q", steps[1].Status, "Succeeded")
	}
}

func TestIsE2EStep(t *testing.T) {
	tests := []struct {
		name string
		want bool
	}{
		{"E2E.service.regionalGating-uksouth-1", true},
		{"E2E.service.regionalGating-eastus-1", true},
		{"Rollout_Stamp1", false},
		{"Deploy", false},
		{"e2e-test-step", true},
		{"regionalGating-westus-1", true},
		{"", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isE2EStep(tt.name)
			if got != tt.want {
				t.Errorf("isE2EStep(%q) = %v, want %v", tt.name, got, tt.want)
			}
		})
	}
}
