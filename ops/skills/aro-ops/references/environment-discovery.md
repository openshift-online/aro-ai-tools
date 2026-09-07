# Environment discovery

Use these instructions when the user asks for available environments or
endpoints, or another operational workflow requires configuration that is not
already available in the current session.

Identify the AI agent client running the skill, such as `claude-code`, `cursor`,
`copilot`, or `codex`. If it cannot be determined, use `unknown`.

Always report the script output to the user. Keep the returned configuration
available during the current session, but do not persist it beyond the session.

## ARO HCP

Detect the operating system and run the appropriate script, passing the client
name:
- On macOS, run `scripts/hcp-get-env-config.sh "<client>"` using `zsh`.
- On Linux or WSL2, run `scripts/hcp-get-env-config.sh "<client>"` using `bash`.
- On Windows outside WSL, run `scripts/hcp-get-env-config.ps1 -Client "<client>"` using `pwsh`.

If the script reports that the plugin is out of date, tell the user how to update
it:

- Copilot: `/plugin update ops@aro-ai-tools`
- Claude: `/plugin marketplace update aro-ai-tools`
- Codex: `codex plugin marketplace upgrade aro-ai-tools`

The returned Kusto and Grafana endpoints can be used with `aro-kusto` and
`aro-grafana` respectively.

## ARO Classic

Detect the operating system and run the appropriate script, passing the client
name:

- On macOS, run `scripts/classic-get-env-config.sh "<client>"` using `zsh`.
- On Linux or WSL2, run `scripts/classic-get-env-config.sh "<client>"` using `bash`.
- On Windows outside WSL, run `scripts/classic-get-env-config.ps1 -Client "<client>"` using `pwsh`.

If the script reports that the plugin is out of date, use the update instructions
in the ARO HCP section.

For a regional resource, select the Classic entry whose `locations` includes the
resource's Azure region. Ask the user to choose only when the correct entry cannot
be determined from context.

Use these returned fields with `aro-kusto`:

- `kusto`: Kusto cluster endpoint for the Classic sector.
- `defaultDatabase`: recommended starting database when present.

ARO Classic has no Grafana endpoint.
