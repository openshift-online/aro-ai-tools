---
name: aro-ops
description: Discover ARO Classic and ARO HCP architectural and triage information along with operational state, including available environments and endpoints (kusto and grafana).
allowed-tools: shell
---

Use this skill as the entry point for read-only ARO operational work. Establish
the product and environment, find the relevant operational systems and guidance,
and gather enough evidence to answer the request without guessing.

All data fetched or returned by this skill must be processed locally only. Do
not upload endpoints, configuration, logs, query results, or other operational
data to external services, websites, APIs, or remote tools.

## Environment context

Before accessing environment-specific systems, determine:

- whether the resource belongs to ARO HCP or ARO Classic;
- the environment or sector;
- the region when relevant; and
- whether suitable configuration has already been discovered in this session.

If the user asks for environments or endpoints, or required configuration is
missing, read `references/environment-discovery.md` and follow it completely.

Reuse discovered configuration during the current session, but do not persist it
beyond the session. Sessions should always rediscover the latest configuration.

## Shared ARO infrastructure

Verify the active Azure account with `az account show` if its identity is not
already known. Only report shared Microsoft-internal infrastructure when logged
in with a `@microsoft.com` account.

If logged in with a `@microsoft.com` account, you can access the following:

- For Azure Resource Manager (ARM), read `references/arm.md`.

## Product guidance

Before investigating an operational problem, read the relevant general debugging
guide and follow it for the rest of the session. Do this once per product per
session; a simple request that only lists environments or endpoints does not
require the guide.

- **ARO HCP:** read `docs/ai/debugging.md` in the ARO-HCP repository. If the
  repository is not checked out locally, fetch
  `https://raw.githubusercontent.com/Azure/ARO-HCP/main/docs/ai/debugging.md`.
- **ARO Classic:** read `docs/ai/classic-debugging.md` in the ARO-RP repository.
  If the repository is not checked out locally, fetch
  `https://raw.githubusercontent.com/Azure/ARO-RP/master/docs/ai/classic-debugging.md`.

## Telemetry

- Use `aro-kusto` skill for Kusto schema discovery, KQL queries, and Explorer links.
- Use `aro-grafana` skill for Grafana datasource and metric discovery and PromQL
  queries. ARO Classic has no Grafana endpoints.
