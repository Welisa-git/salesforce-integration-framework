# Integration Framework

> **Org-agnostic**. Replace any references to `Compano` / `FIPA` with the external system you are integrating against. All configuration is driven by Custom Metadata — no code changes are needed to add a new integration.

---

## Table of Contents

1. [Folder Structure](#1-folder-structure)
2. [Architecture Overview](#2-architecture-overview)
3. [Metadata & Configuration](#3-metadata--configuration)
4. [Mapping](#4-mapping)
5. [Timing & Batches](#5-timing--batches)
6. [Ordering (Sync Order)](#6-ordering-sync-order)
7. [Pagination](#7-pagination)
8. [ID Exchange](#8-id-exchange)
9. [Error Logging](#9-error-logging)
10. [Retry](#10-retry)
11. [Single Record Sync](#11-single-record-sync)
12. [Event-Driven Execution (Triggers & Flows)](#12-event-driven-execution-triggers--flows)
13. [Sandbox Differentiation & Deployments](#13-sandbox-differentiation--deployments)
14. [Quick Start Recipes](#14-quick-start-recipes)

---

## 1. Folder Structure

```
integration/
├── README.md                          ← this file
├── DEVELOPER_GUIDE.md                 ← extended developer reference
│
├── IntegrationSyncRequestAction.cls   ← invocable action for Flow / Platform Events
│
├── core/
│   ├── AbstractIntegrationService.cls ← base service: makeCallout()
│   ├── IntegrationMappingCache.cls    ← per-transaction static cache for CMT
│   ├── IntegrationResult.cls          ← result wrapper (status, message, errors)
│   ├── TypedSyncService.cls           ← generic typed sync service base
│   └── test/
│       ├── AbstractIntegrationServiceTest.cls
│       ├── IntegrationMappingCacheTest.cls
│       └── IntegrationResultTest.cls
│
├── pagination/
│   ├── PaginationStrategy.cls         ← abstract base for pagination strategies
│   ├── PaginationStrategyFactory.cls  ← instantiates + initializes the right strategy
│   ├── PaginationState.cls            ← carries offset + cursor between pages
│   ├── PaginationResult.cls           ← page result (records, hasMoreData, nextState)
│   ├── CompanoOffsetPaginationStrategy.cls  ← REST offset pagination
│   ├── GraphQLCursorPaginationStrategy.cls  ← GraphQL cursor pagination
│   └── test/
│       ├── CompanoOffsetPaginationStrategyTest.cls
│       ├── GraphQLCursorPaginationStrategyTest.cls
│       ├── PaginationResultTest.cls
│       ├── PaginationStateTest.cls
│       ├── PaginationStrategyFactoryTest.cls
│       └── PaginationStrategyTest.cls
│
├── queueable/
│   ├── AbstractPullQueueable.cls      ← base queueable: upsert, logging, state
│   ├── PullQueueable.cls              ← full batch sync (paginated)
│   ├── SingleRecordPullQueueable.cls  ← single-record sync by external ID
│   └── test/
│       ├── AbstractPullQueueableTest.cls
│       ├── PullQueueableTest.cls
│       └── SingleRecordPullQueueableTest.cls
│
├── scheduling/
│   ├── UniversalIntegrationScheduler.cls   ← master scheduler (recommended)
│   ├── IntegrationFrequencyCalculator.cls  ← per-mapping frequency check
│   ├── IntegrationSchedulable.cls          ← legacy: single-endpoint scheduler
│   ├── ThrottledIntegrationRunner.cls      ← concurrency-limited runner
│   └── test/
│       ├── UniversalIntegrationSchedulerTest.cls
│       ├── IntegrationFrequencyCalculatorTest.cls
│       ├── IntegrationSchedulableTest.cls
│       └── ThrottledIntegrationRunnerTest.cls
│
└── test/
    └── IntegrationSyncRequestActionTest.cls
```

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        TRIGGERS / ENTRY POINTS                  │
│                                                                  │
│  UniversalIntegrationScheduler  ←→  Scheduled Job (every N min) │
│  IntegrationSyncRequestAction   ←→  Flow / Platform Event       │
│  Anonymous Apex                 ←→  Manual / one-off            │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
              ┌────────────────────────────────┐
              │         PullQueueable          │  ← full batch sync
              │   or                           │
              │  SingleRecordPullQueueable     │  ← single record by ext ID
              └────────────────┬───────────────┘
                               │ extends
                               ▼
              ┌────────────────────────────────┐
              │      AbstractPullQueueable     │
              │  • HTTP callout                │
              │  • DataWeave transform         │
              │  • External ID upsert          │
              │  • Nebula Logger (with tags)   │
              │  • Execution state persistence │
              └────────────────┬───────────────┘
                               │ uses
              ┌────────────────▼───────────────┐
              │       PaginationStrategy       │
              │  CompanoOffsetPagination  (REST)│
              │  GraphQLCursorPagination (GQL) │
              └────────────────┬───────────────┘
                               │ driven by
              ┌────────────────▼───────────────┐
              │  Integration_Endpoint__mdt     │
              │  Integration_Mapping__mdt      │  ← all config lives here
              └────────────────────────────────┘
```

**Flow for one execution cycle:**

1. Scheduler fires → checks `IntegrationFrequencyCalculator.shouldExecuteNow()` per mapping
2. Enqueues `PullQueueable` for due mappings (lowest `Sync_Order__c` first)
3. `PullQueueable` asks the strategy for HTTP method + URL + request body
4. Calls external API via `AbstractIntegrationService.makeCallout()`
5. Transforms the response JSON via DataWeave to `List<SObject>`
6. Upserts records using the configured external ID field
7. If more pages exist: re-enqueues self with updated `PaginationState`
8. When all pages done: chains to the next `Sync_Order__c` mapping via `@future`
9. Saves `Last_Run_Date__c` and `Last_Status__c` to `IntegrationExecutionState__c`

---

## 3. Metadata & Configuration

The framework is driven entirely by two **Custom Metadata Types**. No code changes are needed to add a new integration.

### `Integration_Endpoint__mdt` — Connection config

| Field | Description |
|-------|-------------|
| `Named_Credential__c` | Named Credential that holds the base URL + authentication |
| `Base_Path__c` | Path prefix appended to the Named Credential URL (e.g. `/api/v1/`) |
| `Pagination_Type__c` | `offset` (REST) or `graphql` |
| `Protocol_Type__c` | `REST` (default) or `GraphQL` |
| `External_ID_Field__c` | Default external ID field name for all mappings on this endpoint |
| `Timeout__c` | HTTP timeout in milliseconds (default: 30000) |
| `Active__c` | Master on/off switch — inactive endpoints are skipped entirely |

One endpoint = one external system. Multiple mappings share one endpoint record.

### `Integration_Mapping__mdt` — Sync config

| Field | Description |
|-------|-------------|
| `Endpoint__c` | Lookup to `Integration_Endpoint__mdt` |
| `Resource_Path__c` | REST only — appended to `Base_Path__c` (e.g. `products`) |
| `GraphQL_Query__c` | GraphQL only — full query string with `$first: Int, $after: String` variables |
| `Target_Object__c` | Salesforce object API name (e.g. `Product2`) |
| `Dataweave_Map_Name__c` | Name of the DataWeave script that transforms API records to SObjects |
| `External_Id_Field_Overide__c` | Overrides `External_ID_Field__c` from the endpoint for this mapping only |
| `Sync_Order__c` | Integer — controls execution order within an endpoint |
| `Page_Size__c` | Records per API call (default: 100) |
| `Execution_Frequency_Type__c` | `Hourly`, `Daily`, `Weekly`, or `Custom Minutes` |
| `Execution_Frequency_Value__c` | Numeric value matching the frequency type (e.g. `2` = every 2 hours) |
| `Active__c` | Inactive mappings are skipped by the scheduler |

### Runtime State — Custom Settings (auto-created)

| Object | Purpose |
|--------|---------|
| `IntegrationExecutionState__c` | Per-mapping: `Last_Run_Date__c`, `Next_Scheduled_Time__c`, `Last_Status__c` |
| `Integration_Pagination_State__c` | Per-mapping: `Last_Run_Date__c` (used by `AbstractPullQueueable.getLastRunTime()`) |

Both are **Hierarchy Custom Settings** and are created automatically on the first successful execution — you do not need to create them manually.

### Cache

`IntegrationMappingCache` wraps all CMT queries with a per-transaction static cache. Records are loaded on first access and reused within the same Apex transaction. The cache uses **lowercase keys** for case-insensitive lookups. `getAllActiveEndpoints()` has a `LIMIT 500` guard and logs a warning if the result is truncated.

---

## 4. Mapping

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

```javascript
// DataWeaveScriptResource.<Dataweave_Map_Name__c>
%dw 2.0
output application/json
---
payload.Data map (item) -> {
    Name: item.description,
    ExternalId__c: item.id
}
```

### Configuring a REST endpoint

**Integration_Endpoint__mdt:**
| Field | Value |
|-------|-------|
| `Named_Credential__c` | Named Credential name |
| `Base_Path__c` | API base path (e.g. `/api/v1/`) |
| `Pagination_Type__c` | `offset` |
| `Protocol_Type__c` | `REST` (or blank) |
| `Timeout__c` | ms (e.g. `30000`) |

**Integration_Mapping__mdt:**
| Field | Value |
|-------|-------|
| `Endpoint__c` | Reference to Integration_Endpoint |
| `Resource_Path__c` | Resource path (e.g. `products`) |
| `Target_Object__c` | Salesforce object (e.g. `Product2`) |
| `Dataweave_Map_Name__c` | DataWeave script name |
| `Page_Size__c` | Records per page (e.g. `100`) |

### Configuring a GraphQL endpoint

**Integration_Endpoint__mdt:**
| Field | Value |
|-------|-------|
| `Named_Credential__c` | Named Credential name |
| `Base_Path__c` | GraphQL endpoint path (e.g. `/graphql`) |
| `Pagination_Type__c` | `graphql` |
| `Protocol_Type__c` | `GraphQL` |
| `Timeout__c` | ms (e.g. `30000`) |

**Integration_Mapping__mdt:**
| Field | Value |
|-------|-------|
| `Endpoint__c` | Reference to Integration_Endpoint |
| `GraphQL_Query__c` | Full GraphQL query with `$first: Int, $after: String` variables |
| `Target_Object__c` | Salesforce object (e.g. `Product2`) |
| `Dataweave_Map_Name__c` | DataWeave script name |
| `Page_Size__c` | Records per page (e.g. `50`) |

**Example `GraphQL_Query__c` value:**
```graphql
query GetProducts($first: Int, $after: String) {
  products(first: $first, after: $after) {
    edges { node { id name } }
    pageInfo { hasNextPage endCursor }
  }
}
```

**Expected response structure:**
```json
{
  "data": {
    "products": {
      "edges": [{ "node": { "id": "1", "name": "Product A" } }],
      "pageInfo": { "hasNextPage": true, "endCursor": "abc123" }
    }
  }
}
```

---

## 5. Timing & Batches

### How batches work

Each Queueable execution = one "page" of records from the API.

- One `PullQueueable` call fetches one page (size = `Page_Size__c`)
- If `hasMoreData = true`, a new `PullQueueable` is immediately re-enqueued with the updated `PaginationState`
- This continues until the API signals no more records

Governor limit consideration: each Queueable invocation is an independent transaction (100 callouts, 10,000 DML rows limit per transaction).

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

The scheduler interval (e.g. 15 min) is the **check frequency**, not the execution frequency. A mapping configured for `Daily` will only actually run once per day.

### Supported frequency types

| `Execution_Frequency_Type__c` | `Execution_Frequency_Value__c` | Runs every... |
|-------------------------------|-------------------------------|---------------|
| `Hourly` | `2` | 2 hours |
| `Daily` | `1` | 1 day |
| `Weekly` | `1` | 7 days |
| `Custom Minutes` | `30` | 30 minutes |

If a mapping has never run (`Last_Run_Date__c` is null), `shouldExecuteNow()` returns `true` immediately — the first run always executes.

### `IntegrationExecutionState__c` — auto-creation

This Custom Setting record is **not** created when the scheduler is set up. It is created automatically by `AbstractPullQueueable.saveLastRunTime()` on the **first successful** execution of a mapping.

Until it exists, `Last_Run_Date__c = null`, which means `shouldExecuteNow()` always returns `true` (see [Section 10 — Retry](#10-retry)).

### Legacy / alternative scheduling

`IntegrationSchedulable` can schedule a single endpoint directly with a Salesforce cron expression. Use this when you need independent control over a specific endpoint's timing, without the master scheduler.

`ThrottledIntegrationRunner` adds concurrency protection: it checks how many `PullQueueable` jobs are currently in-flight and skips the run if the configured maximum is reached, or if a cooldown period has not elapsed.

---

## 6. Ordering (Sync Order)

Within a single endpoint, multiple mappings can exist (e.g. Categories → Products → Prices). `Sync_Order__c` controls the execution sequence.

**How it works:**

1. `UniversalIntegrationScheduler` enqueues only the mapping with the **lowest** `Sync_Order__c` per endpoint
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

## 7. Pagination

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

### PaginationState safety

`PaginationState.fromJson()` is null-safe and type-safe:
- Blank / null input returns a default state (offset=0, pageSize=100)
- Non-object JSON (array, primitive) is rejected with a warning and a default state returned
- Malformed JSON is caught and logged; default state returned

### Adding a custom pagination strategy

1. Create a class extending `PaginationStrategy`
2. Override `processResponse()` and `modifyEndpointUrl()`
3. For non-GET protocols: also override `getHttpMethod()` and `buildRequestBody()`
4. Register in `PaginationStrategyFactory.registerBuiltInStrategies()`:
   ```apex
   strategyTypes.put('myapi', MyApiPaginationStrategy.class);
   ```
5. Set that key on `Integration_Endpoint__mdt.Pagination_Type__c`

---

## 8. ID Exchange

The framework uses Salesforce's **External ID upsert** mechanism to match incoming API records to existing Salesforce records.

### Configuration

| Priority | Source | Field |
|----------|--------|-------|
| 1 (highest) | Mapping | `External_Id_Field_Overide__c` |
| 2 (fallback) | Endpoint | `External_ID_Field__c` |

The resolved field name must exist on `Target_Object__c` and be marked as **External ID** in Salesforce schema.

### How it works

1. The DataWeave script maps the external system's identifier to the external ID field on the SObject
2. `AbstractPullQueueable.processRecords()` resolves the field token via `Schema.DescribeSObjectResult`
3. Records where the external ID value is null or blank are **filtered out** before the upsert (logged as a warning)
4. `Database.upsert(records, externalIdFieldToken, false)` is called — `false` = partial success
5. A record is **inserted** if no match exists, **updated** if a match is found

### Validation

Before calling upsert, the framework validates that the field exists and is marked as External ID. If validation fails, the batch is skipped and an error is logged — no partial upsert occurs.

---

## 9. Error Logging

The framework uses **Nebula Logger** throughout.

### Log levels used

| Level | When |
|-------|------|
| `Logger.debug()` | Pagination details, record counts, URL construction |
| `Logger.info()` | Start/end of each execution, upsert totals, frequency decisions |
| `Logger.warn()` | Skipped records (missing ext. ID), throttle skips, truncated results |
| `Logger.error()` | HTTP 4xx/5xx, DML failures, configuration errors, DataWeave errors |

### Tags per mapping

Each queueable initializes `loggerTags` from `Integration_Mapping__mdt.Logger_Tags__c` (comma-separated string). Tags are applied to key log entries via `applyTags(LogEntryEventBuilder)`, making it easy to filter logs by mapping in Nebula Logger's UI.

```
// Logger_Tags__c on the mapping:  "product-sync, compano, nightly"
// → log entries for this mapping carry those tags for filtering
```

### Log persistence

`Logger.saveLog()` is called at three points:
- After the DataWeave transformation
- After the upsert results are processed
- When an exception is caught

### DML error details

For each failed upsert, the framework logs:
- The external ID value of the failed record
- The full DML error message
- Up to 5 failed records are logged in detail per batch; remaining failures are counted in a summary warning

### Execution state

`IntegrationFrequencyCalculator` writes `Last_Status__c = 'Failed'` to `IntegrationExecutionState__c` on failure, and `Last_Status__c = 'Success'` on completion. Visible in Setup → Custom Settings.

---

## 10. Retry

### Current behavior

There is **no automatic retry** within a single execution. If `PullQueueable.pullAndProcessRecords()` throws an exception:

1. The error is logged via Nebula Logger
2. `Logger.saveLog()` is called
3. The exception is re-thrown
4. `Last_Run_Date__c` is **not updated** (only set on success)

Salesforce's platform will **not** automatically retry a Queueable that throws — the job gets status `Failed` in `AsyncApexJob`.

### Automatic retry via scheduler

Because `saveLastRunTime()` only writes on success, a failed mapping will have an **unchanged** `Last_Run_Date__c`. The next time `UniversalIntegrationScheduler` fires, `shouldExecuteNow()` sees that the interval has elapsed and re-enqueues the mapping automatically.

**In practice**: a mapping that fails will be retried on the next scheduler tick (e.g. 15 minutes later). If it has never succeeded, `Last_Run_Date__c = null` and it retries every single tick.

### Manual re-enqueue

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

---

## 11. Single Record Sync

`SingleRecordPullQueueable` extends `AbstractPullQueueable` directly, bypassing the pagination strategy entirely. It fetches a single record from the external API by external ID, transforms it with the same DataWeave script, and upserts it into Salesforce.

### How it works

1. Takes `endpointName`, `mappingName`, and `externalRecordId` as constructor arguments
2. Builds a URL: `Base_Path__c + Resource_Path__c + externalRecordId + /`
3. Makes a GET callout to that URL
4. Normalises the response to a JSON array (handles both `{}` and `[{...}]` response shapes)
5. Passes the array through the mapping's DataWeave script
6. Upserts the resulting record(s) using the configured external ID field
7. Logs completion via Nebula Logger (with mapping tags)

### Enqueue directly

```apex
System.enqueueJob(new SingleRecordPullQueueable(
    'EndpointDeveloperName',   // Integration_Endpoint__mdt.DeveloperName
    'MappingDeveloperName',    // Integration_Mapping__mdt.DeveloperName
    'PROD-12345'               // external system record ID
));
```

### Via `IntegrationSyncRequestAction` (Flow / Platform Event)

Set `External Record ID` in the invocable action — see [Section 12](#12-event-driven-execution-triggers--flows).

---

## 12. Event-Driven Execution (Triggers & Flows)

The framework supports **event-driven** execution in addition to the scheduled approach. This is primarily useful when an external system needs to trigger a sync in near-real-time (e.g. via FIPA).

### `IntegrationSyncRequestAction` — invocable Apex action

`IntegrationSyncRequestAction` is a `@InvocableMethod` that can be called from any Salesforce Flow, Process Builder, or Platform Event trigger.

**Inputs:**

| Variable | Required | Description |
|----------|----------|-------------|
| `Mapping Name` | Yes | `DeveloperName` of the `Integration_Mapping__mdt` record |
| `External Record ID` | No | External system ID — leave blank for full batch sync |
| `Operation Name` | No | Label for the job in logs (defaults to `FlowTriggered_<MappingName>`) |

**Outputs:**

| Variable | Description |
|----------|-------------|
| `Success` | `true` if the queueable was enqueued successfully |
| `Error Message` | Description of what went wrong (only set when `Success = false`) |

**Behavior:**
- If `External Record ID` is blank → enqueues `PullQueueable` (full batch sync)
- If `External Record ID` is set → enqueues `SingleRecordPullQueueable`
- Each request in a bulk invocation is processed independently (one result per request)

### Recommended Flow architecture

```
Platform Event: Integration_Sync_Request__e
    │  (published by external system / FIPA)
    ▼
Record-Triggered Flow (on Platform Event)
    │
    ▼
Action: "Trigger Integration Sync"  (IntegrationSyncRequestAction)
    Mapping Name      = {!$Record.Mapping_Name__c}
    External Record ID = {!$Record.External_Record_Id__c}
```

### Platform Event fields (suggested)

Create a Platform Event `Integration_Sync_Request__e` with:

| Field | Type | Description |
|-------|------|-------------|
| `Mapping_Name__c` | Text | `DeveloperName` of the `Integration_Mapping__mdt` record |
| `External_Record_Id__c` | Text | External system ID — empty = full batch sync |
| `Sync_Type__c` | Text | Optional: `batch` or `single` for documentation purposes |

### Publishing the event from an external system

```http
POST /services/data/v60.0/sobjects/Integration_Sync_Request__e
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "Mapping_Name__c": "Product_Sync",
  "External_Record_Id__c": "PROD-12345"
}
```

### Apex trigger (alternative — recommended for reliability)

If you need guaranteed processing or want to avoid Flow governor limits, use an Apex trigger on the Platform Event:

```apex
trigger IntegrationSyncRequestTrigger on Integration_Sync_Request__e (after insert) {
    for (Integration_Sync_Request__e event : Trigger.new) {
        Integration_Mapping__mdt mapping =
            IntegrationMappingCache.getMappingByName(event.Mapping_Name__c);
        String endpointName = mapping?.Endpoint__r?.DeveloperName;
        if (String.isBlank(endpointName)) continue;

        if (String.isNotBlank(event.External_Record_Id__c)) {
            System.enqueueJob(new SingleRecordPullQueueable(
                endpointName, event.Mapping_Name__c, event.External_Record_Id__c
            ));
        } else {
            System.enqueueJob(new PullQueueable(
                endpointName, event.Mapping_Name__c,
                'EventTriggered_' + event.Mapping_Name__c, null, null, 1
            ));
        }
    }
}
```

### Preventing duplicate runs

When event-based and timer-based execution run in parallel, you may process the same data twice. Use `ThrottledIntegrationRunner`'s in-flight check as a reference: query `AsyncApexJob` for running `PullQueueable` jobs for the same mapping before enqueuing a new one.

---

## 13. Sandbox Differentiation & Deployments

### What is org-agnostic, what is not

| Component | Org-agnostic? | Notes |
|-----------|--------------|-------|
| Apex classes | Yes | Deploy as-is to all orgs |
| DataWeave scripts | Yes | Deploy as-is to all orgs |
| `Integration_Mapping__mdt` records | Yes | Deployable via SFDX or unlocked package |
| `Integration_Endpoint__mdt` records | Partial | `Named_Credential__c` reference must match the target org |
| Named Credentials | No | Must be configured manually per org |
| External Credentials | No | Must be configured manually per org |
| `IntegrationExecutionState__c` records | No | Runtime data, not deployed |

### Named Credentials per environment

**Best practice**: use the same Named Credential name across all orgs (e.g. `ExternalSystem_API`) but configure the URL + authentication differently per org:
- Production: points to the production API endpoint
- Sandbox / UAT: points to the sandbox or mock API endpoint
- Developer sandbox: can point to a Postman mock or a sandbox API

### Active flag for sandbox control

Use `Active__c` on `Integration_Endpoint__mdt` and `Integration_Mapping__mdt` to disable integrations in specific orgs:
- Deploy `Active__c = false` for heavy batch syncs in developer sandboxes
- Use a sandbox-specific endpoint record pointing to a lightweight test data set

### Deployment commands

```bash
# Deploy Apex classes
sf project deploy start \
  --source-dir force-app/main/default/classes/integration \
  -o <orgAlias>

# Deploy CMT records (endpoint + mapping definitions)
sf project deploy start \
  --source-dir force-app/main/default/customMetadata \
  -o <orgAlias>
```

Named Credentials and External Credentials must be set up via the Setup UI — they cannot be deployed with DX.

### Scheduler setup per org

The `UniversalIntegrationScheduler` must be scheduled **once per org** via Anonymous Apex after deployment:

```apex
// Run once after deployment:
UniversalIntegrationScheduler.scheduleUniversalScheduler('Integration_Master_Scheduler', 15);
```

If redeploying, abort the existing scheduled job first:

```apex
for (CronTrigger ct : [SELECT Id FROM CronTrigger
    WHERE CronJobDetail.Name = 'Integration_Master_Scheduler']) {
    System.abortJob(ct.Id);
}
UniversalIntegrationScheduler.scheduleUniversalScheduler('Integration_Master_Scheduler', 15);
```

---

## 14. Quick Start Recipes

### Schedule the master scheduler

```apex
UniversalIntegrationScheduler.scheduleUniversalScheduler('Integration_Master_Scheduler', 15);
```

### Manually trigger a full batch sync

```apex
System.enqueueJob(new PullQueueable(
    'My_Endpoint',     // Integration_Endpoint__mdt.DeveloperName
    'My_Mapping',      // Integration_Mapping__mdt.DeveloperName
    'ManualSync',      // operation label for logs
    null,              // lastRunTime (null = fetch everything)
    null,              // paginationState (null = start from page 1)
    1                  // syncOrder
));
```

### Trigger a single-record sync

```apex
System.enqueueJob(new SingleRecordPullQueueable(
    'My_Endpoint',
    'My_Mapping',
    'PROD-12345'       // external system ID of the record
));
```

### Call the invocable action from Anonymous Apex (for testing)

```apex
IntegrationSyncRequestAction.Request req = new IntegrationSyncRequestAction.Request();
req.mappingName      = 'My_Mapping';
req.externalRecordId = 'PROD-12345'; // leave null/blank for batch sync

List<IntegrationSyncRequestAction.Result> results =
    IntegrationSyncRequestAction.triggerSync(
        new List<IntegrationSyncRequestAction.Request>{ req });

System.debug(results[0].isSuccess);
System.debug(results[0].errorMessage);
```

### Verify last run status

```apex
IntegrationExecutionState__c state =
    IntegrationExecutionState__c.getInstance('My_Mapping');
System.debug(state?.Last_Run_Date__c);
System.debug(state?.Last_Status__c);
```

---

## Related

- **Logging**: Nebula Logger — all framework classes log via `Logger.info/warn/error/debug`. Log entries for a mapping carry the tags from `Integration_Mapping__mdt.Logger_Tags__c` for easy filtering.
- **Auth**: Named Credentials + External Credentials — protocol-agnostic, works for both REST and GraphQL.
- **DataWeave**: scripts must be in `force-app/main/default/staticresources/` (or as DataWeave resources) and referenced by the `Dataweave_Map_Name__c` field on the mapping.
- **Full developer reference**: see [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md).
