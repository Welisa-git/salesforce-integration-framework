/**
 * @description Abstract base class for object-specific sync services
 * Provides extension point for custom record processing logic
 */
public abstract class TypedSyncService {
    /**
     * @description Process SObjects for specific object types that need custom handling
     * @param sObjects List of SObjects to process
     * @return List<SObject> Processed SObjects
     */
    public abstract List<SObject> processSObjects(List<SObject> sObjects);

    /**
     * @description Optional method to perform actions after records are successfully upserted.
     *              Runs after the Database.upsert operation in the queueable.
     * @param successfulUpserts List of SObjects representing the records successfully upserted.
     *                          These SObjects will contain the final Salesforce ID.
     * @param originalRecordsMap A map where the key is the Salesforce ID of a successfully
     *                           upserted record and the value is the original SObject record
     *                           as it was prepared *before* the upsert operation.
     */
    public virtual void postProcessUpsert(List<SObject> successfulUpserts, Map<Id, SObject> originalRecordsMap) {
        // Default implementation does nothing. Override in subclasses as needed.
        System.debug('Base TypedSyncService.postProcessUpsert called. Override if post-upsert logic is needed.');
    }
}