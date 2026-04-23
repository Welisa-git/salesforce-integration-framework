# Salesforce Integration Framework

An org-agnostic, configuration-driven Salesforce integration framework for building scalable multi-API integrations. This framework handles pagination, state tracking, logging, and queueable execution.

## Features

- **🔧 Configuration-Driven**: All behavior configured via Custom Metadata Type records — no code changes to add a new integration
- **📊 Smart Pagination**: Built-in REST (offset) and GraphQL (cursor) pagination strategies
- **🔗 Multi-Protocol**: REST (GET) and GraphQL (POST) supported via the same pipeline
- **⏱️ State Tracking**: Per-mapping execution state via Custom Settings (auto-created on first successful run)
- **📝 Logging**: Nebula Logger with per-mapping tag support (`Logger_Tags__c`) applied to all key log entries
- **🚀 Queueable Execution**: Async batch sync + single-record sync (`SingleRecordPullQueueable`)
- **🎯 Event-Driven**: Invocable action (`IntegrationSyncRequestAction`) for Flow and Platform Event triggered syncs
- **🔁 Auto-Retry**: Failed mappings are automatically re-run on the next scheduler tick (no manual intervention needed)
- **🧪 Fully Tested**: >75% code coverage with comprehensive test suite
- **🔄 Org-Agnostic**: Zero hardcoded business logic or org-specific references

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        ENTRY POINTS                              │
│                                                                  │
│  UniversalIntegrationScheduler  ←  Scheduled job (every N min)  │
│  IntegrationSyncRequestAction   ←  Flow / Platform Event        │
│  Anonymous Apex                 ←  Manual / one-off             │
└────────────────────────┬─────────────────────────────────────────┘
                         │
           ┌─────────────┴──────────────────┐
           │                                │
┌──────────▼──────────┐          ┌──────────▼──────────────────┐
│  PullQueueable      │          │  SingleRecordPullQueueable  │
│  (full batch sync,  │          │  (single record by ext ID,  │
│   paginated)        │          │   bypasses pagination)      │
└──────────┬──────────┘          └──────────┬──────────────────┘
           │                                │
           └──────────────┬─────────────────┘
                          │ extends
┌─────────────────────────▼────────────────────────────────────────┐
│ AbstractPullQueueable (Base Logic)                               │
│ • HTTP call via named credential                                 │
│ • DataWeave transform + External ID upsert                       │
│ • Per-mapping state persistence (Integration_Pagination_State__c)│
│ • Nebula Logger with per-mapping tags                            │
│ • TypedSyncService delegation (optional)                         │
└──────────────────────────────────────────────────────────────────┘
```

## Getting Started

### Prerequisites

- Salesforce org with API version 60.0+
- Salesforce DX CLI (`sf`) installed
- Nebula Logger package installed (optional, but recommended)

### Installation

1. **Clone this repo**
   ```bash
   git clone <repo-url>
   cd salesforce-integration-framework
   ```

2. **Deploy to your org**
   ```bash
   sf project deploy start -d --force-overwrite
   ```

3. **Set up Custom Metadata**
   - Create `Integration_Endpoint__mdt` records (see below)
   - Create `Integration_Mapping__mdt` records (see below)

4. **Implement your first integration**
   - Follow the [Setup Guide](#setup-guide) below

## Setup Guide

### Step 1: Create a Pagination Strategy (if needed)

If your API has different pagination behavior from the built-in strategies (`offset`, `graphql`), create a class extending `PaginationStrategy`:

```apex
/**
 * Custom pagination for [Your API]
 * @Author: R. Groot Date: [Date]
 */
public class MyApiPaginationStrategy extends PaginationStrategy {
    public override PaginationResult processResponse(HttpResponse response, PaginationState state) {
        // Extract records and determine if more pages exist
        // Return PaginationResult.createSuccess(records, nextState, hasMore)
    }

    public override String modifyEndpointUrl(String baseUrl, PaginationState state) {
        return baseUrl + '?page=' + state.getOffset();
    }
}
```

For non-GET protocols (e.g. custom POST-based APIs), also override:
```apex
public override String getHttpMethod() { return 'POST'; }
public override String buildRequestBody(PaginationState state) { return '{"page": ' + state.getOffset() + '}'; }
```

**Then register in `PaginationStrategyFactory.registerBuiltInStrategies()`**:
```apex
strategyTypes.put('myapi', MyApiPaginationStrategy.class);
```

**Or specify the full class name in metadata** (no registration needed):
```
Pagination_Config__c = "MyApiPaginationStrategy"
```

### Step 2: Create Named Credential

In your Salesforce org:

1. Go to **Setup > Named Credentials**
2. Create a new credential with:
   - **Label**: e.g., `My API`
   - **Name**: e.g., `My_API` (this value goes in `Named_Credential__c`)
   - **URL**: base URL of the API (e.g., `https://api.example.com`)
   - **Authentication Protocol**: OAuth 2.0, Custom, or as required

Alternative: Use **External Credentials** (Salesforce native):
1. Go to **Setup > External Credentials**
2. Create credential and principal
3. Reference the Named Credential name in `Integration_Endpoint__mdt`

### Step 3: Create Integration_Endpoint__mdt Record

Go to **Setup > Custom Metadata Types > Integration Endpoint > Manage Records > New**

| Field | Type | Example | Required |
|-------|------|---------|----------|
| Label | Text | `My API` | ✅ |
| `Named_Credential__c` | Text | `My_API` | ✅ |
| `Base_Path__c` | Text | `/api/v1/` (REST) or `/graphql` (GraphQL) | ✅ |
| `External_ID_Field__c` | Text | `External_Id__c` | ✅ |
| `Active__c` | Checkbox | `true` | ✅ |
| `Protocol_Type__c` | Picklist | `REST` or `GraphQL` | ❌ (defaults to REST) |
| `Pagination_Type__c` | Text | `offset` or `graphql` | ❌ |
| `Pagination_Config__c` | Text | `MyApiPaginationStrategy` | ❌ |
| `Timeout__c` | Number | `30000` (ms) | ❌ |
| `Enable_Nebula_Logger__c` | Checkbox | `true` | ❌ |

> `Pagination_Type__c` and `Pagination_Config__c` are mutually exclusive. `Pagination_Config__c` takes precedence.

### Step 4: Create Integration_Mapping__mdt Records

Go to **Setup > Custom Metadata Types > Integration Mapping > Manage Records > New**

| Field | Type | Example | Required |
|-------|------|---------|----------|
| Label | Text | `My API Products` | ✅ |
| `Endpoint__c` | Lookup | `My_API` | ✅ |
| `Target_Object__c` | Text | `Product2` | ✅ |
| `Source_Object__c` | Text | `products` | ✅ |
| `Operation_Type__c` | Picklist | `Pull` | ✅ |
| `Dataweave_Map_Name__c` | Text | `MyApiProductMap` | ✅ |
| `Active__c` | Checkbox | `true` | ✅ |
| `Resource_Path__c` | Text | `products` (REST only) | ❌ |
| `GraphQL_Query__c` | Long Text | Full query string (GraphQL only) | ❌ |
| `Page_Size__c` | Number | `100` | ❌ |
| `Sync_Order__c` | Number | `1` | ❌ |
| `External_Id_Field_Overide__c` | Text | `My_External_Id__c` | ❌ |
| `Execution_Frequency_Type__c` | Text | `Hourly`, `Daily`, `Weekly`, `Custom Minutes` | ❌ |
| `Execution_Frequency_Value__c` | Number | `1` | ❌ |
| `Logger_Tags__c` | Text | `products,sync` | ❌ |

> `Sync_Order__c` controls execution order when multiple mappings share one endpoint. Required when chaining multiple mappings.

### Step 5: Implement Your Sync Service (Optional)

If you need custom processing logic before or after upsert, create a `TypedSyncService` implementation:

```apex
/**
 * Custom processing logic for Product2 records
 * @Author: R. Groot Date: [Date]
 */
public class Product2SyncService extends TypedSyncService {
    public override List<SObject> processSObjects(List<SObject> sObjects) {
        // Add custom validation or transformation before upsert
        return sObjects;
    }

    public override void postProcessUpsert(List<SObject> successfulUpserts, Map<Id, SObject> originalRecordsMap) {
        // Optional: logic to run after records are upserted
    }
}
```

Service is auto-discovered by naming convention: `[TargetObject]SyncService.cls`
- `Target_Object__c = Product2` → looks for `Product2SyncService`
- `Target_Object__c = PIM_Product__c` → looks for `PIM_Product__cSyncService` or `PIM_ProductSyncService`

### Step 6: Schedule the Integration

**Option A: Universal Scheduler (recommended)**

One scheduled job handles all active mappings. Each mapping controls its own frequency via `Execution_Frequency_Type__c` + `Execution_Frequency_Value__c`.

```apex
// One-time setup in Execute Anonymous — runs every 5 minutes:
UniversalIntegrationScheduler.scheduleUniversalScheduler('Integration_Master_Scheduler', 5);
```

Supported frequency types on `Integration_Mapping__mdt`:
| `Execution_Frequency_Type__c` | `Execution_Frequency_Value__c` | Meaning |
|---|---|---|
| `Hourly` | `2` | Every 2 hours |
| `Daily` | `1` | Once per day |
| `Weekly` | `1` | Once per week |
| `Custom Minutes` | `30` | Every 30 minutes |

> Tip: Set the scheduler interval equal to your shortest mapping frequency (e.g., if a mapping runs every 5 minutes, schedule the runner every 5 minutes).

Per-mapping execution state is tracked in `IntegrationExecutionState__c` (Hierarchy Custom Setting):
- `Last_Run_Date__c` — last successful run timestamp
- `Next_Scheduled_Time__c` — when the next run is expected
- `Last_Status__c` — `Success`, `Failed`, or `Skipped`

**Option B: Legacy single-endpoint scheduler**
```apex
String cronExpression = '0 0 2 * * ?'; // Daily at 02:00
System.schedule('My API Sync', cronExpression, new IntegrationSchedulable('My_API'));
```

### Step 7: Run the Integration Manually

**Full batch sync:**
```apex
Integration_Mapping__mdt m = IntegrationMappingCache.getMappingByName('My_API_Products');
System.enqueueJob(new PullQueueable(
    m.Endpoint__r.DeveloperName,  // endpointName
    m.DeveloperName,               // mappingName
    'ManualSync',                  // operationName (label for logs)
    null,                          // lastRunTime (null = full sync)
    null,                          // paginationState (null = first page)
    1                              // syncOrder
));
```

**Single record sync** — fetches one record by external ID:
```apex
System.enqueueJob(new SingleRecordPullQueueable(
    'My_Endpoint',    // Integration_Endpoint__mdt.DeveloperName
    'My_Mapping',     // Integration_Mapping__mdt.DeveloperName
    'PROD-12345'      // external system ID of the record
));
```

## Configuration Reference

### Custom Metadata Objects

#### Integration_Endpoint__mdt

Represents a single API endpoint.

**Key Fields:**
- `Named_Credential__c` (Text) — Named Credential name (used as `callout:<name>`)
- `Base_Path__c` (Text) — Base API path (e.g. `/api/v1/`) or GraphQL endpoint path (e.g. `/graphql`)
- `Protocol_Type__c` (Picklist) — `REST` (default) or `GraphQL`
- `Pagination_Type__c` (Text) — Built-in strategy key: `offset` (REST) or `graphql` (GraphQL)
- `Pagination_Config__c` (Text) — Full Apex class name of a custom `PaginationStrategy` (overrides `Pagination_Type__c`)
- `External_ID_Field__c` (Text) — External ID field for upsert (e.g. `External_Id__c`)
- `Timeout__c` (Number) — HTTP timeout in milliseconds (default: 30000)
- `Active__c` (Checkbox) — Enable/disable the endpoint
- `Enable_Nebula_Logger__c` (Checkbox) — Enable per-integration Nebula Logger tags

#### Integration_Mapping__mdt

Maps an external API resource to a Salesforce object.

**Key Fields:**
- `Endpoint__c` (Metadata Lookup) — Reference to `Integration_Endpoint__mdt`
- `Target_Object__c` (Text) — Salesforce SObject API name (e.g. `Product2`)
- `Source_Object__c` (Text) — External resource name
- `Operation_Type__c` (Picklist) — `Pull` (reading from external system)
- `Dataweave_Map_Name__c` (Text) — DataWeave Static Resource name for transformation
- `Resource_Path__c` (Text) — REST: path appended to `Base_Path__c` (e.g. `products`)
- `GraphQL_Query__c` (Long Text) — GraphQL only: full query with `$first: Int, $after: String` variables
- `External_Id_Field_Overide__c` (Text) — Overrides endpoint's `External_ID_Field__c` for this mapping
- `Page_Size__c` (Number) — Records per page (default: 100)
- `Sync_Order__c` (Number) — Execution order when multiple mappings share one endpoint
- `Execution_Frequency_Type__c` (Text) — `Hourly`, `Daily`, `Weekly`, or `Custom Minutes`
- `Execution_Frequency_Value__c` (Number) — Frequency value (e.g. `2` = every 2 hours when type is `Hourly`)
- `Active__c` (Checkbox) — Enable/disable this mapping
- `Logger_Tags__c` (Text) — Comma-separated Nebula Logger tags (e.g. `products,sync,myapi`)

### Custom Settings

#### Integration_Pagination_State__c (List Custom Setting)

Persists the last successful run time per mapping. **Auto-managed** by `AbstractPullQueueable`.

**Fields:**
- `Last_Run_Date__c` — Timestamp of last successful execution

**Key:** `DeveloperName` of the mapping (e.g. `My_API_Products`)

#### IntegrationExecutionState__c (Hierarchy Custom Setting)

Tracks scheduling state per mapping. **Auto-managed** by `UniversalIntegrationScheduler`.

**Fields:**
- `Last_Run_Date__c` — Last successful execution
- `Next_Scheduled_Time__c` — Calculated next run time
- `Last_Status__c` — `Success`, `Failed`, or `Skipped`

**Key:** `DeveloperName` of the mapping

## Code Structure

```
force-app/main/default/
├── classes/integration/
│   ├── IntegrationSyncRequestAction.cls            # Invocable action for Flow / Platform Events
│   │
│   ├── core/
│   │   ├── AbstractIntegrationService.cls          # Base service: makeCallout(method, urlPath[, body])
│   │   ├── IntegrationResult.cls                   # Wrapper for results
│   │   ├── IntegrationMappingCache.cls             # CMT caching (getMappingByName, getMappingsForEndpoint)
│   │   ├── TypedSyncService.cls                    # Base sync service (processSObjects, postProcessUpsert)
│   │   └── test/                                   # Core tests
│   │
│   ├── pagination/
│   │   ├── PaginationStrategy.cls                  # Abstract base (getHttpMethod, buildRequestBody, processResponse)
│   │   ├── PaginationState.cls                     # State wrapper (offset + customData for cursor)
│   │   ├── PaginationResult.cls                    # Result wrapper
│   │   ├── PaginationStrategyFactory.cls           # Strategy resolver (offset, graphql)
│   │   ├── CompanoOffsetPaginationStrategy.cls     # REST offset-based pagination
│   │   ├── GraphQLCursorPaginationStrategy.cls     # GraphQL cursor-based pagination
│   │   └── test/                                   # Pagination tests
│   │
│   ├── queueable/
│   │   ├── AbstractPullQueueable.cls               # Base queueable logic
│   │   ├── PullQueueable.cls                       # Full batch sync (paginated)
│   │   ├── SingleRecordPullQueueable.cls           # Single-record sync by external ID
│   │   └── test/                                   # Queueable tests
│   │
│   ├── scheduling/
│   │   ├── UniversalIntegrationScheduler.cls       # Master scheduler (recommended)
│   │   ├── IntegrationFrequencyCalculator.cls      # Per-mapping frequency logic
│   │   ├── IntegrationSchedulable.cls              # Legacy single-endpoint scheduler
│   │   ├── ThrottledIntegrationRunner.cls          # Throttling logic
│   │   └── test/                                   # Scheduling tests
│   │
│   └── test/
│       └── IntegrationSyncRequestActionTest.cls
│
└── objects/
    ├── Integration_Pagination_State__c/            # Run time per mapping (List Custom Setting)
    └── IntegrationExecutionState__c/               # Scheduler state per mapping (Hierarchy Custom Setting)
```

## Extending the Framework

### Adding a New Pagination Strategy

1. **Create class extending `PaginationStrategy`:**
   ```apex
   public class MyApiPaginationStrategy extends PaginationStrategy {
       public override PaginationResult processResponse(HttpResponse response, PaginationState state) { }
       public override String modifyEndpointUrl(String baseUrl, PaginationState state) { }
   }
   ```

2. **Option A: Register shorthand** in `PaginationStrategyFactory.registerBuiltInStrategies()`
   ```apex
   strategyTypes.put('myapi', MyApiPaginationStrategy.class);
   ```

3. **Option B: Use full class name** in `Integration_Endpoint__mdt.Pagination_Config__c`
   ```
   Pagination_Config__c = "MyApiPaginationStrategy"
   ```

### Adding Custom Upsert Logic

1. **Create service extending `TypedSyncService`:**
   ```apex
   public class Product2SyncService extends TypedSyncService {
       public override List<SObject> processSObjects(List<SObject> sObjects) {
           // Custom validation/transformation before upsert
           return sObjects;
       }

       public override void postProcessUpsert(List<SObject> successfulUpserts, Map<Id, SObject> originalRecordsMap) {
           // Optional post-upsert logic
       }
   }
   ```

2. **Name convention:** `[TargetObject]SyncService` (auto-discovered, no registration needed)
   - `Target_Object__c = Product2` → `Product2SyncService.cls`

### Single Record Sync

`SingleRecordPullQueueable` fetches one record by external ID, skipping pagination entirely:

1. Builds URL as `Base_Path__c + Resource_Path__c + externalRecordId + /`
2. Makes a GET callout, normalises the response to a JSON array
3. Passes it through the mapping's DataWeave script
4. Upserts the result using the configured external ID field

```apex
System.enqueueJob(new SingleRecordPullQueueable(
    'My_Endpoint',   // Integration_Endpoint__mdt.DeveloperName
    'My_Mapping',    // Integration_Mapping__mdt.DeveloperName
    'PROD-12345'     // external system ID
));
```

### Event-Driven Execution (Flow / Platform Events)

`IntegrationSyncRequestAction` is an `@InvocableMethod` (label: **"Trigger Integration Sync"**, category: **Integration**) that can be called from any Flow, Process Builder, or Platform Event trigger.

**Inputs:**

| Variable | Required | Description |
|----------|----------|-------------|
| `Mapping Name` | Yes | `DeveloperName` of the `Integration_Mapping__mdt` record |
| `External Record ID` | No | External system ID — leave blank for full batch sync |
| `Operation Name` | No | Label for this job in logs (defaults to `FlowTriggered_<MappingName>`) |

**Outputs:**

| Variable | Description |
|----------|-------------|
| `Success` | `true` if the job was enqueued successfully |
| `Error Message` | Description of what went wrong (only set when `Success = false`) |

- **Blank External Record ID** → enqueues `PullQueueable` (full batch sync)
- **External Record ID set** → enqueues `SingleRecordPullQueueable`

**Recommended Flow architecture:**
```
Platform Event: Integration_Sync_Request__e
    │  (published by external system)
    ▼
Record-Triggered Flow
    │
    ▼
Action: "Trigger Integration Sync"
    Mapping Name       = {!$Record.Mapping_Name__c}
    External Record ID = {!$Record.External_Record_Id__c}
```

**Publishing the event from an external system:**
```http
POST /services/data/v60.0/sobjects/Integration_Sync_Request__e
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "Mapping_Name__c": "My_Mapping",
  "External_Record_Id__c": "PROD-12345"
}
```

### Customizing Logging

Per-integration Nebula Logger support:

1. **Enable per endpoint:** Set `Integration_Endpoint__mdt.Enable_Nebula_Logger__c = true`
2. **Set per-mapping tags:** Set `Integration_Mapping__mdt.Logger_Tags__c = "tag1,tag2"` (comma-separated)
3. Tags are parsed at execution start and applied to key log entries via `applyTags()` — making it easy to filter logs by mapping in Nebula Logger's UI

## Testing

Run the full test suite:
```bash
sf apex run test -w 30 -c
```

Run specific test class:
```bash
sf apex run test -n GraphQLCursorPaginationStrategyTest -w 30
```

## Troubleshooting

### Integration not pulling data

1. **Check logs:**
   ```bash
   sf apex log list
   sf apex log get -n [LogId]
   ```

2. **Verify metadata:**
   - `Integration_Endpoint__mdt.Active__c = true`?
   - `Integration_Mapping__mdt.Active__c = true`?
   - Named Credential reachable?

3. **Inspect mapping via Anonymous Apex:**
   ```apex
   Integration_Mapping__mdt m = IntegrationMappingCache.getMappingByName('My_API_Products');
   System.debug(m);
   System.debug(m.Endpoint__r);
   ```

### State not persisting

Check `Integration_Pagination_State__c` (run time tracking):
```bash
sf data query --query "SELECT Id, Name, Last_Run_Date__c FROM Integration_Pagination_State__c"
```

Check `IntegrationExecutionState__c` (scheduler frequency tracking):
```bash
sf data query --query "SELECT Id, Name, Last_Run_Date__c, Next_Scheduled_Time__c, Last_Status__c FROM IntegrationExecutionState__c"
```

### Pagination errors

1. Verify `Pagination_Type__c` matches your API (e.g., `offset` or `graphql`)
2. Check HTTP response format matches the strategy's expected structure
3. Review logs for parsing errors

## Performance Considerations

- **Page Size**: Default 100 records, adjust via `Page_Size__c` on the mapping
- **Governor Limits**: ~100 DML rows per callout batch; adjust page size if hitting limits
- **Mapping Cache**: Cached per transaction — clear via `IntegrationMappingCache.clearCache()`
- **Chaining**: Multi-page results chain automatically via `System.enqueueJob(this)`; Salesforce allows up to 50 chained jobs per transaction

## Contributing

1. Ensure >75% code coverage on new classes
2. Add tests in `test/` subfolder: `[ClassName]Test.cls`
3. Add `@Author: R. Groot Date: [Date]` comment to class header
4. Follow Apex best practices: bind variables in SOQL, bulk DML, no SOQL/DML in loops

## License

Apache 2.0

## Support

For issues or questions, open a GitHub issue or contact the Welisa development team.
