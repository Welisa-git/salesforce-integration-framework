# Integration Framework — Developer Guide

> **Scope**: This guide covers the internal mechanics of the integration framework.
> It is org-agnostic: replace `Compano` / `FIPA` with whatever external system you are integrating.

---

## Table of Contents

1. [Metadata & Configuration](#1-metadata--configuration)
2. [Mapping](#2-mapping)
3. [Timing & Batches](#3-timing--batches)
4. [Ordering (Sync Order)](#4-ordering-sync-order)
5. [Pagination](#5-pagination)
6. [ID Exchange](#6-id-exchange)
7. [Error Logging](#7-error-logging)
8. [Retry](#8-retry)
9. [Single Record Sync](#9-single-record-sync)
10. [Triggers — Event-Based Execution](#10-triggers--event-based-execution)
11. [Sandbox Differentiation & Deployments](#11-sandbox-differentiation--deployments)

---

## 1. Metadata & Configuration

The framework is driven entirely by two **Custom Metadata Types** (CMT). No code changes are needed to add a new integration — only metadata records.

### `Integration_Endpoint__mdt` — Connection config

| Field | Description |
|-------|-------------|
| `Named_Credential__c` | Named Credential that holds the base URL + authentication |
| `Base_Path__c` | Path prefix appended to the Named Credential URL (e.g. `/API/jsonfeed/`) |
| `Pagination_Type__c` | `offset` (REST) or `graphql` |
| `Protocol_Type__c` | `REST` (default) or `GraphQL` |
| `External_ID_Field__c` | Default external ID field name for all mappings on this endpoint |
| `Timeout__c` | HTTP timeout in milliseconds (default: 30000) |
| `Active__c` | Master on/off switch — inactive endpoints are skipped entirely |

One endpoint = one external system. Multiple mappings (resources/objects) share the same endpoint.

### `Integration_Mapping__mdt` — Sync config

| Field | Description |
|-------|-------------|
| `Endpoint__c` | Lookup to `Integration_Endpoint__mdt` |
| `Resource_Path__c` | REST only — appended to `Base_Path__c` (e.g. `feed_SALESFORCE_PRD`) |
| `GraphQL_Query__c` | GraphQL only — full query string with `$first: Int, $after: String` variables |
| `Target_Object__c` | Salesforce object API name (e.g. `Product2`) |
| `Dataweave_Map_Name__c` | Name of the DataWeave script that transforms API records to SObjects |
| `External_Id_Field_Overide__c` | Overrides `External_ID_Field__c` from the endpoint for this mapping only |
| `Sync_Order__c` | Integer — controls the execution order within an endpoint |
| `Page_Size__c` | Records per API call (default: 100) |
| `Execution_Frequency_Type__c` | `Hourly`, `Daily`, `Weekly`, or `Custom Minutes` |
| `Execution_Frequency_Value__c` | Numeric value matching the frequency type (e.g. `2` = every 2 hours) |
| `Active__c` | Inactive mappings are skipped by the scheduler |

### Runtime State — Custom Settings

| Object | Purpose |
|--------|---------|
| `IntegrationExecutionState__c` | Per-mapping: `Last_Run_Date__c`, `Next_Scheduled_Time__c`, `Last_Status__c` |
| `Integration_Pagination_State__c` | Per-mapping: `Last_Run_Date__c` (used by `AbstractPullQueueable.getLastRunTime()`) |

### Cache

`IntegrationMappingCache` wraps all CMT queries with a per-transaction static cache. Records are loaded on first access and reused within the same Apex transaction. The cache uses **lowercase keys** for case-insensitive lookups.

---

## 2. Mapping

Each `Integration_Mapping__mdt` record defines **one sync pipeline**:

```
External API resource  →  DataWeave transform  →  Salesforce object
```

The mapping drives every step:

1. **Which resource to call** — `Resource_Path__c` (REST) or `GraphQL_Query__c`
2. **Which DataWeave script to use** — `Dataweave_Map_Name__c`
3. **Which Salesforce object to write to** — `Target_Object__c`
4. **How to identify existing records** — `External_Id_Field_Overide__c` or endpoint's `External_ID_Field__c`
5. **How often to run** — `Execution_Frequency_Type__c` + `Execution_Frequency_Value__c`
6. **In which order relative to sibling mappings** — `Sync_Order__c`

The DataWeave script receives the raw API JSON as `payload` and must output a JSON array of SObjects matching `Target_Object__c`. It maps external field names to Salesforce API names and sets the external ID field.

```
// DataWeaveScriptResource.<Dataweave_Map_Name__c>
%dw 2.0
output application/json
---
payload.Data map (item) -> {
    Name: item.description,
    ExternalId__c: item.id
}
```

---

## 3. Timing & Batches

### How batches work

Each Queueable execution = one "page" of records from the API.

- One `PullQueueable` call fetches one page (size = `Page_Size__c`)
- If `hasMoreData = true`, a new `PullQueueable` is immediately re-enqueued with the updated `PaginationState`
- This continues until the API signals no more records

Governor limit consideration: each Queueable invocation is an independent transaction (100 callouts, 10,000 DML rows limit).

### Scheduling — recommended setup

The recommended approach is **one** scheduled job for the entire org:

```apex
// One-time setup — schedule master job every 15 minutes
UniversalIntegrationScheduler.scheduleUniversalScheduler('Integration_Master_Scheduler', 15);
```

`UniversalIntegrationScheduler.execute()` runs every N minutes and:
1. Loads all active endpoints from `IntegrationMappingCache`
2. For each active mapping, calls `IntegrationFrequencyCalculator.shouldExecuteNow()`
3. Enqueues `PullQueueable` only for mappings whose interval has elapsed

This means the scheduler interval (e.g. 15 min) is the **check frequency**, not the execution frequency. A mapping configured for `Daily` will only actually run once per day.

### Supported frequency types

| `Execution_Frequency_Type__c` | `Execution_Frequency_Value__c` | Runs every... |
|-------------------------------|-------------------------------|---------------|
| `Hourly` | `2` | 2 hours |
| `Daily` | `1` | 1 day |
| `Weekly` | `1` | 7 days |
| `Custom Minutes` | `30` | 30 minutes |

If a mapping has never run (`Last_Run_Date__c` is null), `shouldExecuteNow()` returns `true` immediately.

### Legacy / alternative scheduling

`IntegrationSchedulable` can schedule a single endpoint directly with a Salesforce cron expression. Use this when you need independent control over a specific endpoint's timing, without the master scheduler.

`ThrottledIntegrationRunner` adds concurrency protection on top of the schedulable: it checks how many `PullQueueable` jobs are currently in-flight and skips the run if the configured maximum is reached, or if a cooldown period has not elapsed.

---

## 4. Ordering (Sync Order)

Within a single endpoint, multiple mappings can exist (e.g. Categories → Products → Prices). `Sync_Order__c` controls the execution sequence.

**How it works:**

1. `UniversalIntegrationScheduler` enqueues only the mapping with the lowest `Sync_Order__c` per endpoint
2. When that mapping's `PullQueueable` finishes (all pages processed), it looks up the next `Sync_Order__c`
3. It enqueues the next mapping via an `@future` method (to avoid queueable-from-queueable governor limits)
4. This continues until all mappings for the endpoint have run

**Example:**

| `Sync_Order__c` | Mapping | Depends on |
|----------------|---------|------------|
| 1 | `Category_Sync` | — |
| 2 | `Product_Sync` | Categories must exist |
| 3 | `Price_Sync` | Products must exist |

The ordering guarantee is **sequential within one endpoint**. Mappings across different endpoints run independently and may overlap.

**Important**: Only the first mapping in the chain is enqueued by the scheduler. The chain is self-propagating via `PullQueueable.processNextObject()`.

---

## 5. Pagination

Pagination is handled by the **Strategy pattern**. The correct strategy is selected by `PaginationStrategyFactory` based on `Integration_Endpoint__mdt.Pagination_Type__c`.

### Offset pagination (REST) — `CompanoOffsetPaginationStrategy`

Used for REST APIs that accept a start record and page size in the URL path.

```
GET callout:NamedCred/base/resource/1/100/    ← page 1 (records 1–100)
GET callout:NamedCred/base/resource/101/100/  ← page 2 (records 101–200)
```

The strategy reads `Count` / `Total` from the response to determine `hasMoreData`. If the count field is absent, it infers more data when `records.size() >= pageSize`.

Response format accepted:
```json
{ "Count": 250, "Data": [ {...}, {...} ] }
```
or a plain array: `[ {...}, {...} ]`

### Cursor pagination (GraphQL) — `GraphQLCursorPaginationStrategy`

Used for GraphQL endpoints with `edges` / `pageInfo` cursor pagination.

```
POST callout:NamedCred/graphql
Body: { "query": "<GraphQL_Query__c>", "variables": { "first": 50, "after": "cursor" } }
```

The strategy reads `pageInfo.hasNextPage` and `pageInfo.endCursor` from the response. The cursor is stored in `PaginationState.customData` and passed as `after` on the next request.

Response format expected:
```json
{
  "data": {
    "<rootField>": {
      "edges": [ { "node": { ... } } ],
      "pageInfo": { "hasNextPage": true, "endCursor": "abc123" }
    }
  }
}
```

### Adding a new pagination strategy

1. Create a class extending `PaginationStrategy`
2. Override `processResponse()`, `modifyEndpointUrl()`, and optionally `getHttpMethod()` / `buildRequestBody()`
3. Register it in `PaginationStrategyFactory.getStrategyTypeForName()` with a key
4. Set that key on `Integration_Endpoint__mdt.Pagination_Type__c`

---

## 6. ID Exchange

The framework uses Salesforce's **External ID upsert** mechanism to match incoming API records to existing Salesforce records.

### Configuration

| Priority | Source | Field |
|----------|--------|-------|
| 1 (highest) | Mapping | `External_Id_Field_Overide__c` |
| 2 (fallback) | Endpoint | `External_ID_Field__c` |

The resolved field name must exist on `Target_Object__c` and be marked as **External ID** (or be the standard `Id` field) in Salesforce schema.

### How it works

1. The DataWeave script maps the external system's identifier to the external ID field on the SObject
2. `AbstractPullQueueable.processRecords()` resolves the field token via `Schema.DescribeSObjectResult`
3. Records where the external ID value is null or blank are **filtered out** before the upsert (logged as a warning)
4. `Database.upsert(records, externalIdFieldToken, false)` is called — `false` means partial success (failures don't roll back successes)
5. A record is **inserted** if no match exists, **updated** if a match is found

### Validation

Before calling upsert, the framework validates:
- The field exists on the target object
- The field is marked as External ID or is an ID lookup

If validation fails, the batch is skipped and an error is logged — no partial upsert occurs.

---

## 7. Error Logging

The framework uses **Nebula Logger** throughout.

### Log levels used

| Level | When |
|-------|------|
| `Logger.debug()` | Pagination details, record counts, URL construction |
| `Logger.info()` | Start/end of each execution, upsert totals, frequency decisions |
| `Logger.warn()` | Skipped records (missing ext. ID), in-flight throttle skips, truncated results |
| `Logger.error()` | HTTP 4xx/5xx, DML failures, configuration errors, DataWeave errors |

### Tags per mapping

Each queueable initializes `loggerTags` from `Integration_Mapping__mdt.Logger_Tags__c` (comma-separated string). Tags are applied to key log entries via `applyTags(Logger.info(...))`, making it easy to filter logs by mapping in Nebula Logger's UI.

```
// Logger_Tags__c on the mapping:
"product-sync, compano, nightly"

// Resulting log entries carry those tags for filtering
```

### Log persistence

`Logger.saveLog()` is called at three points:
- After the DataWeave transformation
- After the upsert results are processed
- When an exception is caught

### Execution state

`IntegrationFrequencyCalculator` writes `Last_Status__c = 'Failed'` to `IntegrationExecutionState__c` on failure, and `Last_Status__c = 'Success'` on completion. This is visible in Setup → Custom Settings and can be used for monitoring.

### DML error details

For each failed upsert, the framework logs:
- The external ID value of the failed record
- The full DML error message
- Up to 5 failed records are logged in detail per batch; remaining failures are counted in a summary warning

---

## 8. Retry

### Current behavior

There is **no automatic retry** in the framework. If `PullQueueable.pullAndProcessRecords()` throws an exception:

1. The error is logged via Nebula Logger
2. `Logger.saveLog()` is called
3. The exception is re-thrown

Salesforce's platform will **not** automatically retry a Queueable that throws an exception — the job fails with status `Failed` in `AsyncApexJob`.

### Salesforce-level retry (callouts)

For HTTP callouts specifically: if a callout times out or returns a 5xx, the framework throws an `IntegrationException`. There is no built-in backoff or retry loop.

### How to handle failures

**Option 1 — Re-run the scheduler**
The next time `UniversalIntegrationScheduler` fires, it will check `IntegrationExecutionState__c`. If the last run failed and the frequency interval has elapsed, it will re-enqueue the mapping automatically.

**Option 2 — Manual re-enqueue**
```apex
System.enqueueJob(new PullQueueable(
    'EndpointDeveloperName',
    'MappingDeveloperName',
    'ManualRetry',
    null,    // lastRunTime = null → will fetch all records
    null,    // paginationState = null → starts from page 1
    1        // syncOrder
));
```

**Option 3 — Add retry to a subclass**
Extend `PullQueueable` and override `pullAndProcessRecords()` to catch, log, and re-enqueue self with a retry counter stored in the `PaginationState.customData` map.

---

## 9. Single Record Sync

The framework is **batch-oriented by design** — each execution fetches a full page from the API. It does not natively support fetching a single record by ID.

### Current workaround — filter post-transform

If the external API supports filtering by ID in the URL path or as a query parameter, you can add a field (e.g. `Record_Id_Filter__c`) to `Integration_Mapping__mdt` and override `modifyEndpointUrl()` in a custom `PaginationStrategy` subclass to append the filter.

### Recommended extension — `SingleRecordPullQueueable`

For a proper single-record flow, create a subclass:

```apex
public class SingleRecordPullQueueable extends PullQueueable {
    private final String externalRecordId;

    public SingleRecordPullQueueable(String endpointName, String mappingName,
                                     String externalRecordId) {
        super(endpointName, mappingName, 'SingleRecord_' + externalRecordId,
              null, null, 1);
        this.externalRecordId = externalRecordId;
    }

    // Override filterAndProcessRecords() to keep only the matching record,
    // or pass the ID to a custom pagination strategy that builds a single-record URL
}
```

This keeps all the existing DataWeave transform, upsert, and logging logic intact.

### Via Platform Event (FIPA trigger)

See [Section 10](#10-triggers--event-based-execution) for the full event-driven approach.

---

## 10. Triggers — Event-Based Execution

The framework currently supports **timer-based** execution only (via the scheduled `UniversalIntegrationScheduler`). This section describes how to extend it to support **event-driven** execution — both for bulk re-syncs and for single-record updates triggered externally (e.g. from FIPA via a Platform Event).

### Architecture overview

```
External system (FIPA)
    │
    │  publishes Platform Event
    ▼
IntegrationSyncRequest__e
    │
    │  Apex Trigger or Flow
    ▼
System.enqueueJob(new PullQueueable(...))
        or
System.enqueueJob(new SingleRecordPullQueueable(...))
```

### Step 1 — Define the Platform Event

Create a Platform Event `Integration_Sync_Request__e` with the following fields:

| Field | Type | Description |
|-------|------|-------------|
| `Mapping_Name__c` | Text | DeveloperName of the `Integration_Mapping__mdt` record |
| `External_Record_Id__c` | Text | External system ID (empty = full batch sync) |
| `Sync_Type__c` | Text | `batch` or `single` |

### Step 2a — Apex Trigger (recommended for reliability)

```apex
trigger IntegrationSyncRequestTrigger on Integration_Sync_Request__e (after insert) {
    for (Integration_Sync_Request__e event : Trigger.new) {
        if (event.Sync_Type__c == 'single' && String.isNotBlank(event.External_Record_Id__c)) {
            System.enqueueJob(new SingleRecordPullQueueable(
                IntegrationMappingCache.getMappingByName(event.Mapping_Name__c)?.Endpoint__r?.DeveloperName,
                event.Mapping_Name__c,
                event.External_Record_Id__c
            ));
        } else {
            // Full batch sync for this mapping
            System.enqueueJob(new PullQueueable(
                IntegrationMappingCache.getMappingByName(event.Mapping_Name__c)?.Endpoint__r?.DeveloperName,
                event.Mapping_Name__c,
                'EventTriggered_' + event.Mapping_Name__c,
                null, null, 1
            ));
        }
    }
}
```

### Step 2b — Flow (no-code alternative)

Use a Record-Triggered Flow on `Integration_Sync_Request__e` (Platform Event trigger) and call an Invocable Apex action:

```apex
public class IntegrationSyncRequestAction {
    @InvocableMethod(label='Enqueue Integration Sync' category='Integration')
    public static void enqueueSync(List<Request> requests) {
        for (Request req : requests) {
            System.enqueueJob(new PullQueueable(
                req.endpointName, req.mappingName,
                'FlowTriggered', null, null, 1
            ));
        }
    }

    public class Request {
        @InvocableVariable(required=true) public String endpointName;
        @InvocableVariable(required=true) public String mappingName;
    }
}
```

### Publishing the event from FIPA

FIPA (or any external system) publishes the event via the Salesforce REST API:

```http
POST /services/data/v60.0/sobjects/Integration_Sync_Request__e
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "Mapping_Name__c": "Product_Sync",
  "External_Record_Id__c": "PROD-12345",
  "Sync_Type__c": "single"
}
```

### Preventing duplicate runs

When event-based and timer-based execution run in parallel, you may process the same data twice. Use `ThrottledIntegrationRunner`'s pattern as a reference: check `AsyncApexJob` for in-flight `PullQueueable` jobs for the same mapping before enqueuing a new one.

---

## 11. Sandbox Differentiation & Deployments

### What is org-agnostic, what is not

| Component | Org-agnostic? | Notes |
|-----------|--------------|-------|
| Apex classes | ✅ Yes | Deploy as-is to all orgs |
| DataWeave scripts | ✅ Yes | Deploy as-is to all orgs |
| `Integration_Mapping__mdt` records | ✅ Yes | Deployable via SFDX or unlocked package |
| `Integration_Endpoint__mdt` records | ⚠️ Partial | `Named_Credential__c` reference differs per org |
| Named Credentials | ❌ No | Must be configured manually per org |
| External Credentials | ❌ No | Must be configured manually per org |
| `IntegrationExecutionState__c` records | ❌ No | Runtime data, not deployed |

### Named Credentials per environment

Named Credentials are the **only org-specific configuration**. The value of `Integration_Endpoint__mdt.Named_Credential__c` must match a Named Credential that exists in the target org.

**Best practice**: use the same Named Credential name across all orgs (e.g. `Compano_API`) but configure the URL + authentication differently per org:
- Production: points to the production API endpoint
- Sandbox / UAT: points to the sandbox or mock API endpoint
- Developer sandbox: can point to a Postman mock or a sandbox API

### Active flag for sandbox control

Use `Active__c` on `Integration_Endpoint__mdt` and `Integration_Mapping__mdt` to disable integrations in specific orgs:
- Deploy `Active__c = false` for heavy batch syncs in developer sandboxes
- Use a sandbox-specific endpoint record pointing to a lightweight test data set

### Deploying metadata records

```bash
# Deploy CMT records (endpoint + mapping definitions)
sf project deploy start \
  --source-dir force-app/main/default/customMetadata \
  -o <orgAlias>

# Deploy Apex classes separately
sf project deploy start \
  --source-dir force-app/main/default/classes/integration \
  -o <orgAlias>
```

Named Credentials and External Credentials must be set up via Setup UI or Auth. Provider configuration — they cannot be deployed with DX.

### Scheduler setup per org

The `UniversalIntegrationScheduler` must be scheduled **once per org** via Anonymous Apex:

```apex
// Run once after deployment:
UniversalIntegrationScheduler.scheduleUniversalScheduler('Integration_Master_Scheduler', 15);
```

This creates a scheduled job. If redeploying, abort the existing scheduled job first:

```apex
// Abort before rescheduling:
for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'Integration_Master_Scheduler']) {
    System.abortJob(ct.Id);
}
UniversalIntegrationScheduler.scheduleUniversalScheduler('Integration_Master_Scheduler', 15);
```
