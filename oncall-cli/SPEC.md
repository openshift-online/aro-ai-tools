# ARO HCP Oncall — Copilot Skill Spec

## Goal

Three CLI commands that give oncall engineers quick visibility into running HCP SDP pipelines, EV2 rollouts, and E2E gating step status, presented as actionable tables directly in the terminal.

---

## Skills Overview

| Skill Name | Purpose |
|------------|---------|
| `oncall builds` | List ADO pipeline builds (running, or last N hours) |
| `oncall ev2` | List EV2 rollouts associated with HCP builds (running, or last N hours) |
| `oncall e2e` | List E2E regional gating step status from EV2 rollouts |

---

## Skill 1: `aro-hcp-builds`

### Description

List currently running (or recent) HCP SDP pipeline builds from Azure DevOps.

### User Interaction

```
> @copilot show me running HCP builds
> @copilot list HCP builds from the last 6 hours
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `hours` | int | 24 | Show builds from last N hours regardless of status; use 0 for running only |

### Output (Markdown Table)

```
| # | Pipeline | Build | Status | Started | Duration | Link |
|---|----------|-------|--------|---------|----------|------|
| 1 | hcp-incremental | 98765 | 🟡 In Progress | 2h 15m ago | 2h 15m | [ADO](https://...) |
| 2 | hcp-incremental | 98701 | ✅ Completed | 5h ago | 1h 42m | [ADO](https://...) |
```

### Implementation

1. **List definitions** in ADO folder `\OneBranch\sdp-pipelines\hcp\Incremental`
2. **Query builds** with `statusFilter=inProgress` (or `minTime` if `hours` specified)
3. **Format** results as markdown table

### ADO API Calls

```
GET https://dev.azure.com/msazure/AzureRedHatOpenShift/_apis/build/definitions?path=\OneBranch\sdp-pipelines\hcp\Incremental&api-version=7.1

GET https://dev.azure.com/msazure/AzureRedHatOpenShift/_apis/build/builds?definitions={ids}&statusFilter=inProgress&api-version=7.1
```

For historical (last N hours):
```
GET https://dev.azure.com/msazure/AzureRedHatOpenShift/_apis/build/builds?definitions={ids}&minTime={iso8601}&api-version=7.1
```

---

## Skill 2: `aro-hcp-ev2`

### Description

List EV2 rollouts associated with HCP pipeline builds. Extracts EV2 URLs from build logs.

### User Interaction

```
> @copilot show me running EV2 rollouts
> @copilot list EV2 rollouts from the last 4 hours
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `hours` | int | 24 | Show rollouts from last N hours; use 0 for running only |

### Output (Markdown Table)

```
| # | Pipeline | Build | Rollout ID | Service Model | Rollout Link |
|---|----------|-------|-----------|---------------|--------------|
| 1 | hcp-incremental | 98765 | b8e9ef87 | Microsoft.Azure.ARO.HCP.GlobalBuildout | [EV2](https://ra.ev2portal...) |
| 2 | hcp-incremental | 98701 | a1c2d3e4 | Microsoft.Azure.ARO.HCP.GlobalBuildout | [EV2](https://ra.ev2portal...) |
```

### Implementation

1. Use `aro-hcp-builds` logic to get relevant builds
2. For each build, **fetch timeline** → find `Ev2RA Managed SDP Rollout` step
3. **Fetch step log** → extract EV2 portal URLs via regex
4. **Format** results as markdown table

### EV2 URL Extraction

Regex for log parsing:
```
https://ra\.ev2portal\.azure\.net/#/rollouts/[^\s"]+
```

From the extracted URL, parse:
- `rolloutId` (UUID)
- `serviceModel` (e.g. `Microsoft.Azure.ARO.HCP.GlobalBuildout`)
- `executionId` (UUID)

---

## Skill 3: `oncall e2e`

### Description

List E2E regional gating step status from EV2 rollouts. Shows per-region step status for active rollouts.

### User Interaction

```
> oncall e2e
> oncall e2e --hours 6
> oncall e2e --hours 24 --path '\OneBranch\sdp-pipelines\hcp\Incremental'
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `hours` | int | 24 | Show builds from last N hours; use 0 for running only |
| `path` | string | `\OneBranch\sdp-pipelines\hcp\Incremental` | ADO folder path |
| `ev2-host` | string | `https://ev2.azure.net` | EV2 RolloutInfra host URL |

### Output (Markdown Table)

```
| # | Pipeline | Build | Region | Step | Status | Duration | Error |
|---|----------|-------|--------|------|--------|----------|-------|
| 1 | hcp-incremental | 98765 | uksouth | E2E.service.regionalGating-uksouth-1 | 🟡 Running | 15m | |
| 2 | hcp-incremental | 98765 | eastus | E2E.service.regionalGating-eastus-1 | ✅ Succeeded | 22m | |
| 3 | hcp-incremental | 98765 | westeurope | E2E.service.regionalGating-westeurope-1 | ❌ Failed | 8m | timeout... |
```

### Implementation

1. Use `oncall ev2` logic to get EV2 rollout IDs from build logs
2. For each rollout, call **EV2 API** `GET /api/rollouts/{rolloutId}?embed-detail=true`
3. Parse response `resourceGroups[].resources[].actions[]` for steps matching `E2E`/`regionalGating`
4. **Format** results as markdown table with status, duration, and errors

### EV2 API Call

```
GET {ev2Host}/api/rollouts/{rolloutId}?servicegroupname={serviceGroup}&api-version=2016-07-01&embed-detail=true
Authorization: Bearer <AAD token for EV2 host>
```

---

## Architecture

```
┌──────────────────────────────────────────────┐
│        oncall CLI (Go binary)                │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ oncall builds                          │  │
│  │  - Calls ADO REST API                  │  │
│  │  - Returns markdown table              │  │
│  └────────────────────────────────────────┘  │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ oncall ev2                             │  │
│  │  - Calls ADO REST API (timeline/logs)  │  │
│  │  - Parses EV2 URLs from logs           │  │
│  │  - Returns markdown table              │  │
│  └────────────────────────────────────────┘  │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ oncall e2e                             │  │
│  │  - Reuses ev2 logic for rollout IDs    │  │
│  │  - Calls EV2 API (embed-detail=true)   │  │
│  │  - Extracts E2E step status            │  │
│  │  - Returns markdown table              │  │
│  └────────────────────────────────────────┘  │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ Shared: Auth + ADO Client + EV2 Client │  │
│  │  - ADO: PAT or az CLI token            │  │
│  │  - EV2: az CLI token                   │  │
│  │  - Definitions cache                   │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
         │                        │
         ▼                        ▼
   Azure DevOps API          EV2 REST API
```

---

## Authentication

### Azure DevOps

**Option A — PAT (MVP)**
- User provides a PAT with `Build (Read)` scope
- Stored as environment variable: `ADO_PAT`
- Used as Basic auth: `Authorization: Basic base64(:PAT)`

**Option B — Azure CLI credential (preferred for corp)**
- `az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798`
- Or `DefaultAzureCredential` from azidentity SDK

---

## Skill Plugin Format

**TBD:** Research required on Copilot CLI skill plugin protocol:
- How skills are registered (manifest/config file?)
- Communication protocol (stdio JSON? HTTP?)
- How parameters are passed and output returned
- Whether skills are Go binaries, scripts, or something else

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Skill runtime | Go binary |
| ADO client | `net/http` + Azure DevOps REST API v7.1 |
| AAD auth | `github.com/Azure/azure-sdk-for-go/sdk/azidentity` |
| Output | Markdown tables (rendered by Copilot CLI) |

---

## ADO API Reference

| Endpoint | Purpose |
|----------|---------|
| `GET /build/definitions?path=...` | List pipeline definitions in folder |
| `GET /build/builds?definitions=...&statusFilter=...` | List builds by status |
| `GET /build/builds?definitions=...&minTime=...` | List builds since time |
| `GET /build/builds/{buildId}/timeline` | Get build steps |
| `GET /build/builds/{buildId}/logs/{logId}` | Get step log content |

Base: `https://dev.azure.com/msazure/AzureRedHatOpenShift/_apis`  
API version: `7.1`

---

## EV2 API Reference (for future use)

**Docs:** https://eng.ms/docs/products/ev2/references/api/intro  
**Auth:** Bearer token for RolloutInfra AAD resource ID  
**Key endpoints:**

| Version | Operation | Description |
|---------|-----------|-------------|
| 2016-07-01 | `GET /rollouts/{rolloutId}` | Get rollout details |
| 2016-07-01 | `GET /rollouts` | List rollouts |

---

## Open Questions

- [ ] **Copilot skill plugin format:** How to register and package a custom skill
- [ ] **Discover RolloutInfra host URL + AAD resource ID** (for future EV2 API enrichment)
- [ ] **Enumerate pipeline definition IDs:** Confirm which definitions live under the HCP folder

---

## MVP Scope

1. **`aro-hcp-builds`** — lists running/recent builds as markdown table
2. **`aro-hcp-ev2`** — extracts EV2 URLs from build logs, presents as markdown table
3. **Auth via `ADO_PAT` env var**

### Stretch Goals

- Live EV2 rollout status via EV2 API (`GET /rollouts/{rolloutId}`)
- E2E step deep-links per region
- Filtering by pipeline name or region
