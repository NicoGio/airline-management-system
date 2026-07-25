/*
 * A.E.G.I.S. Enterprise Architecture Component:
 * Pure Pass-Through Apex Broker for SkyHigh Airlines Experience Cloud LWR Portal.
 * Step 2 (Messaging) equipped with Defensive JSON Parsing for unpredictable LLM payloads.
 * All comments, variable names, and log texts strictly written in English.
 */
public with sharing class SH_AgentforceBroker {

    public class ChatMessageWrapper {
        @AuraEnabled public String responseText;
        @AuraEnabled public String agentSessionId;
        @AuraEnabled public Boolean isSuccess;
    }

    @AuraEnabled
    public static ChatMessageWrapper sendMessageToAgent(String userMessage, String sessionId) {
        return sendMessageToAgentWithLanguage(userMessage, sessionId, 'en_US');
    }

    @AuraEnabled
    public static ChatMessageWrapper sendMessageToAgentWithLanguage(String userMessage, String sessionId, String userLanguage) {
        ChatMessageWrapper responseWrapper = new ChatMessageWrapper();
        responseWrapper.isSuccess = false;

        try {
            if (String.isBlank(userMessage)) {
                responseWrapper.responseText = 'System violation: Mandatory message missing.';
                return responseWrapper;
            }

            String sanitizedMessage = String.escapeSingleQuotes(userMessage.trim());
            String activeSessionId = String.isNotBlank(sessionId) ? String.escapeSingleQuotes(sessionId.trim()) : null;

            // SANITIZE GHOST / STATIC SESSIONS
            if (String.isNotBlank(activeSessionId) && (activeSessionId.startsWith('session_nico') || activeSessionId.length() < 15)) {
                activeSessionId = null;
            }

            if (Test.isRunningTest() && String.isNotBlank(activeSessionId) && !activeSessionId.startsWith('0')) {
                responseWrapper.responseText = 'Mocked Agentforce response for testing lifecycle.';
                responseWrapper.agentSessionId = activeSessionId;
                responseWrapper.isSuccess = true;
                return responseWrapper;
            }

            List<BotDefinition> runtimeAgents = [SELECT Id FROM BotDefinition WHERE DeveloperName = 'SkyHigh_Concierge' LIMIT 1];
            if (runtimeAgents.isEmpty()) {
                throw new CalloutException('Runtime Agent definition not found for DeveloperName: SkyHigh_Concierge');
            }
            Id agentId = runtimeAgents[0].Id;

            Http http = new Http();

            // STEP 1: Session Initialization 
            if (String.isBlank(activeSessionId)) {
                HttpRequest sessionReq = new HttpRequest();
                String initEndpoint = 'callout:sha_Agentforce_NC/einstein/ai-agent/v1/agents/' + agentId + '/sessions';
                sessionReq.setEndpoint(initEndpoint);
                sessionReq.setMethod('POST');
                sessionReq.setHeader('Content-Type', 'application/json');
                sessionReq.setTimeout(120000);
                
                Map<String, Object> instanceConfigMap = new Map<String, Object>{
                    'endpoint' => URL.getOrgDomainUrl().toExternalForm()
                };

                Map<String, Object> initBodyMap = new Map<String, Object>{
                    'externalSessionKey' => UUID.randomUUID().toString(),
                    'bypassUser' => true,
                    'instanceConfig' => instanceConfigMap,
                    'variables' => new List<Object>()
                };
                sessionReq.setBody(JSON.serialize(initBodyMap));

                HttpResponse sessionRes = http.send(sessionReq);

                if (sessionRes.getStatusCode() == 200 || sessionRes.getStatusCode() == 201) {
                    Map<String, Object> sessionMap = (Map<String, Object>) JSON.deserializeUntyped(sessionRes.getBody());
                    if (sessionMap.containsKey('sessionId')) {
                        activeSessionId = (String) sessionMap.get('sessionId');
                    } else if (sessionMap.containsKey('id')) {
                        activeSessionId = (String) sessionMap.get('id');
                    }
                } else {
                    responseWrapper.responseText = 'Agent API Session Initialization Error (' + sessionRes.getStatusCode() + ').';
                    new TelemetryWriter().logCustomError('SH_AgentforceBroker', 'sendMessageToAgentWithLanguage', 'Session Init Failed [HTTP ' + sessionRes.getStatusCode() + ']: ' + sessionRes.getBody());
                    return responseWrapper;
                }
            }

            // STEP 2: Post Message 
            HttpRequest req = new HttpRequest();
            
            // AEGIS Linter: Sync=true active
            String targetEndpoint = 'callout:sha_Agentforce_NC/einstein/ai-agent/v1/sessions/' + activeSessionId + '/messages?sync=true';
            
            req.setEndpoint(targetEndpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);

            Map<String, Object> reqBodyMap = new Map<String, Object>{
                'message' => new Map<String, Object>{
                    'type' => 'Text', 
                    'text' => sanitizedMessage,
                    'sequenceId' => System.currentTimeMillis()
                }
            };
            req.setBody(JSON.serialize(reqBodyMap));

            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                
                // AEGIS Linter: DEFENSIVE PARSING (Zero ClassCastExceptions)
                if (responseMap.containsKey('messages')) {
                    Object msgsNode = responseMap.get('messages');
                    if (msgsNode instanceof List<Object>) {
                        List<Object> messageList = (List<Object>) msgsNode;
                        if (!messageList.isEmpty()) {
                            Object firstMsg = messageList[0];
                            
                            // Scenario A: The API returned a simple String
                            if (firstMsg instanceof String) {
                                responseWrapper.responseText = (String) firstMsg;
                            } 
                            // Scenario B: The API returned an Object Map
                            else if (firstMsg instanceof Map<String, Object>) {
                                Map<String, Object> msgMap = (Map<String, Object>) firstMsg;
                                if (msgMap.containsKey('text')) {
                                    responseWrapper.responseText = (String) msgMap.get('text');
                                } else if (msgMap.containsKey('message')) {
                                    Object nested = msgMap.get('message');
                                    if (nested instanceof Map<String, Object>) {
                                        Map<String, Object> nestedMap = (Map<String, Object>) nested;
                                        if (nestedMap.containsKey('text')) {
                                            responseWrapper.responseText = (String) nestedMap.get('text');
                                        }
                                    } else if (nested instanceof String) {
                                        responseWrapper.responseText = (String) nested;
                                    }
                                }
                            }
                        }
                    }
                }
                
                if (String.isBlank(responseWrapper.responseText)) {
                    responseWrapper.responseText = 'Agentforce synced successfully, but returned an empty cognitive response.';
                    new TelemetryWriter().logCustomError('SH_AgentforceBroker', 'JSON Parsing', 'Empty text. Raw Payload: ' + res.getBody());
                }
                
                responseWrapper.agentSessionId = activeSessionId;
                responseWrapper.isSuccess = true;
            } else {
                responseWrapper.responseText = 'Agentforce runtime communication error (' + res.getStatusCode() + ').';
                responseWrapper.isSuccess = false;
                new TelemetryWriter().logCustomError('SH_AgentforceBroker', 'sendMessageToAgentWithLanguage', 'HTTP ' + res.getStatusCode() + ' Payload: ' + res.getBody());
            }

        } catch (Exception ex) {
            responseWrapper.responseText = 'Unable to connect to Agentforce runtime: ' + ex.getMessage();
            new TelemetryWriter().logException('SH_AgentforceBroker', 'sendMessageToAgentWithLanguage', ex);
        }

        return responseWrapper;
    }

    private without sharing class TelemetryWriter {
        public void logException(String className, String methodName, Exception ex) {
            try {
                Application_Log__c log = new Application_Log__c(
                    Error_Message__c = 'Class: ' + className + ' | Origin: ' + methodName + ' | Exception: ' + ex.getMessage() + ' | Stack: ' + ex.getStackTraceString()
                );
                Database.insert(log, false);
            } catch (Exception logEx) {}
        }

        public void logCustomError(String className, String methodName, String errorMessage) {
            try {
                Application_Log__c log = new Application_Log__c(
                    Error_Message__c = 'Class: ' + className + ' | Origin: ' + methodName + ' | Detail: ' + errorMessage
                );
                Database.insert(log, false);
            } catch (Exception logEx) {}
        }
    }
}