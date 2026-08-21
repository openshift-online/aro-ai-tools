package ev2

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

const (
	defaultHost = "https://ev2.azure.net"
	apiVersion  = "2016-07-01"
)

// Client talks to the EV2 REST API.
type Client struct {
	httpClient *http.Client
	host       string
	authHeader string
}

// NewClient creates an EV2 client.
// host is the RolloutInfra host (e.g. "https://ev2.azure.net").
func NewClient(host, authHeader string) *Client {
	if host == "" {
		host = defaultHost
	}
	return &Client{
		httpClient: &http.Client{Timeout: 30 * time.Second},
		host:       host,
		authHeader: authHeader,
	}
}

// Rollout is the top-level rollout object from the EV2 API.
type Rollout struct {
	RolloutID            string               `json:"rolloutId"`
	RolloutName          string               `json:"rolloutName"`
	Status               string               `json:"status"`
	TotalRetryAttempts   int                  `json:"totalRetryAttempts"`
	RolloutDetails       RolloutDetails       `json:"rolloutDetails"`
	RolloutOperationInfo RolloutOperationInfo `json:"rolloutOperationInfo"`
	ResourceGroups       []ResourceGroup      `json:"resourceGroups"`
}

type RolloutDetails struct {
	TeamName     string `json:"teamName"`
	ServiceGroup string `json:"serviceGroup"`
	Environment  string `json:"environment"`
	BuildVersion string `json:"buildVersion"`
}

type RolloutOperationInfo struct {
	RetryAttempt int        `json:"retryAttempt"`
	StartTime    time.Time  `json:"startTime"`
	EndTime      *time.Time `json:"endTime"`
	ErrorInfo    ErrorInfo  `json:"errorInfo"`
}

type ErrorInfo struct {
	ErrorCode   string `json:"errorCode"`
	ErrorReason string `json:"errorReason"`
}

type ResourceGroup struct {
	Name           string     `json:"name"`
	Location       string     `json:"location"`
	SubscriptionID string     `json:"subscriptionId"`
	Resources      []Resource `json:"resources"`
}

type Resource struct {
	Name    string   `json:"name"`
	Actions []Action `json:"actions"`
}

type Action struct {
	Name                string              `json:"name"`
	StepName            string              `json:"stepName"`
	Status              string              `json:"status"`
	ActionOperationInfo ActionOperationInfo `json:"actionOperationInfo"`
	Messages            []ActionMessage     `json:"messages"`
}

type ActionOperationInfo struct {
	CorrelationID string     `json:"correlationId"`
	StartTime     time.Time  `json:"startTime"`
	EndTime       *time.Time `json:"endTime"`
	ErrorInfo     ErrorInfo  `json:"errorInfo"`
}

type ActionMessage struct {
	Timestamp time.Time `json:"timestamp"`
	Message   string    `json:"message"`
}

// GetRollout fetches a rollout by ID with full detail (embed-detail=true).
func (c *Client) GetRollout(rolloutID, serviceGroupName string) (*Rollout, error) {
	params := url.Values{
		"servicegroupname": {serviceGroupName},
		"api-version":      {apiVersion},
		"embed-detail":     {"true"},
	}

	reqURL := fmt.Sprintf("%s/api/rollouts/%s?%s", c.host, rolloutID, params.Encode())
	req, err := http.NewRequest("GET", reqURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", c.authHeader)
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("GET %s returned %d: %s", reqURL, resp.StatusCode, string(body))
	}

	var rollout Rollout
	if err := json.NewDecoder(resp.Body).Decode(&rollout); err != nil {
		return nil, fmt.Errorf("decode rollout: %w", err)
	}
	return &rollout, nil
}

// E2EStep represents an E2E gating step extracted from a rollout.
type E2EStep struct {
	StepName  string
	Region    string
	Status    string
	StartTime time.Time
	EndTime   *time.Time
	Error     string
}

// GetE2ESteps extracts E2E regional gating steps from a rollout.
func GetE2ESteps(rollout *Rollout) []E2EStep {
	var steps []E2EStep
	for _, rg := range rollout.ResourceGroups {
		for _, res := range rg.Resources {
			for _, action := range res.Actions {
				if isE2EStep(action.StepName) {
					step := E2EStep{
						StepName:  action.StepName,
						Region:    rg.Location,
						Status:    action.Status,
						StartTime: action.ActionOperationInfo.StartTime,
						EndTime:   action.ActionOperationInfo.EndTime,
					}
					if action.ActionOperationInfo.ErrorInfo.ErrorReason != "" {
						step.Error = action.ActionOperationInfo.ErrorInfo.ErrorReason
					}
					steps = append(steps, step)
				}
			}
		}
	}
	return steps
}

func isE2EStep(stepName string) bool {
	// Match steps like "E2E.service.regionalGating-uksouth-1"
	return len(stepName) > 0 &&
		(contains(stepName, "E2E") || contains(stepName, "e2e") ||
			contains(stepName, "regionalGating"))
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && searchString(s, substr)
}

func searchString(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
