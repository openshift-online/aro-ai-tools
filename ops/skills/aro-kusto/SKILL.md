---
name: aro-kusto
description: Explore and query ARO Kusto clusters — list databases, tables, and schemas, then run KQL queries to search logs, investigate errors, and debug provisioning, cluster lifecycle, and operational data. Use `aro-hcp-env-info` for HCP clusters or `aro-classic-env-info` for Classic clusters first to get the cluster URL.
allowed-tools: shell
---

## Arguments

- **Cluster** (required): A URL to a Kusto cluster (e.g. `https://my-cluster.kusto.windows.net`). If the cluster URL is not already known, use `aro-hcp-env-info` for HCP clusters or `aro-classic-env-info` for Classic clusters.
- **Database** (required for queries): Database to run the query against.
- **Kql** (required for queries): The KQL query to run.

## Instructions

### Choosing environment discovery

Before running Kusto metadata or KQL queries, determine the cluster type:

- If the user provides an Azure resource ID, infer the cluster type from the resource type:
  - Resource IDs containing `/providers/microsoft.redhatopenshift/hcpopenshiftclusters/` are **ARO HCP**; use `aro-hcp-env-info`.
  - Resource IDs containing `/providers/microsoft.redhatopenshift/openshiftclusters/` are **ARO Classic**; use `aro-classic-env-info`.
- For **ARO HCP**, use `aro-hcp-env-info` to discover Kusto endpoint fields such as `kusto` or `kustos`.
- For **ARO Classic**, use `aro-classic-env-info` to discover the sector Kusto endpoint in the `kusto` field and the recommended `defaultDatabase`. Select the Classic entry by the cluster's Azure region/location using the entry's `locations` list.
- If the cluster is **ARO Classic** and the region/location is not clear from the user's request or context, ask the user for the Azure region before choosing a Classic Kusto endpoint.
- If the user does not specify HCP or Classic and the cluster URL is not already present in context, ask the user for the cluster resource ID before choosing a discovery skill.

### Exploring cluster structure

1. Determine the Kusto cluster URL from context, or use the appropriate environment discovery skill above.
2. Detect the operating system and run the appropriate script:
   - On **macOS**: run `scripts/kusto.sh <subcommand> -Cluster CLUSTER [options]` using `zsh`.
   - On **Linux/WSL2**: run `scripts/kusto.sh <subcommand> -Cluster CLUSTER [options]` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/kusto.ps1 <subcommand> -Cluster CLUSTER [options]` using `pwsh`.
3. To get an overview of a cluster run the following script commands in order:
   - `list-databases -Cluster https://mycluster.kusto.windows.net`
   - for each db of interest: `show-schema-all -Cluster https://mycluster.kusto.windows.net -Database DB`

### Running queries

1. Determine the Kusto cluster URL and Database from context. If not present, explore the cluster structure first (see above).
2. Prepare a KQL query.
3. Detect the operating system and run the appropriate script:
   - On **macOS**: run `scripts/kquery.sh -Cluster CLUSTER -Database DB -Kql QUERY` using `zsh`.
   - On **Linux/WSL2**: run `scripts/kquery.sh -Cluster CLUSTER -Database DB -Kql QUERY` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/kquery.ps1 -Cluster CLUSTER -Database DB -Kql QUERY` using `pwsh`.

### Query output

The raw JSON response from the Kusto REST API is returned as-is. If the result set is truncated due to `-MaxRecords` being hit, the response will contain an additional row entry with a `OneApiErrors` field indicating truncation.

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
