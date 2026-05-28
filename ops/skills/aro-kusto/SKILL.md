---
name: aro-kusto
description: Explore and query ARO Kusto clusters — list databases, tables, and schemas, then run KQL queries to search logs, investigate errors, and debug provisioning, cluster lifecycle, and operational data. (Use `aro-hcp-env-info` or `aro-classic-env-info` first)
allowed-tools: shell
---

This skill works both with ARO Classic and ARO HCP.

## Arguments

- **Cluster** (required): A URL to a Kusto cluster (e.g. `https://my-cluster.kusto.windows.net`).
  If unknown, use `aro-hcp-env-info` or `aro-classic-env-info` to discover it.
  Tell HCP from Classic by the Azure resource ID (if provided):
    - `/providers/microsoft.redhatopenshift/hcpopenshiftclusters/` → HCP
    - `/providers/microsoft.redhatopenshift/openshiftclusters/` → Classic
  For Classic, pick the entry whose `locations` includes the cluster's Azure region otherwise ask the user to specify.
- **Database** (required for queries): Database to run the query against.
- **Kql** (required for queries): The KQL query to run.

## Instructions

### Required reading

Before running any other step in this skill, fetch the relevant debugging
guide and follow its guidance for the rest of this session. Do this once
per session, even if you believe you already know the schema — the guide
contains environment-specific gotchas not visible from the schema alone.

- **ARO HCP**: https://raw.githubusercontent.com/Azure/ARO-HCP/main/docs/ai/kusto-debugging.md
- **ARO Classic**: https://raw.githubusercontent.com/Azure/ARO-RP/master/docs/ai/classic-log-search.md

### Exploring cluster structure

1. Determine the Kusto cluster URL from context, or use the appropriate environment discovery skill (see Arguments above).
2. Detect the operating system and run the appropriate script:
   - On **macOS**: run `scripts/kusto.sh <subcommand> -Cluster CLUSTER [options]` using `zsh`.
   - On **Linux/WSL2**: run `scripts/kusto.sh <subcommand> -Cluster CLUSTER [options]` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/kusto.ps1 <subcommand> -Cluster CLUSTER [options]` using `pwsh`.
3. To get an overview of a cluster run the following script commands in order:
   - `list-databases -Cluster https://mycluster.kusto.windows.net`
   - for each db of interest: `show-schema-all -Cluster https://mycluster.kusto.windows.net -Database DB`

### Query discipline

- Treat table names, column names, and field casing as unknown until discovered in the current environment.
- Before writing a query that references table-specific fields, inspect the database/table schema or run a schema-safe probe.
- Do not borrow field names from another ARO environment, product, or previous incident unless you verify them first in the current environment.
- Do not run schema discovery and a schema-dependent query in parallel. Parallelize only independent discovery; construct dependent queries after reading the schema or sample rows.
- Every projected or filtered field in a query must come from current schema output, fetched product guidance, or a just-seen sample row.
- If Kusto reports a missing table or field, stop and rediscover schema instead of tweaking guesses.

### Running queries

1. Determine the Kusto cluster URL and Database from context. If not present, explore the cluster structure first (see above).
2. Prepare a KQL query.
3. Detect the operating system and run the appropriate script:
   - On **macOS**: run `scripts/kquery.sh -Cluster CLUSTER -Database DB -Kql QUERY` using `zsh`.
   - On **Linux/WSL2**: run `scripts/kquery.sh -Cluster CLUSTER -Database DB -Kql QUERY` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/kquery.ps1 -Cluster CLUSTER -Database DB -Kql QUERY` using `pwsh`.

### Query output

The raw JSON response from the Kusto REST API is returned as-is. If the result set is truncated due to `-MaxRecords` being hit, the response will contain an additional row entry with a `OneApiErrors` field indicating truncation.

## Presenting kusto queries and generating links

Whenever:
- You present a kusto query to the user
- The user explicitly asks for an ADX / Azure Data Explorer / Explorer link

1. Detect the operating system and run the appropriate script:
   - On **macOS**: run `scripts/klinks.sh -Cluster CLUSTER -Database DB -Kql QUERY` using `zsh`.
   - On **Linux/WSL2**: run `scripts/klinks.sh -Cluster CLUSTER -Database DB -Kql QUERY` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/klinks.ps1 -Cluster CLUSTER -Database DB -Kql QUERY` using `pwsh`.
2. Present the link to the user

## Reference

```
kusto (.ps1 and .sh) — Kusto cluster metadata (list databases, tables, schemas)

USAGE:
    kusto <subcommand> -Cluster <url> [-Database <name>] [options]

SUBCOMMANDS:
    list-databases              List all databases on the cluster
                                  Required: -Cluster
    show-tables                 List all tables in a database
                                  Required: -Cluster, -Database
    show-schema                 Show schema for a single table (as JSON)
                                  Required: -Cluster, -Database, -Table
    show-schema-all             Show full database schema (as JSON)
                                  Required: -Cluster, -Database

GLOBAL OPTIONS:
    -Cluster <url>              Kusto cluster URL (required)
                                  e.g. https://mycluster.region.kusto.windows.net
    -Database <name>            Database name (required except for list-databases)
    -Table <name>               Table name (required for show-schema)
    -MaxRecords <int>           Row limit (default: 1000, 0 = unlimited)

EXAMPLES:
    kusto list-databases -Cluster https://mycluster.region.kusto.windows.net
    kusto show-tables -Cluster https://mycluster.region.kusto.windows.net -Database mydb
    kusto show-schema -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Table mytable
    kusto show-schema-all -Cluster https://mycluster.region.kusto.windows.net -Database mydb
```

```
kquery (.ps1 and .sh) — Run arbitrary KQL queries against Kusto

USAGE:
    kquery -Cluster <url> -Database <name> -Kql <kql_string> [options]

REQUIRED:
    -Cluster <url>              Kusto cluster URL
                                  e.g. https://mycluster.region.kusto.windows.net
    -Database <name>            Database name
    -Kql <kql_string>           KQL query or control command

OPTIONS:
    -MaxRecords <int>           Row limit (default: 1000, 0 = unlimited)

EXAMPLES:
    .\kquery -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Kql "MyTable | take 10"
    .\kquery -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Kql "MyTable | summarize count() by col" -MaxRecords 0
```
