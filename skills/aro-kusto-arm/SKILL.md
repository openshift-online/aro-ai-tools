---
name: aro-kusto-arm
description: Investigate Azure Resource Manager operations in internal ARM Kusto logs. Use for correlation-ID timelines, downstream resource-provider calls, long-running operations, deployment failures, retries, and escalation evidence.
allowed-tools: shell
---

# ARM Kusto Investigation

Use internal Azure Resource Manager (ARM) request logs to reconstruct control-plane
operations and identify where a request failed or spent time. This skill applies
to any Azure resource provider; do not assume the affected service, provider, or
resource type in advance.

Use `aro-kusto` for Kusto schema discovery, query execution, and ADX links. This
skill supplies the ARM-specific investigation workflow and query patterns.

## Inputs

Collect as many of these as are available:

- UTC time window, kept as narrow as practical
- ARM correlation ID, activity ID, client request ID, or service request ID
- subscription, resource group, resource ID, deployment name, or operation name
- failed status, error code, and error message
- a successful retry or comparison operation

Do not block when a correlation ID is unavailable. Start from the resource ID and
time window, then discover the request identifiers from matching rows.

## ARM log locations

Known ARM Logs v2 clusters include:

- `https://armprodeus.eastus.kusto.windows.net`
- `https://armprodweu.westeurope.kusto.windows.net`
- `https://armprodsea.southeastasia.kusto.windows.net`

The commonly used tables are:

- `Requests.HttpIncomingRequests`: requests received by ARM
- `Requests.HttpOutgoingRequests`: calls from ARM to downstream resource providers

Always fully qualify the cluster, database, and table. A resource's Azure region
does not determine which ARM log cluster contains the request, so search other
known clusters when the first query returns no evidence.

Access to these internal clusters is permission-dependent. If access is denied,
report the cluster and error rather than treating the absence of results as
evidence that the request did not occur.

## Investigation workflow

1. **Bound the search.** Start with the narrowest reliable UTC time range. Never
   run an unbounded correlation or resource-ID search.
2. **Discover the schema.** Use `aro-kusto` to inspect the `Requests` database.
   Treat table names and columns as unknown until verified. ARM schemas can differ
   across clusters and evolve over time.
3. **Find the operation.** Search incoming and outgoing tables for all available
   request identifiers. If none are known, search by resource ID or deployment
   name and extract the identifiers.
4. **Summarize before expanding.** A single operation can produce thousands of
   polling rows. Group by source table, provider, operation, method, and status
   before reading the detailed timeline.
5. **Reconstruct the call chain.** Distinguish the client-to-ARM request from
   ARM-to-provider calls. Extract downstream resource IDs and request identifiers
   from `HttpOutgoingRequests`.
6. **Reduce polling noise.** Focus on writes, failures, long-duration calls,
   exceptions, and state transitions. Keep polling rows only when their cadence
   or terminal result is relevant.
7. **Measure time.** Compare first/last observations, recorded request duration,
   and gaps between adjacent events. These are different measurements; label them
   accurately.
8. **Compare retries when available.** Determine whether a retry created, reused,
   or skipped downstream resources. Retry success alone does not prove the
   original dependency recovered.
9. **Pivot to provider logs.** ARM logs show the control-plane boundary, not
   necessarily the provider's internal cause. Carry the downstream resource ID,
   request IDs, status, and exact UTC window into the provider-specific logs.

Reusable queries are in [references/kql-recipes.md](references/kql-recipes.md).
Adapt provider and resource filters only after inspecting the actual rows.

## Query discipline

- Query both incoming and outgoing request tables.
- Use `column_ifexists()` for optional fields after verifying the base schema.
- Normalize identifiers with `tostring()` and compare GUIDs case-insensitively.
- Project only the fields needed for the current step.
- Start with counts and summaries; retrieve detailed rows only for the narrowed
  operation.
- Keep the original timestamps and identifiers in exported evidence.
- Do not infer completion from an accepted `202`; follow the long-running
  operation or polling sequence to its terminal state.
- Do not interpret a large gap by itself. Show the event immediately before and
  after it and check whether a long request duration accounts for the gap.
- Do not assume an HTTP failure identifies the root cause. It establishes the
  failing boundary; provider logs may be required for the internal cause.

## Evidence standard

Separate:

- **Observed:** exact ARM rows, timestamps, status codes, durations, resource IDs,
  and request identifiers.
- **Supported conclusion:** the narrowest failing or waiting boundary established
  by those rows.
- **Unknown:** provider-internal work not visible in ARM logs.

For each material claim, retain the query or ADX link that supports it.

## Report format

```text
ARM investigation

Scope:
- Time window:
- Identifier(s):
- Resource(s):
- ARM cluster(s) and tables:

Timeline:
- <UTC timestamp> <incoming/outgoing> <method> <resource/operation> <status>

Findings:
- Client-to-ARM result:
- Downstream provider calls:
- Longest observed request or timeline gap:
- Retry comparison:

Conclusion:
- Established failure or wait boundary:
- Evidence:
- Remaining uncertainty:
- Recommended owner or next log source:
```

## Common mistakes

- Searching only the Azure region nearest the resource
- Querying only `HttpIncomingRequests`
- Assuming fields copied from a previous incident still exist
- Treating repeated polling as separate failures
- Calling an upsert a creation without evidence that the resource was absent
- Treating retry success as proof of root cause
- Assigning provider-internal blame from ARM boundary evidence alone
