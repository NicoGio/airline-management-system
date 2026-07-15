/**
 * @description Invocable Action for Agentforce to search available flights based on segment lookups.
 * @author Nico & A.E.G.I.S. Co-Pilot
 * @date June 2026
 */
public with sharing class SH_AgentFlightAction {

    public class FlightRequest {
        @InvocableVariable(required=true description='IATA Code for the origin airport (e.g., EZE)')
        public String originIata;

        @InvocableVariable(required=true description='IATA Code for the destination airport (e.g., HND)')
        public String destinationIata;

        @InvocableVariable(required=true description='Unique session identifier from the Experience Cloud chat context')
        public String sessionId;
    }

    public class FlightResult {
        @InvocableVariable(description='Indicates if a matching flight path was found and published')
        public Boolean isSuccess;

        @InvocableVariable(description='User-friendly message returned to the AI agent')
        public String responseMessage;
    }

    @InvocableMethod(label='Search and Route Flights by Vibe' description='Queries active flight segments and notifies the LWR UI via Platform Events')
    public static List<FlightResult> searchAndRouteFlights(List<FlightRequest> requests) {
        List<FlightResult> results = new List<FlightResult>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        FlightRequest req = requests[0];
        FlightResult res = new FlightResult();
        res.isSuccess = false;

        try {
            // Zero Trust: Enforce explicit FLS and Object-Level security checks before execution
            if (!Schema.sObjectType.Flight_Segment__c.isAccessible() || 
                !Schema.sObjectType.Airport__c.isAccessible() ||
                !Schema.sObjectType.Flight_Found__e.isAccessible()) {
                res.responseMessage = 'Security enforcement failed: Insufficient permissions to query or publish flights.';
                return new List<FlightResult>{ res };
            }

            // Clean inputs to mitigate potential SOQL Injection vulnerabilities
            String sanitizedOrigin = String.escapeSingleQuotes(req.originIata.trim().toUpperCase());
            String sanitizedDest = String.escapeSingleQuotes(req.destinationIata.trim().toUpperCase());

            // Grounded SOQL: Querying through Lookups utilizing parent relationship references (SSoT)
            List<Flight_Segment__c> activeSegments = [
                SELECT Id, Flight__c, Origin_Airport__c, Destination_Airport__c, Origin_Airport__r.IATA_Code__c, Destination_Airport__r.IATA_Code__c
                FROM Flight_Segment__c
                WHERE Origin_Airport__r.IATA_Code__c = :sanitizedOrigin 
                AND Destination_Airport__r.IATA_Code__c = :sanitizedDest
                WITH USER_MODE
                LIMIT 1
            ];

            if (!activeSegments.isEmpty()) {
                Flight_Segment__c targetedSegment = activeSegments[0];

                // Instantiate our custom Platform Event
                Flight_Found__e flightEvent = new Flight_Found__e();
                flightEvent.Flight_Id__c = targetedSegment.Flight__c; 
                flightEvent.Destination_Code__c = sanitizedDest;
                flightEvent.Session_Id__c = req.sessionId;

                // Publish Event Bus Message securely
                Database.SaveResult eventResult = EventBus.publish(flightEvent);

                if (eventResult.isSuccess()) {
                    res.isSuccess = true;
                    res.responseMessage = 'Flight matching route ' + sanitizedOrigin + '-' + sanitizedDest + ' successfully identified and routed to UI.';
                } else {
                    res.responseMessage = 'Failed to broadcast flight event to the UI bus.';
                }
            } else {
                res.responseMessage = 'No available flight segments found matching the criteria: ' + sanitizedOrigin + ' to ' + sanitizedDest + '.';
            }

        } catch (Exception ex) {
            res.responseMessage = 'An internal systemic error occurred while processing the flight routing request.';
            
            try {
                Application_Log__c errorLog = new Application_Log__c();
                errorLog.Error_Message__c = 'Class: SH_AgentFlightAction | Method: searchAndRouteFlights' 
                                          + ' | Error: ' + ex.getMessage() 
                                          + ' | Stack: ' + ex.getStackTraceString();
                
                Database.insert(errorLog, false);
            } catch (Exception logEx) {
                // Fail-safe
            }
        }

        results.add(res);
        return results;
    }
}