package ado

import (
	"testing"
)

func TestParseEV2URL(t *testing.T) {
	tests := []struct {
		name        string
		url         string
		wantRollout string
		wantService string
	}{
		{
			name:        "full EV2 URL",
			url:         "https://ra.ev2portal.azure.net/#/rollouts/Prod/b8e9ef87-cd63-4085-ab14-1c637806568c/Microsoft.Azure.ARO.HCP.GlobalBuildout/17f00427-21cc-4a6f-b9f6-46895f211631",
			wantRollout: "b8e9ef87-cd63-4085-ab14-1c637806568c",
			wantService: "Microsoft.Azure.ARO.HCP.GlobalBuildout",
		},
		{
			name:        "EV2 URL with E2E step",
			url:         "https://ra.ev2portal.azure.net/#/rollouts/Prod/b8e9ef87-cd63-4085-ab14-1c637806568c/Microsoft.Azure.ARO.HCP.GlobalBuildout/17f00427-21cc-4a6f-b9f6-46895f211631/list/Medium.uksouth/E2E.service.regionalGating-uksouth-1/shell%2FregionalGating/0/uksouth%3A3a6c4091-c11f-48c0-b650-2c6a41e77acb",
			wantRollout: "b8e9ef87-cd63-4085-ab14-1c637806568c",
			wantService: "Microsoft.Azure.ARO.HCP.GlobalBuildout",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseEV2URL(tt.url)
			if got.RolloutID != tt.wantRollout {
				t.Errorf("RolloutID = %q, want %q", got.RolloutID, tt.wantRollout)
			}
			if got.ServiceModel != tt.wantService {
				t.Errorf("ServiceModel = %q, want %q", got.ServiceModel, tt.wantService)
			}
			if got.URL != tt.url {
				t.Errorf("URL = %q, want %q", got.URL, tt.url)
			}
		})
	}
}

func TestDedupRollouts(t *testing.T) {
	input := []EV2Rollout{
		{URL: "https://a", RolloutID: "id1", ServiceModel: "svc1"},
		{URL: "https://b", RolloutID: "id1", ServiceModel: "svc1"},
		{URL: "https://c", RolloutID: "id2", ServiceModel: "svc2"},
	}
	got := dedupRollouts(input)
	if len(got) != 2 {
		t.Fatalf("expected 2 rollouts, got %d", len(got))
	}
	if got[0].RolloutID != "id1" {
		t.Errorf("first rollout ID = %q, want %q", got[0].RolloutID, "id1")
	}
	if got[1].RolloutID != "id2" {
		t.Errorf("second rollout ID = %q, want %q", got[1].RolloutID, "id2")
	}
}

func TestEV2URLPattern(t *testing.T) {
	log := `2026-07-01T10:00:00 Starting EV2 rollout...
Rollout URL: https://ra.ev2portal.azure.net/#/rollouts/Prod/b8e9ef87-cd63-4085-ab14-1c637806568c/Microsoft.Azure.ARO.HCP.GlobalBuildout/17f00427-21cc-4a6f-b9f6-46895f211631
Waiting for completion...`

	matches := ev2URLPattern.FindAllString(log, -1)
	if len(matches) != 1 {
		t.Fatalf("expected 1 match, got %d", len(matches))
	}
	expected := "https://ra.ev2portal.azure.net/#/rollouts/Prod/b8e9ef87-cd63-4085-ab14-1c637806568c/Microsoft.Azure.ARO.HCP.GlobalBuildout/17f00427-21cc-4a6f-b9f6-46895f211631"
	if matches[0] != expected {
		t.Errorf("match = %q, want %q", matches[0], expected)
	}
}
