# ARM Kusto query recipes

These recipes are starting points. Verify the current schema first and replace
the cluster, time range, identifiers, and resource filters.

## Find an operation by request identifier

```kusto
let RequestId = "<request-id>";
let StartTime = datetime(<start-utc>);
let EndTime = datetime(<end-utc>);
union withsource=Source isfuzzy=true
    cluster("https://armprodeus.eastus.kusto.windows.net").database("Requests").HttpIncomingRequests,
    cluster("https://armprodeus.eastus.kusto.windows.net").database("Requests").HttpOutgoingRequests
| where TIMESTAMP between (StartTime .. EndTime)
| extend
    CorrelationId = tostring(column_ifexists("correlationId", "")),
    ActivityId = tostring(column_ifexists("ActivityId", "")),
    ClientRequestId = tostring(column_ifexists("clientRequestId", "")),
    ServiceRequestId = tostring(column_ifexists("serviceRequestId", "")),
    OperationId = tostring(column_ifexists("operationId", ""))
| where CorrelationId =~ RequestId
    or ActivityId =~ RequestId
    or ClientRequestId =~ RequestId
    or ServiceRequestId =~ RequestId
    or OperationId =~ RequestId
| project
    TIMESTAMP,
    Source,
    TaskName = tostring(column_ifexists("TaskName", "")),
    OperationName = tostring(column_ifexists("operationName", "")),
    Method = tostring(column_ifexists("httpMethod", "")),
    Status = toint(column_ifexists("httpStatusCode", int(null))),
    DurationMs = tolong(column_ifexists("durationInMilliseconds", long(null))),
    Provider = tostring(column_ifexists("resourceProvider", "")),
    TargetUri = tostring(column_ifexists("targetUri", "")),
    CorrelationId,
    ActivityId,
    ClientRequestId,
    ServiceRequestId,
    Exception = tostring(column_ifexists("exceptionMessage", ""))
| order by TIMESTAMP asc
```

If this returns no rows, repeat against the other known ARM clusters before
concluding that the identifier is absent.

## Discover request identifiers from a resource

```kusto
let Resource = "<resource-id-or-distinctive-fragment>";
let StartTime = datetime(<start-utc>);
let EndTime = datetime(<end-utc>);
union withsource=Source isfuzzy=true
    cluster("https://armprodeus.eastus.kusto.windows.net").database("Requests").HttpIncomingRequests,
    cluster("https://armprodeus.eastus.kusto.windows.net").database("Requests").HttpOutgoingRequests
| where TIMESTAMP between (StartTime .. EndTime)
| extend TargetUri = tostring(column_ifexists("targetUri", ""))
| where TargetUri has Resource
| summarize
    FirstSeen = min(TIMESTAMP),
    LastSeen = max(TIMESTAMP),
    Rows = count(),
    Methods = make_set(tostring(column_ifexists("httpMethod", "")), 10),
    Statuses = make_set(tostring(column_ifexists("httpStatusCode", int(null))), 20),
    SampleTarget = any(TargetUri)
  by
    Source,
    CorrelationId = tostring(column_ifexists("correlationId", "")),
    ActivityId = tostring(column_ifexists("ActivityId", "")),
    ClientRequestId = tostring(column_ifexists("clientRequestId", "")),
    ServiceRequestId = tostring(column_ifexists("serviceRequestId", ""))
| order by FirstSeen asc
```

## Summarize a noisy operation

Start from the identifier query, retain its filters, and replace the final
projection with:

```kusto
| summarize
    Rows = count(),
    FirstSeen = min(TIMESTAMP),
    LastSeen = max(TIMESTAMP),
    Statuses = make_set(tostring(column_ifexists("httpStatusCode", int(null))), 20),
    MaxDurationMs = max(tolong(column_ifexists("durationInMilliseconds", long(null)))),
    SampleTarget = any(tostring(column_ifexists("targetUri", "")))
  by
    Source,
    Provider = tostring(column_ifexists("resourceProvider", "")),
    OperationName = tostring(column_ifexists("operationName", "")),
    TaskName = tostring(column_ifexists("TaskName", "")),
    Method = tostring(column_ifexists("httpMethod", ""))
| order by Rows desc
```

## Remove low-value polling noise

Apply after the operation and resource filters:

```kusto
| extend
    Method = tostring(column_ifexists("httpMethod", "")),
    Status = toint(column_ifexists("httpStatusCode", int(null))),
    DurationMs = tolong(column_ifexists("durationInMilliseconds", long(null))),
    TaskName = tostring(column_ifexists("TaskName", "")),
    Exception = tostring(column_ifexists("exceptionMessage", ""))
| where Method !in~ ("GET", "HEAD", "OPTIONS")
    or Status >= 400
    or DurationMs >= 30000
    or TaskName has_any ("Failure", "Error", "Timeout")
    or Exception has_any ("Failure", "Error", "Timeout", "Exception")
```

## Find the largest timeline gaps

Start from a filtered operation query and project the material event fields,
then:

```kusto
| order by TIMESTAMP asc
| serialize
| extend
    PreviousTime = prev(TIMESTAMP),
    PreviousSource = prev(Source),
    PreviousOperation = prev(OperationName),
    PreviousMethod = prev(Method),
    PreviousStatus = prev(Status),
    PreviousTarget = prev(TargetUri),
    Gap = TIMESTAMP - PreviousTime
| where isnotnull(PreviousTime)
| top 25 by Gap desc
| project
    Gap,
    FromTime = PreviousTime,
    ToTime = TIMESTAMP,
    FromSource = PreviousSource,
    ToSource = Source,
    FromOperation = PreviousOperation,
    ToOperation = OperationName,
    FromMethod = PreviousMethod,
    ToMethod = Method,
    FromStatus = PreviousStatus,
    ToStatus = Status,
    FromTarget = PreviousTarget,
    ToTarget = TargetUri
```

Inspect the detailed rows around each gap. A gap may represent downstream work,
polling cadence, missing telemetry, or a long request recorded on one row.

## Compare multiple attempts

Use a small input table instead of duplicating queries:

```kusto
let Attempts = datatable(
    Case:string,
    ApproximateTime:datetime,
    CorrelationId:string
)
[
    "failed", datetime(<failed-time>), "<failed-correlation-id>",
    "retry", datetime(<retry-time>), "<retry-correlation-id>"
];
let StartTime = toscalar(Attempts | summarize min(ApproximateTime) - 30m);
let EndTime = toscalar(Attempts | summarize max(ApproximateTime) + 30m);
union withsource=Source isfuzzy=true
    cluster("https://armprodeus.eastus.kusto.windows.net").database("Requests").HttpIncomingRequests,
    cluster("https://armprodeus.eastus.kusto.windows.net").database("Requests").HttpOutgoingRequests
| where TIMESTAMP between (StartTime .. EndTime)
| extend CorrelationId = tostring(column_ifexists("correlationId", ""))
| join kind=inner (Attempts) on CorrelationId
| summarize
    FirstSeen = min(TIMESTAMP),
    LastSeen = max(TIMESTAMP),
    Rows = count(),
    Statuses = make_set(tostring(column_ifexists("httpStatusCode", int(null))), 20),
    Providers = make_set(tostring(column_ifexists("resourceProvider", "")), 20),
    SampleTarget = any(tostring(column_ifexists("targetUri", "")))
  by Case, CorrelationId
| order by FirstSeen asc
```

After identifying each attempt, compare its downstream resource IDs and write
operations to determine whether the retry created, reused, or skipped resources.
