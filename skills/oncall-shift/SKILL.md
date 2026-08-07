---
name: oncall-shift
description: Manage an oncall shift end-to-end — accept handover, prioritize tasks, track work in a local shift log, and generate structured handover notes for the next shift. Use whenever a user starts an oncall shift, receives handover notes, wants to update shift status, or needs to create handover notes.
---

## Personal Overrides

If a `SKILL.local.md` file exists in this skill's directory, read it before
proceeding. It contains personal instructions that augment (never contradict)
the directions below. These files are gitignored and persist across upstream
skill updates.

# Oncall Shift Management

## What I Do

Manage the full lifecycle of an oncall shift:

1. **Accept handover** — parse incoming handover notes (Slack pastes, text),
   extract action items, and create a prioritized plan.
2. **Create tracking doc** — create a local shift log file that tracks
   all work, updates, and handover notes.
3. **Prioritize tasks** — order by: rollouts first, then time-sensitive /
   important items, then alerts, then routine monitoring.
4. **Track updates** — append to the shift log as work progresses
   throughout the shift, preserving chat excerpts with attribution.
5. **Generate handover notes** — produce structured handover notes for the
   next shift in a consistent format.

## Coverage Model

The team follows a **24x5 Follow-the-Sun (FTS)** model.

- **Coverage window**: Sunday 21:00 UTC to Friday 21:00 UTC
- **Weekend policy**: No weekend SLAs. Pager rotations and active monitoring
  pause on Saturdays and Sundays.
- **Shift handover**: Each region (APAC → EMEA → NASA) hands over IC
  responsibilities at the end of their local business day.

### Shift Schedule

| GEO | Start (UTC) | End (UTC) |
|-----|-------------|----------|
| APAC East | 22:00 | 04:00 |
| APAC West | 04:00 | 10:00 |
| EMEA | 10:00 | 16:00 |
| NASA | 16:00 | 22:00 |

Scheduling is managed quarterly via IcM. Check your schedule at
[IcM / MyOnCall](https://portal.microsofticm.com/).

## Roles

Each shift has a **Primary** and **Secondary** responder.

### Primary Responder (Releases & Alerts)

The Primary is the Interrupt Collector (IC). Responsibilities:

1. **Release management** — execute all releases across INT, Stage, and Prod
   per the continuous, serialized rollout model.
2. **Quality Service Review (QSR)** — attend the QSR meeting to provide
   release updates.
3. **Proactive revert policy** — if a component breaks a rollout or fails a
   gate, perform an immediate revert. Before reverting, verify the failure is
   not infrastructure or pipeline related. Once reverted, notify the
   responsible team to provide a fix for re-submission in a later batch.
4. **IcM alert management** — see IcM Alert Triage section below.
5. **Dev merge queue health** — see Dev Merge Queue Monitoring section below.

### Secondary Responder (Communication & Triage)

*Not currently enforced — team-based best effort.*

- **Slack monitoring**: First point of contact for all IC pings in designated
  Slack channels.
- **Tag response**: Respond to all team @-mentions and tags related to service
  lifecycle issues.

## When to Use Me

- User starts an oncall shift and pastes or describes handover notes
- User wants to create a prioritized oncall plan
- User wants to log an update to their shift log
- User wants to generate handover notes for the next shift
- User mentions "oncall", "handover", "shift tracking", or "on-call"

## Core Principles

1. **If it's not in the handover notes, it didn't happen.** Every action,
   decision, and status change must be recorded — either in the shift
   shift log or in the handover notes. Verbal-only updates are lost.

2. **Every JIRA ticket created during oncall must have the `oncall` label.**
   This is non-negotiable. It enables filtering oncall interrupt work from
   planned sprint work. Note: the shift log is NOT a JIRA ticket.
   JIRA tickets are reserved for actual work products (incidents, bugs,
   tasks). The shift log is a local markdown file.

3. **Chat excerpts must include attribution.** When recording Slack messages
   or conversations, always capture: **who** said it, **when** (timestamp),
   and **where** (Slack link if available). Ask for the Slack link if not
   provided.

4. **Prioritization order is fixed:**
   1. Situational awareness (quality call notes, handover ticket dashboard)
   2. Rollouts (active, failed, blocked)
   3. Time-sensitive / important items (CCOA exceptions, approvals, deadlines)
   4. Dev merge queue health (unblock Tide batches)
   5. Check alerts (proactive problem detection)
   6. Routine monitoring (IcM, Prow, Azure Pipelines, dashboards)

5. **IcM alerts have a hard SLA.** All Sev 2 and below critical alerts must
   be acknowledged within 30 minutes. This is not optional.

## Parameters

Extract from user context. Only ask if required and not inferrable.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `handover_notes` | yes (for start) | Raw handover text — Slack paste, typed notes, etc. |
| `shift_name` | no | Timezone shift name (EMEA, NASA, APAC). Infer from context. |
| `engineer` | no | Oncall engineer's name. Infer from git config or context. |
| `tracking_doc_path` | no | Existing shift log file path if resuming a shift. Created automatically if not provided. |

## Directions

### Phase 1 — Accept Handover & Create Plan

When the user starts a shift (pastes handover notes or describes context):

#### Step 1: Parse Handover Notes

Extract from the raw input:

- **Rollouts** — active, completed, failed, blocked. Include EV2 links.
- **Action items** — things explicitly assigned or requested.
- **Awareness items** — FYIs, no action needed but carry forward.
- **PRs to babysit** — PRs that need merging or monitoring.
- **Incidents** — IcM incidents, capacity issues, outages.
- **Chat excerpts** — preserve who said what and when. Flag any item
  where a Slack link is missing and ask for it.

For each chat excerpt, enforce this format:

```
- **<Person> [<time>]**: <message> ([Slack](<link>))
```

If the Slack link is not provided, record without it but flag:

```
- **<Person> [<time>]**: <message> *(Slack link not provided — ask sender)*
```

#### Step 2: Prioritize

The five categories below are standing responsibilities every shift. All
five must appear in every action plan regardless of what the handover notes
contain. Handover items, action items, PRs to babysit, and awareness items
are slotted into whichever category they belong to — they do not form a
separate list.

1. **🔴 Rollouts** — Active rollouts, failed rollouts needing cancellation,
   blocked rollouts. Slot handover rollout items here.
2. **🟠 Important / Time-Sensitive** — CCOA exceptions, approval chains,
   PRs with deadlines, pipeline recoveries. Slot handover action items, PRs
   to babysit, and time-sensitive requests here.
3. **🟡 Dev Merge Queue** — Check Tide batch health and unblock if needed
   (see Dev Merge Queue Monitoring section below). Always present even if
   handover does not mention it.
4. **🟡 Alerts** — Check monitoring alerts for proactive problem detection.
   Always present even if handover does not mention it.
5. **🟢 Routine Monitoring** — IcM portal sweep, oncall dashboard ticket
   triage, Prow status, quality call, handover ticket dashboard. Slot
   handover awareness items and incidents here. Always present even if
   handover does not mention it.

   Key links for routine monitoring:
   - [IcM Portal (active incidents)](https://portal.microsofticm.com/imp/v3/overview/main?q=ACTIVE&st=predefined_2)
   - [Prow Status (ARO-HCP jobs)](https://prow.ci.openshift.org/?repo=Azure%2FARO-HCP)
   - [Azure Pipelines Rollout Status](https://dev.azure.com/msazure/AzureRedHatOpenShift/_build?pipelineNameFilter=Entrypoint*HCP)
   - [Handover Ticket Dashboard (active JIRAs)](https://redhat.atlassian.net/jira/software/c/projects/AROSLSRE/boards/11820)
   - [Quality Call Notes](https://docs.google.com/document/d/1dX_CsGpS0hsU0lETbsRgIaLFrQIg-frH-7qzJN8d13A/edit?tab=t.0)

If the handover notes contain items that already match a standing category
(e.g. an IcM incident is routine monitoring, a PR deadline is
important/time-sensitive), place them in that category rather than creating
duplicates.

Present as a numbered action sequence (not just categories). Every category
must have at least one concrete action, even if it is the standing default:

```
### Suggested Sequence

1. Review latest Quality Call notes for situational awareness
2. Check handover ticket dashboard for active JIRAs requiring attention
3. <Most urgent rollout action or "No active rollouts — verify none pending">
4. <Next rollout action>
5. <Time-sensitive item or "No time-sensitive items">
6. Check Dev merge queue health (CI Health Dashboard)
7. Check monitoring alerts
8. <Verify pipeline/automation>
9. <Babysit PR>
10. Routine monitoring: IcM portal sweep, Prow status, Azure Pipelines rollout status
```

#### Step 3: Create Shift Log

Create a local markdown file to serve as the single source of truth for
the shift — all updates, decisions, and handover notes go here.

**File setup:**

- **Path**: `~/.local/share/oncall-shifts/<YYYY-MM-DD>-<shift_name>.md`
- **Create the directory** if it doesn't exist (`mkdir -p`).
- **Filename**: lowercase, dashes for spaces (e.g. `2026-08-03-nasa-east.md`).
- **Initial content**: Full prioritized plan with all sections:
  - Overview (shift context, handover source, engineer name)
  - Prioritized Task List (with all five categories)
  - Handover Chat Excerpts (with attribution)
  - References and links

Tell the user the file path immediately after creation.

### Phase 2 — Track Updates During Shift

When the user reports progress, new issues, or status changes:

#### Adding Updates

Append to the shift log file. Each update should include:

```markdown
## Shift Update — <HH:MM> UTC

### <Topic>

**Status**: <new status>
**Action taken**: <what was done>
**Result**: <outcome>

### Chat Excerpt (if applicable)

- **<Person> [<time>]**: <message> ([Slack](<link>))
```

#### Creating JIRA Tickets

If a new issue is discovered during the shift that warrants a JIRA ticket
(incidents, bugs, actionable tasks — NOT shift tracking):

1. Use the `create-jira-issue` skill to create it
2. **Always add the `oncall` label**
3. Add a note to the shift log referencing the new ticket

#### Tracking Chat Excerpts

When the user pastes a Slack conversation or references one:

1. Extract key statements with attribution
2. If no Slack link is provided, ask: *"Can you share the Slack link for
   this conversation so it's traceable in the handover?"*
3. Record in the shift log with the standard format

### Phase 3 — Generate Handover Notes

When the user asks for handover notes (end of shift):

#### Step 1: Gather State

Review the shift log file to compile current state of every
tracked item.

#### Step 2: Generate Handover

Generate **two versions** of the handover notes: a full markdown version
(appended to the shift log) and a Slack version (condensed, copy-paste
friendly). Always produce both.

##### Auto-linkification

Before rendering either version, scan all text for recognizable
references and convert them to clickable links. Apply these rules in
order:

| Pattern | URL Template |
|---------|-------------|
| `#NNNN` (bare PR number) | `https://github.com/Azure/ARO-HCP/pull/NNNN` |
| `AROSLSRE-NNNN` | `https://redhat-internal.atlassian.net/browse/AROSLSRE-NNNN` |
| `OCMBUGS-NNNN`, `OCMSVC-NNNN`, or any `PROJ-NNNN` Jira key | `https://redhat-internal.atlassian.net/browse/PROJ-NNNN` |
| IcM incident number (6–12 digits in IcM context) | `https://portal.microsofticm.com/imp/v5/incidents/details/NNNN/home` |
| ADO build ID (in rollout/pipeline context) | `https://dev.azure.com/msazure/AzureRedHatOpenShift/_build/results?buildId=NNNN` |
| ADO PR ID (in sdp-pipelines context) | `https://dev.azure.com/msazure/AzureRedHatOpenShift/_git/sdp-pipelines/pullrequest/NNNN` |

**Rules:**
- Never paste bare URLs. Always wrap in the appropriate link syntax.
- Use standard markdown links `[text](url)` in both the full markdown
  version and the Slack version. Slack renders markdown links as
  clickable text when pasted into a regular message.
- When context is ambiguous (e.g. a bare number could be a build ID or
  an incident), prefer the interpretation that matches the surrounding
  sentence. If still unclear, leave it as plain text.
- **Rollout items must include EV2 links.** For every rollout mentioned
  in the handover (INT, Stage, Prod), fetch the EV2 portal URL from the
  Release Dashboard (`https://releases.dev.aro.azure-test.net/releases`)
  and include it as an `[EV2](url)` link. The EV2 portal requires
  Microsoft corp auth but the links are still useful for the incoming IC
  to open from their SAW/VM.

##### Full Markdown Version

Append to the shift log file using this template:

```markdown
---

## ARO HCP SL Handover <FROM_SHIFT> to <TO_SHIFT> — <DATE>

### Highlights

<Things worth sharing with other shifts — context, learnings, process
changes, awareness items. Things that happened or were discovered during
the shift that the next shift should know about even if no action is needed.>

*Leave blank if nothing noteworthy.*

### High Priority Tasks

| Item | Status | Action Needed | Links |
|------|--------|---------------|-------|
| <item> | <status> | <what next shift should do> | JIRA / PR / Slack |

*Include JIRA tickets, PRs to merge, Slack threads to follow.*
*Leave blank if nothing pending.*

### High Priority IcM Incidents

| Incident | Severity | Status | Action Needed |
|----------|----------|--------|---------------|
| <title> | <sev> | <status> | <next step> |

*Leave blank if no active incidents.*

### Low Priority Stuff

<Things that are not critical but would be nice to review if the next
shift has spare time. Monitoring items, nice-to-have PRs, cleanup tasks.>

*Leave blank if nothing.*

### Tracking

- **Shift log**: <file path>
- **Oncall engineer**: <name>
- **Shift**: <shift_name> (<start_time> — <end_time>)
```

##### Slack Version

The Slack handover is posted as a *regular Slack message* (not through
the Slack Workflow). The agent produces a complete, self-contained
message with section headers and emojis that mirrors the Workflow
format. The user copies the entire message and pastes it into the
handover thread.

**Delivery method**: Write the Slack version to `/tmp/handover-slack.txt`
*and* display it on screen. Both outputs must be identical. The user
can copy from whichever is more convenient.

**Prerequisite**: The user must have "Format messages with markup"
enabled in Slack settings (Preferences > Advanced). Without this,
markdown links render as raw text.

**Critical formatting rules for the Slack version:**
- Bold: `*bold*` (single asterisk). NEVER use `**bold**`.
- Links: `[label](url)` (standard markdown). Use short labels (2-4
  words) for long URLs: `EV2`, `Stage rollout`, `Slack`, `Prow`.
  NEVER use `<url|label>` — the pipe character gets corrupted.
  NEVER paste bare URLs — always wrap in `[label](url)`.
- No `#` headings — Slack does not render them.
- No tables — use bullets only.
- Max 5 one-line bullets per section.
- Sub-bullets are allowed (indented with 2 spaces) for essential
  additional details on a parent bullet (e.g. cancellation reason,
  Slack thread link, next action). Keep sub-bullets to one line each.
- Each bullet starts with `• ` (bullet character, not dash).

**File template** (`/tmp/handover-slack.txt`):

```
ARO HCP SL Handover <FROM_SHIFT> to <TO_SHIFT>

:sparkles: *Highlights*
• <one-line highlight or "Nothing noteworthy">
  • <optional sub-bullet with supporting detail>

:thisisfine-3012: *High Priority tasks*
• <item — status — [short label](url)>
  • <optional sub-bullet: reason, Slack link, or next action>

:fire_engine: *High Priority IcM incidents*
• <incident or "No active IcM incidents">

:shrug: *Low Priority Stuff*
• <item or "Nothing pending">

:star: *Rate your shift*
<1-5 star emoji> <one-line summary>
```

**Example file content:**

```
ARO HCP SL Handover NASA East to NASA West

:sparkles: *Highlights*
• Multiple prod E2E regionalGating failures; stage kusto-lookup failure in uksouth

:thisisfine-3012: *High Priority tasks*
• *P0 fix needs prod rollout* — stage completed, prod not started, due tomorrow — [Stage rollout](https://ra.ev2portal.azure.net/#/rollouts/Prod/.../e165291f)
• Prod E2E regionalGating brazilsouth & eastus2 — retried, monitor — [EV2](https://ra.ev2portal.azure.net/#/rollouts/prod/.../5069861a)
• Prod E2E regionalGating uksouth — failed, retry or investigate — [EV2](https://ra.ev2portal.azure.net/#/rollouts/Prod/.../276aac58)
  • Failure is infra-related, not code — [Slack](https://redhat-internal.slack.com/archives/...)

:fire_engine: *High Priority IcM incidents*
• No active IcM incidents

:shrug: *Low Priority Stuff*
• Dev merge queue and IcM sweep not completed — meeting load + rollout activity

:star: *Rate your shift*
:star::star::star: Busy with rollouts and E2E failures but no incidents
```

**Content filtering — what goes in handover vs shift log only:**

The handover message is for the *incoming shift*. Only include items
they need to act on or be aware of to do their job. Everything else
stays in the shift log for internal documentation.

| Belongs in handover | Stays in shift log only |
|---------------------|------------------------|
| Active/blocked/failed rollouts needing action | Completed rollouts with no follow-up |
| IcM incidents requiring continued monitoring | Late handover from prior shift (process issue, not actionable) |
| Tickets the next shift must follow up on | Tickets with `oncall` label that are fully resolved or tracked on the oncall dashboard |
| CI health issues that are *abnormal* (week-over-week regression) | PR reviews done during shift (unless PR is rollout-blocking) |
| Region rollouts only if they are actively failing/blocking | Region rollouts with no activity (not actionable) |

**JIRA ticket filtering**: If a ticket has the `oncall` label, it
already appears on the oncall dashboard. Only include it in the
handover if the incoming shift needs to take *specific action* beyond
what the dashboard shows. Don't list tickets just because they were
touched during the shift.

**CI health context**: When reporting CI success rates, compare against
recent history (week-over-week) to distinguish normal baseline from
genuine regression. A 48% DEV success rate is not noteworthy if it has
been ~50% for weeks. Only flag it if there is a meaningful drop or a
new dominant failure pattern.

**Process issues stay internal**: Late handovers, missing documentation
from prior shifts, and similar process observations are valuable for
management analysis but do not help the incoming IC. Record them in the
shift log under "Lesson Learned" but omit from handover notes.

After writing the file, tell the user: *"Handover written to
`/tmp/handover-slack.txt` and displayed above — copy from whichever
is easier."*

#### Step 3: Post Handover

Append the **full markdown version** to the shift log file. Write
the **Slack version** to `/tmp/handover-slack.txt` and display it
on screen.

### Mandatory Handover Process

The out-going IC is **fully accountable** for ensuring a successful transfer.
The shift is not considered complete until all open issues are documented
and the handover has been proactively sought and confirmed.

#### 15 Minutes Before Shift End

1. **Prepare handover notes** — generate both the full markdown version
   (appended to the shift log) and the Slack version (written to
   `/tmp/handover-slack.txt` and displayed on screen) *before* reaching
   out to the incoming IC. This ensures the handover is ready to post
   immediately.
2. **Proactively contact the in-coming IC** via the automatically-created
   Slack handover thread. Tag the incoming IC and confirm they are alert
   and ready.
3. **Post the handover message** in the Slack thread using the handover
   notes prepared in step 1.
4. For every unresolved issue, provide:
   - **Shift log path** with status and next steps clearly documented
   - **PR links** (if applicable)
   - **Slack thread links** to relevant conversations
   - **Current status and next steps** — a clear statement of what the
     incoming IC needs to do

#### Handover Meeting (If Needed)

If the Slack message is insufficient for the complexity of open issues:

1. Initiate and lead the handover meeting using the scheduled meeting link.
2. Ensure the incoming IC attends.
3. Document key decisions and action items in the shift log and
   any relevant JIRA tickets.

#### Accountability

Failure to perform a complete and proactive handover does not guarantee a
follow-up from the incoming GEO zone. The out-going IC owns the handover.

## IcM Alert Triage

IcM is the primary tool for engaging SREs to resolve service interruptions.
Access the portal at https://portal.microsofticm.com/ (requires a properly
set up VM or SAW device).

### Acknowledgement SLA

**All Sev 2 and below critical alerts must be acknowledged within 30 minutes.**
This is the escalation policy window — missing it triggers automatic
escalation.

### Triage Process

For every IcM alert:

1. **Acknowledge** the alert within the 30-minute window.
2. **Initiate investigation** — review the alert details, check related
   dashboards and logs.
3. **Create a JIRA ticket** with the `oncall` label if the issue warrants
   tracked remediation work.
4. **Route the issue**:
   - **Component issue** → assign to the component owner's team.
   - **Infrastructure issue** → work on resolution directly.
5. **Document** — update the shift log and any JIRA tickets with
   the outcome. If the issue is not resolved by end of shift, include it
   in handover notes with full context.

### During Routine Monitoring

Even without active alerts, sweep the IcM portal once per shift to check
for:

- New alerts that may not have paged
- Alerts assigned to the team that need attention
- Stale alerts that should be resolved or re-assigned

## Dev Merge Queue Monitoring

Monitoring the Dev e2e-parallel merge queue is a core oncall responsibility.
The goal is to keep the merge queue moving by unblocking failing Tide
batches.

**CI Health Dashboard**: https://cihealth.tools.hcpsvc.osadev.cloud/

**E2E Failure Analysis (AI)**: https://releases.dev.aro.azure-test.net/tests/hcp

All monitoring should be done via the CI Health Dashboard:

### Day-to-day workflow

- **Report page** (`/report`, DEV env) — watch the E2E success card (after
  the last push of a merged PR). This is the key metric. A dropping value
  is your alarm.
- **Run Log** (`/run-log?date=<YYYY-MM-DD>&env=dev`) — type `batch` in the
  search box (or use `&q=batch`) to filter for Tide batch runs. A cluster
  of failing batches means the queue is blocked. Each row links to the Prow
  job and shows the matched failure.
- **Failure Patterns** (`/failure-patterns`) — this is a triage tool, not a
  monitoring tool. Use it to rank the most impactful issues by run-impact %.
  Category signals (Regression vs. Flake, provision & e2e only) help
  separate a new PR-induced break from a long-standing flake.

### Triage guidance

- **Flake vs. regression**: Tide merges PRs in batches; every PR in a batch
  has already passed e2e on its own. A failing Tide batch is either a flake
  or a bad interaction between batched PRs. Don't chase every red run.
- **Timeout patterns**: Patterns like `CreateHCPClusterAndWait`,
  `context deadline exceeded`, etc. are generic timeouts hiding distinct
  root causes. Occurrence count alone is meaningless. Timeouts require
  deeper analysis from Kusto logs using `hcpctl snapshot analyze`
  against the run's snapshot.

## Escalation

When the IC cannot resolve an issue, or the issue belongs to a component
outside Service Lifecycle's responsibility:

1. **Identify the owning team** using the
   [Service Component Escalation Paths](https://docs.google.com/document/d/1fqH__2cv0GU4oiUYAnhl08x61b7CuDbVi3OkC-J58LA/edit?tab=t.0)
   (maintained externally).
2. **Follow the prescribed channel** — open the appropriate tickets and/or
   engage via the documented Slack channels for that component.
3. **Document the escalation** in the shift log with: who was
   contacted, when, via what channel, and the current status.

## Swarm

A Swarm should be initiated when the IC is overwhelmed by a high volume of
complex interruptions (rollouts, critical alerts, major incidents) that make
completing the shift unsustainable.

### How to Initiate

1. Use the `/Swarm` command in `#hcm-aro-team-service-lifecycle`.
2. Select the service **"ARO SLC Swarm"**.
3. Specify:
   - The **region (GEO)** from which assistance is required.
   - The **number of associates** needed.

### Expectations

Team members summoned by a Swarm are expected to:

- Respond promptly
- Assess the required assistance
- Assume a portion of the on-call workload from the IC

## Chat Excerpt Rules

These rules are absolute. Oncall decisions often trace back to Slack
conversations, and without proper attribution the context is lost.

1. **Always record who said it** — use their Slack display name.
2. **Always record when** — timestamp from Slack (format: `[HH:MM AM/PM]`).
3. **Always include the Slack link** — if not provided by the user, ask for
   it explicitly: *"What's the Slack link for that message?"*
4. **Preserve the original wording** for critical decisions — don't
   paraphrase instructions like "cancel the rollout" or "get approval from X".
5. **Flag missing attribution** — if you can't determine who said something
   or when, record it with `*(attribution unclear — verify)*`.

## JIRA Label Enforcement

JIRA tickets are reserved for actual work products — incidents, bugs,
actionable tasks. Shift tracking is done in local shift logs, NOT JIRA.

However, any JIRA ticket created or updated during an oncall shift
**must** have the `oncall` label. This includes:

- Incident tickets
- Bug reports
- Remediation tasks
- Any existing tickets updated as part of oncall work

When updating an existing ticket that doesn't have the `oncall` label, add
it via `mcp_jira_editJiraIssue` with
`fields: {"labels": [<existing_labels>, "oncall"]}`.

## Associate Obligations

By participating in the oncall rotation, associates agree to:

- **Acknowledgement SLA**: Always acknowledge alerts within the escalation
  policy window (typically 10-15 minutes for pages, 30 minutes for IcM).
- **Fitness for duty**: Associates must not be impaired by alcohol or
  medication that affects their ability to perform technical tasks.
- **Replacement responsibility**: If unable to fulfill duties, source a
  replacement and put in an override into IcM. If unable to find a
  replacement (or in an emergency/illness), inform your manager and get
  confirmation.
- **Comp day**: Working a Recharge Day or Company-Funded Day entitles the
  associate to one Comp Day, which must be taken within two weeks.

## Reference: Policy Documents

| Document | URL |
|----------|-----|
| JIRA Hygiene Policy | https://docs.google.com/document/d/1jLwHt00p5EyW4hYIUlDleQGh0K96UfZrmcp-BJ3BmaM/ |
| Service Component Escalation Paths | https://docs.google.com/document/d/1fqH__2cv0GU4oiUYAnhl08x61b7CuDbVi3OkC-J58LA/edit?tab=t.0 |
| On-Call Policy & Operations | https://docs.google.com/document/d/1fqH__2cv0GU4oiUYAnhl08x61b7CuDbVi3OkC-J58LA/edit?tab=t.0#heading=h.x4lbuvw3431e |
| Quality Call Notes | https://docs.google.com/document/d/1dX_CsGpS0hsU0lETbsRgIaLFrQIg-frH-7qzJN8d13A/edit?tab=t.0 |
| Handover Ticket Dashboard | https://redhat.atlassian.net/jira/software/c/projects/AROSLSRE/boards/11820 |
| Prow Status (ARO-HCP) | https://prow.ci.openshift.org/?repo=Azure%2FARO-HCP |
| Azure Pipelines Rollout Status | https://dev.azure.com/msazure/AzureRedHatOpenShift/_build?pipelineNameFilter=Entrypoint*HCP |
| IcM Portal (active incidents) | https://portal.microsofticm.com/imp/v3/overview/main?q=ACTIVE&st=predefined_2 |

## Reference: MCP Tools Used

| Tool | Purpose |
|------|---------|
| Local shift log (`~/.local/share/oncall-shifts/`) | Create and update shift tracking markdown files |
| `mcp_jira_createJiraIssue` | Create incident/bug tickets (NOT shift tracking) |
| `mcp_jira_editJiraIssue` | Add labels, update fields |
| `mcp_jira_searchJiraIssuesUsingJql` | Find related tickets |
| `mcp_jira_getJiraIssue` | Read current ticket state |

## Reference: Component IDs

| Component | ID |
|-----------|----|
| aro-hcp-oncall | 84116 |
| aro-hcp-releases | 83787 |
| aro-hcp-e2e | 83786 |
| aro-hcp-ci | 32027 |
| aro-hcp-infra | 84112 |
| aro-hcp-observability | 84111 |
