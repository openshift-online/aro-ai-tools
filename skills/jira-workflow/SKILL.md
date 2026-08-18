---
name: jira-workflow
description: Manage JIRA issue lifecycle and status transitions in the ARO HCP space. Covers workflow states, transition rules, Blocked handling, Release Pending, and full lifecycle for all issue types including Features, Initiatives, Epics, Tasks, Bugs, and Spikes.
---

## Personal Overrides

If a `SKILL.local.md` file exists in this skill's directory, read it before
proceeding. It contains personal defaults (e.g. team name, default labels,
components) that augment (never contradict) the directions below. These files
are gitignored and persist across upstream skill updates.

**First-time setup**: If no `SKILL.local.md` exists and the user has not
previously configured their team, prompt them to create one by selecting their
team from the Team Field Values table in `create-jira-issue`. Store their
selection so workflow operations can reference the correct team.

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

# JIRA Workflow Management

## What I Do

Manage JIRA issue status transitions, lifecycle enforcement, and workflow
correctness across the ARO HCP space. This skill is the single source of
truth for:

- Which statuses exist and what they mean
- Valid transition paths per issue type
- When to use Blocked, Release Pending, and other special states
- Feature/Initiative lifecycle (L4) and Outcome (L5) management
- Definition of Ready and Definition of Done per issue type

## Related Skills

| Skill | Purpose |
|-------|---------|
| `create-jira-issue` | Creates new JIRA issues with correct fields and structure. References this skill for workflow transitions after creation. |
| `groom-jira` | Backlog grooming, stale ticket detection, and weekly status update preparation. References this skill for valid status transitions. |

## When to Use Me

- Transitioning an issue between statuses
- Determining the correct next status for a ticket
- Understanding what fields are required at each lifecycle stage
- Managing Feature or Initiative lifecycle
- Setting or clearing Blocked status
- Moving a ticket to Release Pending after code is merged but before
  production rollout
- Reviewing whether a ticket meets Definition of Ready or Done

## JIRA Hierarchy

```
Outcome (L5)  ->  Feature/Initiative (L4)  ->  Epic (L3)  ->  Story/Task/Bug/Spike (L2)  ->  Sub-task
   Planning spaces (HPSTRAT, OCPSTRAT)          Execution spaces (AROSLSRE, ARO, HOSTEDCP, AROSLSRE, OSDOCS)
```

### Issue Type Definitions

| Level | Type | Space | Description |
|-------|------|-------|-------------|
| 5 | Outcome | HPSTRAT, OCPSTRAT | Major strategic goal or roadmap deliverable tied to corporate strategy via observable/measurable business results. |
| 4 | Feature | HPSTRAT, OCPSTRAT | Functional area of the product supporting specific use cases or product increments. Describes "What" and "Why", not "How". |
| 4 | Initiative | HPSTRAT, OCPSTRAT | Larger goals not directly on the product roadmap. Architectural or improvement focused work with clear completion criteria. Not a bucket for Epics. |
| 3 | Epic | ARO, HOSTEDCP, AROSLSRE | Extra-large work that will not fit in a single sprint. Includes acceptance criteria from end-user perspective. Generally associated with a single team/function. |
| 2 | Story | ARO, HOSTEDCP, AROSLSRE | Short description of a capability from the perspective of the person who desires it. |
| 2 | Task | ARO, HOSTEDCP, AROSLSRE | Finite piece of work. Post-meeting follow-ups, action items, oncall investigations. |
| 2 | Bug | ARO, HOSTEDCP, AROSLSRE | Error, flaw, or fault causing incorrect or unexpected results. |
| 2 | Spike | ARO, HOSTEDCP, AROSLSRE | Time-boxed research activity. Uses Story issue type with `spike` label. |

## Status Definitions

All issue types share the same status set, but not all statuses are used by
every type. See the per-type workflow sections below for which statuses apply.

| Status | ID | Meaning |
|--------|----|---------|
| New | 11 | Newly created, not yet triaged or prioritized. |
| Refinement | 31 | Being refined: description, acceptance criteria, dependencies being defined. |
| Backlog | 21 | Triaged and refined, but not yet ready for active development. May be blocked by other work. |
| To Do | 41 | Definition of Ready is met. Ready for a developer to pick up. |
| In Progress | 51 | Actively being worked on in the current sprint. |
| Blocked | — | Work is stalled due to an external dependency, upstream issue, or unresolved question. Set `customfield_10517` to `True` and document the blocking reason in a comment. Blocked is an overlay on any active status (In Progress, To Do, Backlog). The ticket remains in its current status column but is flagged. |
| Review | 61 | Code review, QE verification, or stakeholder review in progress. |
| Release Pending | 71 | Code is merged and verified but not yet rolled out to all production regions. Transition to Closed once the change is live in production. |
| Closed | 81 | Definition of Done met and code is in production, OR ticket was rejected/cancelled during triage. |

### Blocked Status Rules

Blocked is not a separate workflow column. It is a flag applied to tickets
in any active state:

1. Set `customfield_10517` = `True` when the ticket cannot progress.
2. Add a comment explaining **what** is blocking, **who** owns the blocker,
   and **when** it is expected to resolve.
3. Link the blocking issue using `Blocks` link type if applicable.
4. Set `customfield_10517` = `False` when the blocker is resolved.
5. During grooming, any ticket that has not progressed for 14+ days should
   be evaluated for Blocked status (see `groom-jira` skill).

### Release Pending Rules

Release Pending bridges the gap between "code merged" and "live in production":

1. Transition to Release Pending (ID: 71) after PR is merged and all
   environments except production have been verified.
2. The ticket remains in Release Pending until the change is confirmed
   live in all production regions.
3. Transition to Closed (ID: 81) once production rollout is complete.
4. If a rollback occurs from production, move back to In Progress (ID: 51).

## Workflows by Issue Type

### Task Workflow

```
New -> Backlog -> To Do -> In Progress -> Review -> Release Pending -> Closed
                                 |                        |
                                 +--- Blocked (flag) -----+
```

| Status | Entry Criteria | Required Fields |
|--------|---------------|-----------------|
| New | Ticket just created | Description (initial draft), Team field |
| Backlog | Refinement in progress | — |
| To Do | Definition of Ready met | Priority, Size, Acceptance Criteria, Components, Team field, not Blocked |
| In Progress | Pulled into sprint | Parent ticket should also be In Progress |
| Review | Code review in progress | — |
| Release Pending | PR merged, not yet in production | — |
| Closed | DoD met and in production, OR rejected at triage | Resolution set |

### Story Workflow

Same as Task workflow. Stories are preferred over Tasks when sub-tasks are
likely, cross-team coordination is needed, or the work delivers a user-facing
capability.

### Bug Workflow

```
New -> Backlog -> To Do -> In Progress -> Review -> Release Pending -> Closed
  |                                         |            |
  |                                         +-- (QE fail: back to In Progress)
  +-- (invalid: straight to Closed)
```

| Status | Entry Criteria | Required Fields |
|--------|---------------|-----------------|
| New | Bug reported, awaiting triage | Description, reproduction steps, Team field |
| Refinement | Not used for Bugs | — |
| Backlog | Triaged but blocked by upstream fix or backport | — |
| To Do | Bug is valid, testable, fix target agreed | Fix Version, Team field |
| In Progress | Developer actively working | — |
| Review | Fix in code review. If QA contact is set, ready for QE verification | QA contact (if QE testing accepted) |
| Release Pending | Fix merged, awaiting production rollout | — |
| Closed | Fix verified in production, OR bug is invalid | Resolution set |

**Bug Triage Process:**

The Bug Triage Meeting is asynchronous, driven by QE:
1. QE reviews the bug queue in JIRA
2. For each bug, the team agrees:
   - The bug describes a valid problem (if not, close with reasoning)
   - There are enough details to reproduce (if not, request more info)
   - Testing procedure is defined
   - Testing owner is assigned
3. Once agreement is reached, transition from New to To Do
4. QE may assign "QA contact" and describe proposed testing scope

### Spike Workflow

```
New -> To Do -> In Progress -> Closed
```

Spikes are time-boxed research. They use the Story issue type with the
`spike` label. They skip Review and Release Pending since they produce
knowledge, not deployable code.

### Epic Workflow

```
New -> Refinement -> Backlog -> In Progress -> Review -> Closed
                                    |
                                    +--- Blocked (flag)
```

| Status | Entry Criteria | Required Fields |
|--------|---------------|-----------------|
| New | Epic just created | Description (initial draft), Team field |
| Refinement | Being refined: description, child issues being written | Assignee, Description (all sections), Components, Priority, Parent, T-Shirt Size, Team field |
| Backlog / To Do | Refinement complete, ready for development | Epic ranked on team board |
| In Progress | Child tasks pulled into sprints | Parent Feature/Initiative should also be In Progress |
| Review | All child tasks complete, assignee verifying acceptance criteria | — |
| Closed | All child tasks Closed AND code rolled out to all production regions | Resolution set |

**Epic Sizing**: Not required at program level. If sizing at this level,
keep it consistent with the parent and up to date.

### Feature Workflow (Level 4)

```
New -> Refinement -> Backlog -> In Progress -> Review -> Closed
```

Features describe the "What" and "Why" of product functionality. They should
NOT prescribe "How" the implementation is performed.

**Good Feature Example**: "Track end to end customer transaction flow"
describes the What and Why even if CorrelationId is the known How.

**Bad Feature Example**: "Implement CorrelationId" fails to describe what
problem is being solved and why.

| Status | Entry Criteria | Required Fields & Actions |
|--------|---------------|--------------------------|
| New | Feature created, not yet triaged | Description (initial draft), Activity Type, Ranking, Label (Taxonomy) |
| Refinement | Prioritized, being refined | Assignee (set by EM/TL), Developer, Description (all sections complete), Components (at least 'ARO HCP'), Parent, MoSCoW, Epics created in relevant spaces and parented, Epics given relevant priority. Product Documentation Required = Yes triggers automatic Epic creation. |
| Backlog | All Refinement items finalized, ready for development | Feature assigned to assignees. Uncertainties tracked as separate epics/tasks. Note: Not all child Epics need to be in Backlog to move Feature to Backlog. |
| In Progress | Child Epics being developed | Weekly updates required (see Weekly Status Updates section) |
| Review | All Epics Closed, stakeholder review | Demo to stakeholders, Assignee and Reporter confirm Acceptance Criteria met |
| Closed | Acceptance Criteria met, MVP Epics Closed, OR rejected at triage | Ensure outstanding non-Critical Epics moved to follow-on Feature |

#### Feature Definition of Ready

Before engineering can start work:
- [ ] Product Manager and engineering assignee agree Feature is Ready
- [ ] Description complete: Overview, Acceptance Criteria, Definition of Done, References
- [ ] Architect determined approach (via ADR/DDR, spikes)
- [ ] Critical Epics defined at minimum
- [ ] Dependency tickets linked or created
- [ ] MoSCoW priority set
- [ ] Team field set (`customfield_10001`)
- [ ] Components set (at least 'ARO HCP') -- for functional categorization only

#### Feature Definition of Done

- [ ] Feature's own definition of done met (availability to end user specified)
- [ ] All Epics marked Closed with their own DoD met
- [ ] All aspects shipped to customer (including Docs)

### Initiative Workflow (Level 4)

Same workflow as Feature. Initiatives describe tangible deliverables
(architectural changes, new processes, investigatory work) that can be used by
Red Hat associates. They have clear start and stop criteria but do not
necessarily result in a new customer Feature.

**Good Initiative Examples**: "Internal Disaster Recovery",
"Automated Gating Tests"

**Bad Practice**: Using Initiatives as a bucket/dumping ground for Epics.

### Outcome Workflow (Level 5)

Outcomes represent major strategic goals tied to corporate strategy. They are
managed by PMs and EMs in the planning spaces (HPSTRAT, OCPSTRAT).
This skill does not manage Outcome transitions directly.

## Weekly Status Updates (In Progress Features/Epics)

For any Feature or Epic in "In Progress" status, update weekly:

### Color Status

| Color | Meaning |
|-------|---------|
| Green | On track for the current milestone |
| Yellow | Off track with risks that can be mitigated or are being worked on |
| Red | Off track and cannot be de-risked to meet milestone timeline |

### Status Summary (update weekly)

Include:
- Status date (date the summary was added)
- High level status
- Risks (if any) and mitigation actions
- Testing status (E2E automated feature test status)

### Blocked Field

- Set to `True` if blocked
- Set to `False` if not blocked
- Leave unset if the feature is not being actively worked on

### Blocked Reason

Document the blocking reason when Blocked is True.

### Target End Date

Update if timeline has changed.

## Activity Type Labels (Taxonomy)

Apply one Activity Type label to Features and Initiatives for reporting:

| Label | Use When |
|-------|----------|
| `s360sreoperability` | SRE operability improvements (internal reliability, tooling, automation) |
| `engineeringoperability` | Engineering process or platform improvements |
| `customerexperience` | Improvement or ease of use of existing feature (e.g. error codes, UX) |
| `customerfeature` | New capability for customers (e.g. 500 worker node support) |

These labels are lowercase per team convention.

## Status Transition Quick Reference

| ID | Name | Target Status |
|----|------|---------------|
| 11 | New | New |
| 21 | Backlog | Backlog |
| 31 | Refinement | Refinement |
| 41 | To Do | To Do |
| 51 | In Progress | In Progress |
| 61 | Review | Review |
| 71 | Release Pending | Release Pending (Done) |
| 81 | Closed | Closed (Done) |

## MCP Tools Reference

| Tool | Purpose |
|------|---------|
| `mcp_jira_transitionJiraIssue` | Change issue status |
| `mcp_jira_editJiraIssue` | Update fields (Blocked, Color Status, Status Summary) |
| `mcp_jira_getTransitionsForJiraIssue` | List available transitions for an issue |
| `mcp_jira_getJiraIssue` | Read current issue state |
| `mcp_jira_addCommentToJiraIssue` | Add blocking reason or status update comments |
| `mcp_jira_createIssueLink` | Link blocking/blocked issues |

## Technical Notes

1. **Cloud ID** is `2b9e35e3-6bd3-4cec-b838-f4249ee02432` for the Red Hat
   Atlassian instance.

2. **Blocked field** (`customfield_10517`) is a string: `"True"` or `"False"`.

3. **Content format**: Always use `contentFormat: "markdown"` for comments.
   - Bold: use single asterisks `*bold*`
   - Links: use short-form `[text](url)` -- never paste bare full URLs
   - JIRA keys: write them bare (e.g. `AROSLSRE-123`) -- JIRA auto-links them
   - Headings: use `##` and `###`
   - Code: use triple-backtick fenced blocks with language tag

4. **Release Pending vs Closed**: A ticket in Release Pending has merged code
   that is not yet in production. Only transition to Closed when the change is
   confirmed live in all production regions. If a rollback occurs, move back
   to In Progress.

5. **Feature/Initiative statuses are not subject to standard stale-ticket
   automation** (see `groom-jira` skill for extended lifecycle rules).

6. **Team field** (`customfield_10001`): Required on all tickets. The source
   of truth for team ownership, replacing component-based and label-based team
   identification. Pass as `{"name": "ARO HCP - Service Lifecycle West"}`.
   Components remain for functional area categorization only. See
   `create-jira-issue` for the full list of team values.
