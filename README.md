# Salesforce Integration Framework

An org-agnostic, configuration-driven Salesforce integration framework for building scalable multi-API integrations. This framework handles pagination, state tracking, logging, and queueable execution.

## Features

- **🔧 Configuration-Driven**: All behavior configured via Custom Metadata Type records
- **📊 Smart Pagination**: Built-in REST (offset) and GraphQL (cursor) pagination strategies
- **🔗 Multi-Protocol**: REST (GET) and GraphQL (POST) supported via the same pipeline
- **⏱️ State Tracking**: Per-mapping pagination state persistence via Custom Settings
- **📝 Logging**: Integrated Nebula Logger with per-integration and per-mapping tag control
- **🚀 Queueable Execution**: Async job scheduling with concurrent execution limits
- **🧪 Fully Tested**: >75% code coverage with comprehensive test suite
- **🔄 Org-Agnostic**: Zero hardcoded business logic or org-specific references

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ IntegrationSchedulable / Manual Trigger                     │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│ ThrottledIntegrationRunner (Asyncable/Schedulable)          │
│ • Enqueues PullQueueable jobs                               │
│ • Respects concurrent job limits                            │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│ PullQueueable (Queueable)                                   │
│ • Extends AbstractPullQueueable                             │
│ • Implements pullAndProcessRecords()                        │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│ AbstractPullQueueable (Base Logic)                          │
│ • HTTP call via named credential                           │
│ • Pagination strategy resolution                           │
│ • Per-mapping state persistence                            │
│ • Nebula Logger integration                                │
│ • TypedSyncService delegation (optional)                   │
└─────────────────────┬───────────────────────────────────────┘
                      │
        ┌─────────────┴──────────────┐
        │                            │
┌───────▼──────┐          ┌──────────▼────────┐
│ DataWeave    │          │ TypedSyncService  │
│ Transform    │          │ (Custom Impl)     │
│ (Mule/Apex)  │          │ • Lookups         │
│ • Lookups    │          │ • Validation      │
│ • Transforms │          │ • Upsert logic    │
│ • Mapping    │          └───────────────────┘
└──────────────┘
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
   - Create `Integration_Pagination_State__c` records for state tracking (optional, auto-created)

4. **Implement your first integration**
   - Follow the [Setup Guide](#setup-guide) below

## Setup Guide

### Step 1: Create a Pagination Strategy (if needed)

If you need custom pagination logic (non-Compano), create a class extending `PaginationStrategy`:

```apex
/**
 * Custom pagination for [Your API]
 * Handles [Specific pagination format]
 * @Author: R. Groot Date: [Date]
 */
public class CustomApiPaginationStrategy extends PaginationStrategy {
    public override PaginationResult processResponse(HttpResponse response, PaginationState state) {
        // Extract records and calculate next pagination state
        // Return PaginationResult.createSuccess(records, nextState, hasMore)
    }
    
    public override String modifyEndpointUrl(String baseUrl, PaginationState state) {
        // Apply pagination parameters to URL
        return baseUrl + "?page=" + state.getOffset();
    }
}
```

**Then register in `PaginationStrategyFactory`**:
```apex
strategyTypes.put('your-api', CustomApiPaginationStrategy.class);
```

**Or use full class name in metadata** (see Custom Metadata section below):
```
Pagination_Config__c = "com.example.CustomApiPaginationStrategy"
```

### Step 2: Create Named Credential

In your Salesforce org:

1. Go to **Setup > Named Credentials**
2. Create a new credential with:
   - **Label**: e.g., `Compano_API`
   - **Name**: e.g., `Compano_API` (used in Integration_Endpoint__mdt)
   - **URL**: https://api.example.com/base/path
   - **Authentication Protocol**: OAuth 2.0
   - **Authentication Provider**: [Your Auth Provider]
   - **Scope**: [Required scopes]

Alternative: Use **External Credentials** (Salesforce native OAuth):
1. Go to **Setup > External Credentials**
2. Create credential and principal
3. Reference in Integration_Endpoint__mdt by name

### Step 3: Create Integration_Endpoint__mdt Record

Go to **Setup > Custom Metadata Types > Integration_Endpoint__mdt > Manage Records**

Create a record with these required fields:

| Field | Type | Example | Required |
|-------|------|---------|----------|
| Label | Text | `Compano API` | ✅ |
| Endpoint_Name__c | Text | `Compano` | ✅ |
| Base_Url__c | URL | `https://api.compano.com/v1` | ✅ |
| Named_Credential__c | Text | `Compano_API` | ✅ |
| Pagination_Type__c | Text | `offset` | ❌ |
| Pagination_Config__c | Text | `com.example.CustomApiPaginationStrategy` | ❌ |
| Page_Size__c | Number | `100` | ❌ |
| Enable_Nebula_Logger__c | Checkbox | `true` | ❌ |
| Timeout_Seconds__c | Number | `30` | ❌ |

### Step 4: Create Integration_Mapping__mdt Records

Go to **Setup > Custom Metadata Types > Integration_Mapping__mdt > Manage Records**

Create records for each Salesforce object type you're syncing:

| Field | Type | Example | Required |
|-------|------|---------|----------|
| Label | Text | `Account Mapping` | ✅ |
| Mapping_Name__c | Text | `Account` | ✅ |
| Target_Object__c | Text | `Account` | ✅ |
| Endpoint__c | Lookup | `Compano` | ✅ |
| External_Id_Field__c | Text | `External_ID__c` | ✅ |
| DataWeave_Transform_Resource__c | Text | `account-transform` | ✅ |
| Pagination_Enabled__c | Checkbox | `true` | ❌ |
| Pagination_Page_Size__c | Number | `100` | ❌ |
| Logger_Tags__c | Text | `account,sync,compano` | ❌ |

### Step 5: Implement Your Sync Service (Optional)

If you need custom upsert logic, create a `TypedSyncService` implementation:

```apex
/**
 * Custom upsert logic for Account records
 * Handles validation and lookups specific to Account
 * @Author: R. Groot Date: [Date]
 */
public class AccountSyncService extends TypedSyncService {
    public AccountSyncService(Integration_Mapping__mdt mapping) {
        super(mapping);
    }
    
    public override void processBatch(List<SObject> records) {
        // Add custom validation or transformation logic
        upsertRecords(records);
    }
}
```

Service is auto-discovered by naming: `[TargetObject]SyncService.cls`
(e.g., `Account` → `AccountSyncService`)

### Step 6: Schedule the Integration

Create an **Apex Schedule** or use **Flow**:

**Option A: Apex Batch Schedule**
```apex
// Schedule in Setup > Apex Classes > Schedule Apex
String jobName = 'Compano Account Sync';
String cronExpression = '0 0 * * * ?'; // Daily at midnight
System.schedule(jobName, cronExpression, new IntegrationSchedulable('Account'));
```

**Option B: Flow-based Trigger**
1. Create a Flow
2. Add HTTP Request element calling your PullQueueable
3. Or directly enqueue: `new PullQueueable('Account').enqueueJob()`

### Step 7: Run the Integration

Manual execution:
```apex
Database.executeBatch(new PullQueueable('Account'), 1);
// Or enqueue as queueable:
System.enqueueJob(new PullQueueable('Account'));
```

## Configuration Reference

### Custom Metadata Objects

#### Integration_Endpoint__mdt

Represents a single API endpoint with pagination and logging config.

**Key Fields:**
- `Named_Credential__c` (Text) — Named Credential or External Credential name
- `Base_Path__c` (Text) — Base API path (e.g. `/api/v1/`) or GraphQL path (e.g. `/graphql`)
- `Protocol_Type__c` (Picklist) — `REST` (default) or `GraphQL`
- `Pagination_Type__c` (Text) — Shorthand pagination strategy key
  - Built-in: `offset` (REST), `graphql` (GraphQL)
  - Custom: Register in `PaginationStrategyFactory.registerBuiltInStrategies()`
- `Pagination_Config__c` (Text) — Full Apex class name (overrides Pagination_Type__c)
- `External_ID_Field__c` (Text) — External ID field for upsert (e.g. `External_ID__c`)
- `Timeout__c` (Number) — HTTP timeout in milliseconds (default: 30000)

#### Integration_Mapping__mdt

Maps a Salesforce object to API endpoint and transformation rules.

**Key Fields:**
- `Target_Object__c` (Text) — Salesforce SObject API name (e.g., `Account`)
- `Source_Object__c` (Text) — External system resource name
- `Endpoint__c` (Metadata Lookup) — Reference to Integration_Endpoint__mdt
- `Resource_Path__c` (Text) — REST resource path appended to Base_Path__c (e.g., `products`)
- `GraphQL_Query__c` (Long Text) — Full GraphQL query string with `$first: Int, $after: String` variables. Only used when endpoint `Protocol_Type__c = GraphQL`.
- `Dataweave_Map_Name__c` (Text) — DataWeave script name for transformation
- `External_Id_Field_Overide__c` (Text) — Override the endpoint's external ID field per mapping
- `Page_Size__c` (Number) — Override page size (uses endpoint default if blank)
- `Sync_Order__c` (Number) — Execution order when multiple mappings share one endpoint

### Custom Settings

#### Integration_Pagination_State__c (List Custom Setting)

Persists pagination state between integration runs. **Auto-managed** by AbstractPullQueueable.

**Fields:**
- `Last_Run_Date__c` — Timestamp of last successful API call
- `State_Data__c` — JSON serialized pagination state (internal use)

**Key:** Identified by Mapping_Name__c (e.g., "Account")

## Code Structure

```
force-app/main/default/
├── classes/integration/
│   ├── core/
│   │   ├── AbstractIntegrationService.cls          # Base service class
│   │   ├── IntegrationResult.cls                   # Wrapper for results
│   │   ├── IntegrationMappingCache.cls             # CMT caching
│   │   ├── TypedSyncService.cls                    # Base sync service
│   │   └── test/                                   # Core tests
│   │
│   ├── pagination/
│   │   ├── PaginationStrategy.cls                  # Base pagination class (getHttpMethod, buildRequestBody)
│   │   ├── PaginationState.cls                     # State wrapper (offset + customData for cursor)
│   │   ├── PaginationResult.cls                    # Result wrapper
│   │   ├── PaginationStrategyFactory.cls           # Strategy resolver (offset, graphql)
│   │   ├── CompanoOffsetPaginationStrategy.cls     # REST offset-based pagination
│   │   ├── GraphQLCursorPaginationStrategy.cls     # GraphQL cursor-based pagination
│   │   └── test/                                   # Pagination tests
│   │
│   ├── queueable/
│   │   ├── AbstractPullQueueable.cls               # Base queueable logic
│   │   ├── PullQueueable.cls                       # Concrete queueable
│   │   └── test/                                   # Queueable tests
│   │
│   └── scheduling/
│       ├── IntegrationSchedulable.cls              # Schedulable wrapper
│       ├── ThrottledIntegrationRunner.cls          # Throttling logic
│       └── test/                                   # Scheduling tests
│
├── customMetadata/
│   ├── Integration_Endpoint__mdt/                  # API endpoint config
│   └── Integration_Mapping__mdt/                   # Object mapping config
│
└── objects/
    └── Integration_Pagination_State__c/            # Custom Setting
```

## Extending the Framework

### Adding a New Pagination Strategy

1. **Create class extending `PaginationStrategy`:**
   ```apex
   public class MyCustomPaginationStrategy extends PaginationStrategy {
       public override PaginationResult processResponse(HttpResponse response, PaginationState state) { }
       public override String modifyEndpointUrl(String baseUrl, PaginationState state) { }
   }
   ```

2. **Option A: Register shorthand** in `PaginationStrategyFactory.registerBuiltInStrategies()`
   ```apex
   strategyTypes.put('myapi', MyCustomPaginationStrategy.class);
   ```

3. **Option B: Use full class name** in `Integration_Endpoint__mdt.Pagination_Config__c`
   ```
   Pagination_Config__c = "com.example.MyCustomPaginationStrategy"
   ```

### Adding Custom Upsert Logic

1. **Create service extending `TypedSyncService`:**
   ```apex
   public class AccountSyncService extends TypedSyncService {
       public AccountSyncService(Integration_Mapping__mdt mapping) {
           super(mapping);
       }
       
       public override void processBatch(List<SObject> records) {
           // Custom validation/transformation
           upsertRecords(records);
       }
   }
   ```

2. **Name convention:** `[TargetObject]SyncService` (auto-discovered)
   - Target Object: `Account` → Class: `AccountSyncService.cls`

### Customizing Logging

Per-integration and per-mapping Nebula Logger integration:

1. **Disable globally:** Set `Integration_Endpoint__mdt.Enable_Nebula_Logger__c = false`
2. **Set per-mapping tags:** Use `Integration_Mapping__mdt.Logger_Tags__c = "tag1,tag2,tag3"`
3. **Access in custom code:**
   ```apex
   Integration_Mapping__mdt mapping = IntegrationMappingCache.getInstance(label).get(mappingName);
   List<String> tags = (List<String>) mapping.get('Logger_Tags__c');
   // Use with Logger.info(...).addTag('tag1')
   ```

## Testing

Run the full test suite:
```bash
sf apex run test -w 30 -c
```

Run specific test class:
```bash
sf apex run test -n PaginationStrategyFactoryTest -w 30
```

## Troubleshooting

### Integration not pulling data

1. **Check logs:**
   ```bash
   sf apex log list
   sf apex log get -n [LogId]
   ```

2. **Verify metadata:**
   - Integration_Endpoint__mdt record exists? ✓
   - Integration_Mapping__mdt points to correct endpoint? ✓
   - Named Credential configured? ✓

3. **Test HTTP callout:**
   ```apex
   // In Execute Anonymous
   Integration_Mapping__mdt mapping = IntegrationMappingCache.getInstance('Integration_Endpoint__c').getMappingByName('Account');
   System.debug(mapping);
   ```

### State not persisting

Check `Integration_Pagination_State__c`:
```bash
sf data query --query "SELECT Id, DeveloperName, Last_Run_Date__c FROM Integration_Pagination_State__c"
```

### Pagination errors

1. Verify `Pagination_Type__c` or `Pagination_Config__c` is set correctly
2. Check HTTP response format matches strategy expectations
3. Review logs for parsing errors

## Performance Considerations

- **Batch Size**: Default 100 records, adjust via `Page_Size__c`
- **Concurrent Jobs**: Limit via ThrottledIntegrationRunner
- **Governor Limits**: 
  - ~100 records per APIcall
  - ~150 DML statements per execution
  - Adjust batch sizes based on your org's needs
- **Custom Metadata Cache**: Cached for performance (clear via `IntegrationMappingCache.invalidate()`)

## Contributing

1. Ensure >75% code coverage on new classes
2. Add tests in `test/` subfolder: `[ClassName]Test.cls`
3. Use consistent naming: `@Author: R. Groot Date: [Date]` in class headers
4. Follow Apex best practices: bind variables, bulk operations, DML error handling

## License

Apache 2.0

## Support

For issues or questions, open a GitHub issue or contact the Welisa development team.
