package ado

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
)

const (
	baseURL     = "https://dev.azure.com/msazure/AzureRedHatOpenShift/_apis"
	apiVersion  = "7.1"
	defaultPath = "\\OneBranch\\sdp-pipelines\\hcp\\Incremental"
)

// Client talks to the Azure DevOps REST API.
type Client struct {
	httpClient *http.Client
	authHeader string
}

// NewClient creates an ADO client with the given auth header.
func NewClient(authHeader string) *Client {
	return &Client{
		httpClient: &http.Client{Timeout: 30 * time.Second},
		authHeader: authHeader,
	}
}

// Definition represents a build pipeline definition.
type Definition struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
	Path string `json:"path"`
}

// Build represents a pipeline build/run.
type Build struct {
	ID          int        `json:"id"`
	BuildNumber string     `json:"buildNumber"`
	Status      string     `json:"status"`
	Result      string     `json:"result"`
	StartTime   time.Time  `json:"startTime"`
	FinishTime  *time.Time `json:"finishTime"`
	Definition  Definition `json:"definition"`
	Links       struct {
		Web struct {
			Href string `json:"href"`
		} `json:"web"`
	} `json:"_links"`
}

// TimelineRecord is a step in a build timeline.
type TimelineRecord struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Type string `json:"type"`
	Log  *struct {
		ID  int    `json:"id"`
		URL string `json:"url"`
	} `json:"log"`
}

// ListDefinitions returns pipeline definitions under the given path (recursive).
func (c *Client) ListDefinitions(path string) ([]Definition, error) {
	if path == "" {
		path = defaultPath
	}
	params := url.Values{
		"path":                 {path},
		"includeAllProperties": {"false"},
		"api-version":          {apiVersion},
	}
	var result struct {
		Value []Definition `json:"value"`
	}
	if err := c.get("/build/definitions", params, &result); err != nil {
		return nil, err
	}
	return result.Value, nil
}

// ListBuilds returns builds for the given definition IDs.
// If hours > 0, returns builds from the last N hours. Otherwise only inProgress.
func (c *Client) ListBuilds(definitionIDs []int, hours int) ([]Build, error) {
	if len(definitionIDs) == 0 {
		return nil, nil
	}

	ids := make([]string, len(definitionIDs))
	for i, id := range definitionIDs {
		ids[i] = fmt.Sprintf("%d", id)
	}

	params := url.Values{
		"definitions": {strings.Join(ids, ",")},
		"api-version": {apiVersion},
	}

	if hours > 0 {
		minTime := time.Now().UTC().Add(-time.Duration(hours) * time.Hour)
		params.Set("minTime", minTime.Format(time.RFC3339))
	} else {
		params.Set("statusFilter", "inProgress")
	}

	var result struct {
		Value []Build `json:"value"`
	}
	if err := c.get("/build/builds", params, &result); err != nil {
		return nil, err
	}
	return result.Value, nil
}

// GetTimeline returns all timeline records for a build.
func (c *Client) GetTimeline(buildID int) ([]TimelineRecord, error) {
	path := fmt.Sprintf("/build/builds/%d/timeline", buildID)
	params := url.Values{"api-version": {apiVersion}}

	var result struct {
		Records []TimelineRecord `json:"records"`
	}
	if err := c.get(path, params, &result); err != nil {
		return nil, err
	}
	return result.Records, nil
}

// GetLog returns the raw log text for a given log ID in a build.
func (c *Client) GetLog(buildID, logID int) (string, error) {
	path := fmt.Sprintf("/build/builds/%d/logs/%d", buildID, logID)
	params := url.Values{"api-version": {apiVersion}}

	reqURL := baseURL + path + "?" + params.Encode()
	req, err := http.NewRequest("GET", reqURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", c.authHeader)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("GET %s returned %d: %s", reqURL, resp.StatusCode, string(body))
	}

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

var ev2URLPattern = regexp.MustCompile(`https://ra\.ev2portal\.azure\.net/#/rollouts/[^\s"]+`)

// EV2Rollout holds a parsed EV2 rollout URL and its components.
type EV2Rollout struct {
	URL          string
	RolloutID    string
	ServiceModel string
}

// FindEV2URLs searches build logs for EV2 portal URLs.
// It looks for the "Ev2RA Managed SDP Rollout" step in the timeline.
func (c *Client) FindEV2URLs(buildID int) ([]EV2Rollout, error) {
	records, err := c.GetTimeline(buildID)
	if err != nil {
		return nil, fmt.Errorf("get timeline: %w", err)
	}

	var rollouts []EV2Rollout
	for _, rec := range records {
		if !strings.Contains(rec.Name, "Ev2RA") && !strings.Contains(rec.Name, "SDP Rollout") {
			continue
		}
		if rec.Log == nil {
			continue
		}

		logText, err := c.GetLog(buildID, rec.Log.ID)
		if err != nil {
			continue // best effort
		}

		matches := ev2URLPattern.FindAllString(logText, -1)
		for _, m := range matches {
			rollout := parseEV2URL(m)
			rollouts = append(rollouts, rollout)
		}
	}

	return dedupRollouts(rollouts), nil
}

func parseEV2URL(rawURL string) EV2Rollout {
	r := EV2Rollout{URL: rawURL}
	// URL format: .../rollouts/Prod/{rolloutId}/{serviceModel}/{executionId}...
	parts := strings.Split(rawURL, "/")
	for i, p := range parts {
		if p == "rollouts" && i+3 < len(parts) {
			r.RolloutID = parts[i+2] // skip "Prod"
			r.ServiceModel = parts[i+3]
			break
		}
	}
	return r
}

func dedupRollouts(rollouts []EV2Rollout) []EV2Rollout {
	seen := make(map[string]bool)
	var result []EV2Rollout
	for _, r := range rollouts {
		if !seen[r.RolloutID] {
			seen[r.RolloutID] = true
			result = append(result, r)
		}
	}
	return result
}

func (c *Client) get(path string, params url.Values, target interface{}) error {
	reqURL := baseURL + path + "?" + params.Encode()
	req, err := http.NewRequest("GET", reqURL, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", c.authHeader)
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("GET %s returned %d: %s", reqURL, resp.StatusCode, string(body))
	}

	return json.NewDecoder(resp.Body).Decode(target)
}
