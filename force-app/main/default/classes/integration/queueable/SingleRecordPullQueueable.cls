/**
 * @description Queueable for syncing a single external record by its external ID.
 * Builds a direct URL: Base_Path__c + Resource_Path__c + externalRecordId + '/'
 * Expects the API to return either a JSON object or an array containing the record.
 * Uses the same DataWeave script and upsert pipeline as PullQueueable — no pagination.
 * @Author: R. Groot Date: 23-04-2026
 */
public class SingleRecordPullQueueable extends AbstractPullQueueable {

    @TestVisible private final String externalRecordId;

    /**
     * @description Constructor for single-record sync
     * @param endpointName DeveloperName of Integration_Endpoint__mdt
     * @param mappingName  DeveloperName of Integration_Mapping__mdt
     * @param externalRecordId The external system ID of the record to sync
     */
    public SingleRecordPullQueueable(String endpointName, String mappingName, String externalRecordId) {
        super(endpointName, mappingName,
              'SingleRecord_' + externalRecordId,
              null, null, 1);
        this.externalRecordId = externalRecordId;
    }

    protected override IntegrationResult pullAndProcessRecords() {
        if (mapping == null) {
            return IntegrationResult.createError('No mapping found',
                'Mapping not found for: ' + mappingName);
        }
        if (String.isBlank(externalRecordId)) {
            return IntegrationResult.createError('Invalid input',
                'externalRecordId cannot be blank');
        }

        String url = buildSingleRecordUrl();
        applyTags(Logger.info('Fetching single record: externalId=' + externalRecordId + ' mapping=' + mappingName));
        Logger.debug('SingleRecordPullQueueable URL: ' + url);

        HttpResponse response = makeCallout('GET', url);

        if (response.getStatusCode() >= 400) {
            Logger.saveLog();
            return IntegrationResult.createError(
                'HTTP ' + response.getStatusCode(),
                'Callout failed for externalId ' + externalRecordId
            );
        }

        String jsonRecords = normaliseToJsonArray(response.getBody());
        List<SObject> records = processDataweaveMapping(jsonRecords);
        records = filterToTargetRecord(records);

        applyTags(Logger.info('Single record sync complete: ' + records.size() + ' record(s) ready for upsert'));
        Logger.saveLog();

        PaginationResult pageResult = PaginationResult.createSuccess(records, null, false);
        IntegrationResult result = IntegrationResult.createSuccess('Single record synced: ' + externalRecordId);
        result.additionalDetails.put('paginationResult', pageResult);
        return result;
    }

    /**
     * @description Builds the single-record API URL: base + resource + id + trailing slash
     */
    @TestVisible
    private String buildSingleRecordUrl() {
        String base = String.isNotBlank(endpoint?.Base_Path__c) ? endpoint.Base_Path__c : '';
        String resource = String.isNotBlank(mapping?.Resource_Path__c) ? mapping.Resource_Path__c : '';
        while (base.endsWith('/')) base = base.removeEnd('/');
        while (resource.endsWith('/')) resource = resource.removeEnd('/');
        return base + '/' + resource + '/' + externalRecordId + '/';
    }

    /**
     * @description Normalises a raw API body to a JSON array string.
     * Wraps a single JSON object in an array so DataWeave always receives an array.
     */
    @TestVisible
    private static String normaliseToJsonArray(String body) {
        if (String.isBlank(body)) return '[]';
        String trimmed = body.trim();
        return trimmed.startsWith('[') ? trimmed : '[' + trimmed + ']';
    }

    /**
     * @description Post-transform safety filter: keeps only the record whose external ID
     * matches externalRecordId. Falls back to all records if no match is found
     * (e.g. the API already returned the correct single record without the ID field set).
     */
    private List<SObject> filterToTargetRecord(List<SObject> records) {
        if (records == null || records.isEmpty()) return new List<SObject>();

        String extIdField = String.isNotBlank(mapping?.External_Id_Field_Overide__c)
            ? mapping.External_Id_Field_Overide__c
            : endpoint?.External_ID_Field__c;

        if (String.isBlank(extIdField)) return records;

        List<SObject> filtered = new List<SObject>();
        for (SObject rec : records) {
            try {
                if (externalRecordId == String.valueOf(rec.get(extIdField))) {
                    filtered.add(rec);
                }
            } catch (Exception ignored) {}
        }

        if (filtered.isEmpty()) {
            Logger.warn('SingleRecordPullQueueable: no record matched externalId=' + externalRecordId
                + ' on field ' + extIdField + '; upserting all ' + records.size() + ' returned record(s)');
            return records;
        }

        return filtered;
    }
}
