/**
 * @description Invocable action that enqueues an integration sync job from a Flow, Process Builder,
 * or any other Salesforce automation. Supports both full batch sync and single-record sync.
 *
 * Flow usage:
 *   - Set "Mapping Name" to the DeveloperName of the Integration_Mapping__mdt record.
 *   - Leave "External Record ID" blank for a full batch sync.
 *   - Set "External Record ID" to trigger a single-record sync via SingleRecordPullQueueable.
 *
 * Platform Event usage (e.g. triggered by FIPA):
 *   Publish Integration_Sync_Request__e → Flow listens → calls this action.
 *
 * @Author: R. Groot Date: 23-04-2026
 */
public class IntegrationSyncRequestAction {

    @InvocableMethod(
        label='Trigger Integration Sync'
        description='Enqueues a sync job for a mapping. Leave External Record ID blank for a full batch sync.'
        category='Integration'
    )
    public static List<Result> triggerSync(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(processRequest(req));
        }
        return results;
    }

    private static Result processRequest(Request req) {
        try {
            if (String.isBlank(req.mappingName)) {
                return errorResult('mappingName is required');
            }

            Integration_Mapping__mdt mapping = IntegrationMappingCache.getMappingByName(req.mappingName);
            if (mapping == null) {
                return errorResult('No active mapping found: ' + req.mappingName);
            }

            String endpointName = mapping.Endpoint__r?.DeveloperName;
            if (String.isBlank(endpointName)) {
                return errorResult('Mapping has no endpoint configured: ' + req.mappingName);
            }

            if (String.isNotBlank(req.externalRecordId)) {
                System.enqueueJob(new SingleRecordPullQueueable(
                    endpointName,
                    req.mappingName,
                    req.externalRecordId
                ));
                Logger.info('IntegrationSyncRequestAction: enqueued SingleRecordPullQueueable'
                    + ' mapping=' + req.mappingName
                    + ' externalId=' + req.externalRecordId);
            } else {
                String opName = String.isNotBlank(req.operationName)
                    ? req.operationName
                    : 'FlowTriggered_' + req.mappingName;
                System.enqueueJob(new PullQueueable(
                    endpointName,
                    req.mappingName,
                    opName,
                    null,
                    null,
                    mapping.Sync_Order__c != null ? mapping.Sync_Order__c.intValue() : 1
                ));
                Logger.info('IntegrationSyncRequestAction: enqueued PullQueueable'
                    + ' mapping=' + req.mappingName
                    + ' operation=' + opName);
            }

            Result res = new Result();
            res.isSuccess = true;
            return res;

        } catch (Exception e) {
            Logger.error('IntegrationSyncRequestAction failed for mapping='
                + req?.mappingName + ': ' + e.getMessage());
            return errorResult(e.getMessage());
        }
    }

    private static Result errorResult(String message) {
        Result res = new Result();
        res.isSuccess    = false;
        res.errorMessage = message;
        Logger.warn('IntegrationSyncRequestAction: ' + message);
        return res;
    }

    // ─── Invocable Input ─────────────────────────────────────────────────────

    public class Request {
        @InvocableVariable(
            required=true
            label='Mapping Name'
            description='DeveloperName of the Integration_Mapping__mdt record to sync'
        )
        public String mappingName;

        @InvocableVariable(
            required=false
            label='External Record ID'
            description='External system ID of a single record to sync. Leave blank for a full batch sync.'
        )
        public String externalRecordId;

        @InvocableVariable(
            required=false
            label='Operation Name'
            description='Optional label for this sync job (visible in logs). Defaults to FlowTriggered_<MappingName>.'
        )
        public String operationName;
    }

    // ─── Invocable Output ────────────────────────────────────────────────────

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean isSuccess;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }
}
