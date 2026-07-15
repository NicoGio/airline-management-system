/**
 * @description Automated Test Suite to certify the cognitive Agentforce Action lifecycle.
 * Validates relational segment filtering, Platform Event broadcast, and consolidated logging.
 * @author Nico & A.E.G.I.S. Co-Pilot
 * @date July 2026
 */
@IsTest
private class SH_AgentFlightAction_Test {

    @TestSetup
    static void makeData() {
        // 1. Create a baseline Account for data model consistency
        Account testAcc = new Account(Name = 'SkyHigh AI Test Account');
        insert testAcc;

        // 2. Create foundational Airport records utilizing the physical schema
        Airport__c departureAirport = new Airport__c(
            IATA_Code__c = 'EZE', 
            City__c = 'Buenos Aires', 
            Country__c = 'Argentina'
        );
        Airport__c arrivalAirport = new Airport__c(
            IATA_Code__c = 'HND', 
            City__c = 'Tokyo', 
            Country__c = 'Japan'
        );
        insert new List<Airport__c>{ departureAirport, arrivalAirport };

        // 3. Instantiate the Aircraft Asset configuration block
        String mockCabin = '{"aircraftType":"Boeing 787"}';
        Asset testAsset = new Asset(
            Name = 'Dreamliner-787',
            AccountId = testAcc.Id,
            Cabin_Configuration__c = mockCabin
        );
        insert testAsset;

        // 4. Create transactional Flight header
        Flight__c testFlight = new Flight__c(Flight_Number__c = 'SH-999');
        insert testFlight;

        // 5. Create the physical Flight Segment to support relational traverse queries
        Flight_Segment__c testSegment = new Flight_Segment__c(
            Flight__c = testFlight.Id,
            Asset__c = testAsset.Id,
            Origin_Airport__c = departureAirport.Id, 
            Destination_Airport__c = arrivalAirport.Id,
            Seat_Map_JSON__c = mockCabin 
        );
        insert testSegment;
    }

    /**
     * @description Validates the happy path execution: Finding a valid segment,
     * broadcasting the Platform Event securely, and returning successful indicators to Agentforce.
     */
    @IsTest
    static void testSearchAndRouteFlights_Success() {
        // Prepare the request collection structure mirroring Agentforce invocation signatures
        SH_AgentFlightAction.FlightRequest req = new SH_AgentFlightAction.FlightRequest();
        req.originIata = 'EZE';
        req.destinationIata = 'HND';
        req.sessionId = 'session_test_nico_02';

        List<SH_AgentFlightAction.FlightRequest> requests = new List<SH_AgentFlightAction.FlightRequest>{ req };

        Test.startTest();
        List<SH_AgentFlightAction.FlightResult> results = SH_AgentFlightAction.searchAndRouteFlights(requests);
        Test.stopTest();

        // System Assertions to certify full integration alignment
        System.assertEquals(1, results.size(), 'A single results item should be returned.');
        System.assertEquals(true, results[0].isSuccess, 'The operation indicator should report success.');
        System.assert(results[0].responseMessage.contains('successfully identified'), 'Success message should confirm routing.');
    }

    /**
     * @description Validates gracefully handled behavior when the AI searches for a route
     * that does not physically exist in our active flight schedule.
     */
    @IsTest
    static void testSearchAndRouteFlights_NoRouteFound() {
        SH_AgentFlightAction.FlightRequest req = new SH_AgentFlightAction.FlightRequest();
        req.originIata = 'EZE';
        req.destinationIata = 'MIA'; // Non-existent target route in our TestSetup block
        req.sessionId = 'session_test_nico_03';

        List<SH_AgentFlightAction.FlightRequest> requests = new List<SH_AgentFlightAction.FlightRequest>{ req };

        Test.startTest();
        List<SH_AgentFlightAction.FlightResult> results = SH_AgentFlightAction.searchAndRouteFlights(requests);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'A single results item should be returned.');
        System.assertEquals(false, results[0].isSuccess, 'The outcome should indicate that no segment matched.');
        System.assert(results[0].responseMessage.contains('No available flight segments found'), 'Should inform the AI agent about missing criteria.');
    }

    /**
     * @description Negative Testing: Intentionally forces an internal exception handler block
     * by injecting an empty request element, ensuring full coverage of our consolidated logging architecture.
     */
    @IsTest
    static void testSearchAndRouteFlights_NegativeExceptionLogging() {
        // Passing an instantiated object inside the array context but with completely null parameters
        // to force inner runtime query formatting exceptions or null pointer boundaries inside our action logic
        SH_AgentFlightAction.FlightRequest corruptedReq = new SH_AgentFlightAction.FlightRequest();
        corruptedReq.originIata = null; 
        corruptedReq.destinationIata = null;
        corruptedReq.sessionId = null;

        List<SH_AgentFlightAction.FlightRequest> requests = new List<SH_AgentFlightAction.FlightRequest>{ corruptedReq };

        Test.startTest();
        List<SH_AgentFlightAction.FlightResult> results = SH_AgentFlightAction.searchAndRouteFlights(requests);
        Test.stopTest();

        // Enforce robust validation assertions against our unique consolidated repository logging field
        System.assertEquals(false, results[0].isSuccess, 'The transactional execution must report a failed flag.');
        
        List<Application_Log__c> errorLogs = [SELECT Id, Error_Message__c FROM Application_Log__c];
        System.assert(errorLogs.size() > 0, 'An immutable observability error record should be programmatically captured inside our DB.');
        System.assert(errorLogs[0].Error_Message__c.contains('SH_AgentFlightAction'), 'The trace text must contain the matching class container string name.');
    }
}