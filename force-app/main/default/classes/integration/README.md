# Integration Framework

This folder contains the reusable integration framework organized into logical layers:

## Folder Structure

### `/core`
Core orchestration and caching logic:
- **AbstractIntegrationService.cls** - Base service class for sync operations. Reads `Integration_Mapping__mdt` records to drive sync behavior.
- **IntegrationMappingCache.cls** - Runtime cache for `Integration_Mapping__mdt` custom metadata. Loaded once per org session.
- **IntegrationResult.cls** - Result wrapper with status, message, and error details.
- **TypedSyncService.cls** - Generic typed sync service base class.

### `/pagination`
Pagination strategy pattern for handling API responses:
- **PaginationStrategy.cls** - Abstract interface for pagination strategies.
- **PaginationResult.cls** - Represents a paginated API response with result set and next page cursor.
- **PaginationState.cls** - Tracks pagination state across requests.
- **CompanoOffsetPaginationStrategy.cls** - Offset-based pagination (example: `/API/jsonfeed/products?offset=0&limit=100`).
- **PaginationStrategyFactory.cls** - Factory pattern to instantiate strategy implementations.

### `/queueable`
Async batch processing for API data:
- **AbstractPullQueueable.cls** - Base queueable for pulling data from external APIs.
- **PullQueueable.cls** - Concrete implementation for data synchronization.

### `/scheduling`
Scheduled and throttled execution:
- **IntegrationSchedulable.cls** - Schedulable job for periodic sync operations.
- **ThrottledIntegrationRunner.cls** - Wraps queueable execution with configurable rate-limiting.

## How It Works

1. **Configuration**: Create `Integration_Mapping__mdt` records that link:
   - External API endpoint (via `Integration_Endpoint__c` lookup)
   - Source object/resource path (e.g., `/API/jsonfeed/products`)
   - Target Salesforce object (e.g., `Product2`)
   - Field mapping logic (DataWeave transform name or inline mapping)

2. **Orchestration**: `IntegrationMappingCache` reads all active `Integration_Mapping__mdt` records at startup.

3. **Execution**: `AbstractIntegrationService` orchestrates the sync based on mapping configuration:
   - Fetches from external API using configured pagination strategy
   - Transforms data using mapped fields
   - UPSERT/CREATE/UPDATE into target Salesforce object
   - Logs via Nebula Logger

4. **Scheduling**: `IntegrationSchedulable` triggers sync on a schedule (configurable via job scheduling UI).

## Customization for Compano Integration

⚠️ **Important**: The framework includes some vendor-specific code that needs customization:

### PullQueueable.cls
Currently contains example patterns from a reference implementation. Configure before use:
1. Review `PullQueueable.cls` and customize object references as needed
2. Adjust the data transformation logic for your specific use cases
3. Use your `Integration_Mapping__mdt` records to parametrize behavior instead of hard-coding

### Integration_Mapping__mdt
Ensure your `Integration_Mapping__mdt` records include:
- `Active__c` = true
- `Endpoint__c` → points to your `Integration_Endpoint` (e.g., Compano_Named_Credentials)
- `Source_Object__c` → external resource (e.g., "products", "orders")
- `Target_Object__c` → Salesforce object (e.g., "Product2", "Order")
- `Operation_Type__c` → "CREATE", "UPDATE", or "UPSERT"
- `Resource_Path__c` → API endpoint path
- `Dataweave_Map_Name__c` → (optional) name of transform, or null for automatic field mapping

## Next Steps

1. ✅ Framework organized and ready to customize
2. ⏳ Update `PullQueueable.cls` for your Compano objects
3. ⏳ Create `Integration_Mapping__mdt` records for each Compano sync (Products, Orders, Customers, etc.)
4. ⏳ Test with Compano API via `WebFormSubmissionRestService` or scheduled jobs
5. ⏳ Monitor sync performance and adjust pagination/throttling settings as needed

## Related Files

- **REST API**: `WebFormSubmissionRestService.cls` - Web form intake endpoint (uses for initial data)
- **Credentials**: Compano_Named_Credentials, Compano_External_Credentials
- **Logging**: Nebula Logger (all framework classes log via Logger.info/warn/error)
