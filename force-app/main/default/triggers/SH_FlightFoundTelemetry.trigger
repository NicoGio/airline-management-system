// SH_FlightFoundTelemetry.trigger
trigger SH_FlightFoundTelemetry on Flight_Found__e (after insert) {
    // AEGIS Protocol 1.4: Enterprise Observability
    List<Application_Log__c> telemetryLogs = new List<Application_Log__c>();

    for (Flight_Found__e eventPayload : Trigger.new) {
        // Strict adherence to physical metadata availability (Error_Message__c only)
        telemetryLogs.add(new Application_Log__c(
            Error_Message__c = 'AEGIS TELEMETRY | Flight_Found__e Published Payload: ' + JSON.serialize(eventPayload)
        ));
    }

    if (!telemetryLogs.isEmpty()) {
        // Partial success handling to prevent event bus blockages
        Database.insert(telemetryLogs, false);
    }
}