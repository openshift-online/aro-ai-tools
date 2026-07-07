package auth

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// adoResource is Microsoft's well-known first-party Azure AD application ID
// for Azure DevOps. It's the same fixed ID for every org/tenant (not specific
// to this project) and is passed as --resource to `az account get-access-token`
// so the resulting token's audience is Azure DevOps, which the ADO REST API
// accepts as Bearer auth.
const adoResource = "499b84ac-1321-427f-aa17-267ca6975798"

// Token returns an authorization header value for Azure DevOps.
// It tries ADO_PAT env var first, then falls back to `az` CLI.
func Token() (string, error) {
	if pat := os.Getenv("ADO_PAT"); pat != "" {
		encoded := base64.StdEncoding.EncodeToString([]byte(":" + pat))
		return "Basic " + encoded, nil
	}
	return azCLIToken(adoResource)
}

// EV2Token returns an authorization header value for the EV2 API.
// Uses `az` CLI to get a token for the EV2 host resource.
func EV2Token(host string) (string, error) {
	if host == "" {
		host = "https://ev2.azure.net"
	}
	// The resource for az CLI token is the host URL itself
	return azCLIToken(host)
}

func azCLIToken(resource string) (string, error) {
	cmd := exec.Command("az", "account", "get-access-token",
		"--resource", resource,
		"--query", "accessToken",
		"--output", "json",
	)
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get az CLI token for resource %s (is az logged in?): %w", resource, err)
	}
	var token string
	if err := json.Unmarshal(out, &token); err != nil {
		return "", fmt.Errorf("failed to parse az CLI token: %w (output: %s)", err, strings.TrimSpace(string(out)))
	}
	return "Bearer " + token, nil
}
