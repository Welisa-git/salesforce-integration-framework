# Integration Framework

This folder contains the reusable integration framework organized into logical layers:

## Folder Structure

### `/core`
Core orchestration and caching logic:
- **AbstractIntegrationService.cls** - Base service class for sync operations. Provides `makeCallout(method, urlPath)` and `makeCallout(method, urlPath, requestBody)` for REST and GraphQL callouts.
- **IntegrationMappingCache.cls** - Runtime cache for `Integration_Mapping__mdt` custom metadata. Loaded once per org session.
- **IntegrationResult.cls** - Result wrapper with status, message, and error details.
- **TypedSyncService.cls** - Generic typed sync service base class.

### `/pagination`
Pagination strategy pattern for handling API responses:
- **PaginationStrategy.cls** - Abstract base for pagination strategies. Exposes `getHttpMethod()` (default: `GET`) and `buildRequestBody(state)` (default: `null`) for protocol-specific overrides.
- **PaginationResult.cls** - Represents a paginated API response with result set and next page cursor.
- **PaginationState.cls** - Tracks pagination state across requests (offset + `customData` map for cursors).
- **CompanoOffsetPaginationStrategy.cls** - Offset-based pagination for REST (e.g. `/API/jsonfeed/products/1/100/`).
- **GraphQLCursorPaginationStrategy.cls** - Cursor-based pagination for GraphQL endpoints. Sends POST with `{"query":"...", "variables":{"first":N,"after":"cursor"}}`. Parses `data.<rootField>.edges` and `pageInfo.{hasNextPage, endCursor}`.
- **PaginationStrategyFactory.cls** - Factory pattern to instantiate strategy implementations. Registered strategies: `offset` (REST), `graphql` (GraphQL).

### `/queueable`
Async batch processing for API data:
- **AbstractPullQueueable.cls** - Base queueable for pulling data from external APIs.
- **PullQueueable.cls** - Concrete implementation for data synchronization. Uses `strategy.getHttpMethod()` and `strategy.buildRequestBody()` — protocol-agnostic.

### `/scheduling`
Scheduled and throttled execution:
- **UniversalIntegrationScheduler.cls** - Single master scheduler that checks all active mappings and only enqueues jobs when their configured frequency is due. **Recommended** over individual scheduled jobs.
- **IntegrationFrequencyCalculator.cls** - Determines whether a mapping should execute based on `Execution_Frequency_Type__c` and `Execution_Frequency_Value__c`. Supports `Hourly`, `Daily`, `Weekly`, `Custom Minutes`.
- **IntegrationSchedulable.cls** - Legacy: schedulable job for a single endpoint with a fixed cron expression.
- **ThrottledIntegrationRunner.cls** - Wraps queueable execution with configurable rate-limiting.

---

## How It Works

1. **Configuration**: Create `Integration_Mapping__mdt` records that link:
   - External API endpoint (via `Integration_Endpoint__c` lookup)
   - Source object/resource path (REST) or GraphQL query (GraphQL)
   - Target Salesforce object (e.g., `Product2`)
   - DataWeave transform name

2. **Orchestration**: `IntegrationMappingCache` reads all active `Integration_Mapping__mdt` records at startup.

3. **Execution**: `PullQueueable` orchestrates the sync:
   - Asks the strategy for HTTP method + request body
   - Fetches from external API via `AbstractIntegrationService.makeCallout()`
   - Transforms data with DataWeave
   - Upserts into Salesforce
   - Chains next page or next mapping

4. **Scheduling (aanbevolen)**: Stel één `UniversalIntegrationScheduler` in die elke 5–15 minuten draait. Hij controleert per mapping de `Execution_Frequency_Type__c` en slaat over als het interval nog niet verstreken is.
   ```apex
   UniversalIntegrationScheduler.scheduleUniversalSchedler('Integration_Master_Scheduler', 15);
   ```
   Per mapping staat de uitvoerstatus in `IntegrationExecutionState__c` (Hierarchy Custom Setting).

5. **Scheduling (legacy)**: `IntegrationSchedulable` kan nog steeds gebruikt worden voor één endpoint met een vaste cron expressie.

---

## Configuring a REST Endpoint

**Integration_Endpoint__mdt:**
| Field | Value |
|-------|-------|
| `Named_Credential__c` | Named Credential name |
| `Base_Path__c` | API base path (e.g. `/api/v1/`) |
| `Pagination_Type__c` | `offset` |
| `Protocol_Type__c` | `REST` (or blank) |
| `Timeout__c` | ms (e.g. 30000) |

**Integration_Mapping__mdt:**
| Field | Value |
|-------|-------|
| `Endpoint__c` | Reference to Integration_Endpoint |
| `Resource_Path__c` | Resource path (e.g. `products`) |
| `Target_Object__c` | Salesforce object (e.g. `Product2`) |
| `Dataweave_Map_Name__c` | DataWeave script name |
| `Page_Size__c` | Records per page (e.g. 100) |

---

## Configuring a GraphQL Endpoint

**Integration_Endpoint__mdt:**
| Field | Value |
|-------|-------|
| `Named_Credential__c` | Named Credential name |
| `Base_Path__c` | GraphQL endpoint path (e.g. `/graphql`) |
| `Pagination_Type__c` | `graphql` |
| `Protocol_Type__c` | `GraphQL` |
| `Timeout__c` | ms (e.g. 30000) |

**Integration_Mapping__mdt:**
| Field | Value |
|-------|-------|
| `Endpoint__c` | Reference to Integration_Endpoint |
| `GraphQL_Query__c` | Full GraphQL query with `$first: Int, $after: String` variables |
| `Target_Object__c` | Salesforce object (e.g. `Product2`) |
| `Dataweave_Map_Name__c` | DataWeave script name |
| `Page_Size__c` | Records per page (e.g. 50) |

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

## Adding a Custom Pagination Strategy

1. Create a class extending `PaginationStrategy`
2. Override `processResponse()` and `modifyEndpointUrl()`
3. For non-GET protocols: also override `getHttpMethod()` and `buildRequestBody()`
4. Register in `PaginationStrategyFactory.registerBuiltInStrategies()`:
   ```apex
   strategyTypes.put('myapi', MyApiPaginationStrategy.class);
   ```

---

## Related

- **Logging**: Nebula Logger (all framework classes log via `Logger.info/warn/error`)
- **Auth**: Named Credentials + External Credentials (protocol-agnostic, works for both REST and GraphQL)
