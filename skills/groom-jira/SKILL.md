---
name: groom-jira
description: Groom the JIRA backlog for the ARO HCP space. Detect stale tickets, enforce close policies, run backlog refinement checks, prepare tickets for weekly status updates, and flag stuck work as Blocked. Use when grooming the backlog, reviewing stale issues, preparing for program calls, or enforcing JIRA hygiene.
---

## Personal Overrides

If a `SKILL.local.md` file exists in this skill's directory, read it before
proceeding. It contains personal instructions that augment (never contradict)
the directions below. These files are gitignored and persist across upstream
skill updates.

## Policy Staleness Check

When this skill is loaded, check its last-modified date:

```bash
git log -1 --format="%ai" -- <path-to-this-SKILL.md>
```

If the file has not been modified in over **90 days**, warn the user:

> This skill has not been updated in over 90 days. The upstream
> [ARO HCP JIRA governance conventions][governance-doc] may have changed.
> Please compare this skill against the Google Doc and update if needed
> before relying on its guidance.

[governance-doc]: https://docs.google.com/document/d/1jLwHt00p5EyW4hYIUlDleQGh0K96UfZrmcp-BJ3BmaM

# JIRA Backlog Grooming

## What I Do

Enforce JIRA hygiene and backlog health for the ARO HCP space:

1. **Detect stale tickets** based on inactivity thresholds per issue type
2. **Enforce close policy** with correct Resolution and closing comments
3. **Flag stuck work** by identifying tickets that should be marked Blocked
4. **Prepare for weekly status updates** by checking that In Progress
   Features/Epics have current Color Status, Status Summary, and Blocked fields
5. **Run backlog refinement checks** to surface aging tickets before they
   hit automated purge thresholds

## Related Skills

| Skill | Purpose |
|-------|---------|
| `create-jira-issue` | Creates new JIRA issues with correct fields and structure. |
| `jira-workflow` | Single source of truth for all JIRA status definitions, transition rules, Blocked handling, Release Pending, and per-issue-type lifecycle. This skill references `jira-workflow` for valid statuses and transitions. |

## When to Use Me

- Grooming or cleaning the JIRA backlog
- Reviewing stale or aging tickets
- Preparing for the bi-weekly Program Call or Sprint Planning
- Checking that tickets are ready for weekly status reporting
- Closing stale tickets with proper resolution and comments
- Identifying work that is stuck and should be flagged as Blocked
- Reviewing the "ARO HCP Oldest Issues" saved filter

## Stale Ticket Detection

### Inactivity Thresholds for L2/L3 Items (Epic, Story, Task, Bug, Spike)

A ticket is considered stale if it has had no comments, assignment changes,
or status updates for the specified period.

| Ticket Status | Stale Threshold | Action |
|---------------|----------------|--------|
| Active Sprint / In Progress | 14 days | **The Ping**: Assignee is pinged (automated or manual) to check for blockers or stalled work. Evaluate whether the ticket should be set to Blocked. |
| Active Sprint / In Progress | 30 days | **The Eviction**: Ticket must be unassigned, moved out of the active sprint, and returned to Backlog. In-flight work should not sit idle for a month. |
| Product Backlog / To Do | 90 days | **The Warning**: An automated comment flags the issue as stale and requests an update from the assignee/reporter. |
| Product Backlog / To Do | 120 days | **The Purge**: Ticket is automatically closed to keep the backlog actionable. |

### Blocked Status Enforcement

During grooming, evaluate every ticket that has not progressed in 14+ days:

1. If the ticket is In Progress but no commits, comments, or status changes
   in 14 days, ask the assignee: is this blocked?
2. If blocked, set `customfield_10517` = `True` and add a comment documenting
   the blocker, owner, and expected resolution date.
3. If not blocked but simply deprioritized, move to Backlog.
4. If the work is no longer needed, close with Resolution = "Won't Do".

### Extended Lifecycles for Features, Epics, and Initiatives (L3/L4)

Features, Epics, and Initiatives represent long-term strategic goals and are
exempt from the standard 90-day automated purge. Their staleness is measured
by **child-issue activity**.

#### The "Child Activity" Rule

A Feature, Epic, or Initiative is NOT considered stale if its child
stories/tasks are actively being worked on.

**The Rule**: A Feature/Epic/Initiative is only flagged as stale if BOTH the
parent ticket AND all of its child tickets have seen zero activity for the
specified period.

| Issue Type | Stale Warning | Automated Action | Exceptions |
|------------|--------------|-----------------|------------|
| Feature / Epic | 180 days (6 months) | Comment tagging Product Owner / Epic Owner to review | Exempt if linked to an active upstream Red Hat or Microsoft dependency |
| Initiative | 270 days (9 months) | Flagged for review during next quarter's planning | Exempt if in "Roadmap" or "Future" status |

#### Status Exclusions ("Safe Harbors")

Tickets in the following statuses are completely exempt from stale-ticket
automation, as they represent future planning:

- **Proposed / Discovery**
- **Roadmap / Future**
- **On Hold** (must have a documented reason in comments for why it is paused)

## Close Policy

**Closed does not mean Deleted.** If a bug or feature has not been relevant
enough to touch in 3-4 months, it is not a current priority.

### Resolution Field

When closing a stale ticket, always set the Resolution dropdown:

| Scenario | Resolution Value |
|----------|-----------------|
| Ticket closed due to inactivity | `Inactivity` |
| Ticket intentionally deprioritized | `Won't Do` |
| Ticket completed successfully | `Done` |
| Ticket is a duplicate | `Duplicate` |
| Bug is not reproducible or invalid | `Cannot Reproduce` or `Won't Do` |

**Never leave Resolution blank** when closing a ticket. Never mark a
stale ticket as `Done`.

### Closing Comment Template

Always leave a clean paper trail before closing a stale ticket. Use or
adapt the following:

```
Closing this ticket due to {X} days of absolute inactivity.
If this issue or feature request is still relevant to the ARO HCP
deployment, please feel free to reopen it with updated context.
```

## Backlog Refinement Protocol

During standard ARO HCP backlog grooming sessions, dedicate the **first
5 minutes** to reviewing aging tickets:

### Step 1 — Review Oldest Issues

Query for tickets not updated in 60+ days:

```
Tool: mcp_jira_searchJiraIssuesUsingJql
cloudId: 2b9e35e3-6bd3-4cec-b838-f4249ee02432
jql: project = AROSLSRE AND updated <= -60d AND status not in (Closed) AND component = "ARO-HCP" ORDER BY updated ASC
maxResults: 20
fields: ["summary", "status", "assignee", "updated", "priority", "issuetype"]
```

### Step 2 — Triage Each Ticket

For each aging ticket, decide:

1. **Still relevant?** If yes, update with current context and re-prioritize.
2. **Blocked?** If yes, set Blocked flag and document the blocker.
3. **No longer needed?** Close with Resolution = "Won't Do" and the closing
   comment template.
4. **Needs investigation?** Create a Spike to determine relevance.

### Step 3 — Review In Progress Tickets for Staleness

Query for In Progress tickets not updated in 14+ days:

```
Tool: mcp_jira_searchJiraIssuesUsingJql
cloudId: 2b9e35e3-6bd3-4cec-b838-f4249ee02432
jql: project = AROSLSRE AND status = "In Progress" AND updated <= -14d AND component = "ARO-HCP" ORDER BY updated ASC
maxResults: 20
fields: ["summary", "status", "assignee", "updated", "priority", "issuetype"]
```

For each result:
- Ping the assignee to check for blockers
- If 30+ days stale, evict from sprint and return to Backlog

## Weekly Status Update Preparation

This section ensures that tickets are ready for the weekly program status
process. Engineers own the ticket content; the grooming process ensures that
content is present and current.

### What Needs Weekly Updates

Any Feature or Epic in **In Progress** status must have current weekly fields.
The bi-weekly Program Call doc is the source of truth for overall status.

### Pre-Status-Update Checklist

Run this check before each weekly status cycle:

```
Tool: mcp_jira_searchJiraIssuesUsingJql
cloudId: 2b9e35e3-6bd3-4cec-b838-f4249ee02432
jql: project in (AROSLSRE, HPSTRAT) AND status = "In Progress" AND issuetype in (Feature, Epic) AND component = "ARO-HCP" ORDER BY priority ASC
maxResults: 50
fields: ["summary", "status", "assignee", "customfield_10517", "priority", "issuetype"]
```

For each Feature/Epic in the results, verify:

- [ ] **Color Status** is set (Green / Yellow / Red)
- [ ] **Status Summary** is present and dated within the last 7 days
- [ ] **Blocked** field reflects actual state
  - If Blocked = True, **Blocked Reason** is documented
  - If ticket has not progressed in 14+ days but Blocked = False, flag for
    review
- [ ] **Target End Date** is set and still realistic
- [ ] **Testing status** is noted (E2E automated feature test status)

### Status Summary Format

Each Status Summary update should include:

```
*<YYYY-MM-DD>*
- Status: <Green/Yellow/Red>
- <High level status of the work>
- Risks: <any risks and mitigations, or "None">
- Testing: <E2E test status>
```

### Remediation

If a Feature/Epic is missing required weekly fields:

1. Add a comment tagging the assignee:
   ```
   @{assignee} — This ticket is In Progress but missing its weekly status
   update. Please update Color Status, Status Summary, and Blocked fields
   before the next program call.
   ```
2. If the ticket has been In Progress with no status update for 2+ weeks,
   escalate to the Engineering Manager.

## Automated Governance

Where possible, leverage global Jira Automation rules for:

- **90-day warning**: Automated comment on Backlog/To Do tickets
- **120-day closure**: Automated close with Resolution = "Inactivity"
- **14-day ping**: Automated reminder on In Progress tickets

This prevents spending unnecessary time manually chasing stale tickets.

## Grooming Cadence

| Activity | When | Duration | Participants |
|----------|------|----------|-------------|
| Backlog grooming (oldest issues review) | First 5 min of each grooming session | 5 min | Dev Team, PM |
| Sprint Planning | Every second Monday | 1 hr | Dev Team, Managers, Architect, Product, QE |
| Sprint Review/Demo | Every 4 weeks | 30 min | Dev Team, QE |
| Weekly status field check | Before each program call | 15 min | PM/EM or automated |

## JQL Quick Reference

| Purpose | JQL |
|---------|-----|
| Oldest untouched issues | `project = AROSLSRE AND updated <= -60d AND status not in (Closed) AND component = "ARO-HCP" ORDER BY updated ASC` |
| Stale In Progress (14d) | `project = AROSLSRE AND status = "In Progress" AND updated <= -14d AND component = "ARO-HCP" ORDER BY updated ASC` |
| Stale In Progress (30d eviction) | `project = AROSLSRE AND status = "In Progress" AND updated <= -30d AND component = "ARO-HCP" ORDER BY updated ASC` |
| Backlog purge candidates (120d) | `project = AROSLSRE AND status in ("Backlog", "To Do") AND updated <= -120d AND component = "ARO-HCP" ORDER BY updated ASC` |
| Features/Epics needing status update | `project in (AROSLSRE, HPSTRAT) AND status = "In Progress" AND issuetype in (Feature, Epic) AND component = "ARO-HCP" ORDER BY priority ASC` |
| All Blocked tickets | `project = AROSLSRE AND cf[10517] = "True" AND status not in (Closed) ORDER BY updated ASC` |
| Stale Features (180d, no child activity) | `project in (AROSLSRE, HPSTRAT) AND issuetype = Feature AND updated <= -180d AND status not in (Closed) ORDER BY updated ASC` |

## MCP Tools Reference

| Tool | Purpose |
|------|---------|
| `mcp_jira_searchJiraIssuesUsingJql` | Find stale, aging, or in-progress tickets |
| `mcp_jira_transitionJiraIssue` | Close stale tickets or move to Backlog |
| `mcp_jira_editJiraIssue` | Set Blocked flag, Resolution, Color Status |
| `mcp_jira_addCommentToJiraIssue` | Add closing comments, ping assignees, status updates |
| `mcp_jira_getJiraIssue` | Read current ticket state and fields |

## Technical Notes

1. **Cloud ID** is `2b9e35e3-6bd3-4cec-b838-f4249ee02432` for the Red Hat
   Atlassian instance.

2. **Resolution field**: When closing via `mcp_jira_editJiraIssue`, set
   `resolution` to `{"name": "Won't Do"}` or `{"name": "Done"}` before
   transitioning to Closed.

3. **Content format**: Always use `contentFormat: "markdown"` for comments.
   - Bold: use single asterisks `*bold*`
   - Links: use short-form `[text](url)` -- never paste bare full URLs
   - JIRA keys: write them bare (e.g. `AROSLSRE-123`) -- JIRA auto-links them
   - Headings: use `##` and `###`
   - Code: use triple-backtick fenced blocks with language tag

4. **Blocked field** (`customfield_10517`): String value `"True"` or `"False"`.

5. **Child Activity Rule**: When evaluating Feature/Initiative staleness,
   check child issues with:
   ```
   jql: parent = <FEATURE-KEY> AND updated >= -180d
   ```
   If any child has recent activity, the parent is NOT stale.

6. **Safe Harbor statuses**: Tickets in Proposed, Discovery, Roadmap, Future,
   or On Hold (with documented reason) are exempt from all stale automation.

7. For valid status transitions and detailed lifecycle rules per issue type,
   see the `jira-workflow` skill.
