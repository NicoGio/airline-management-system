/**
 * @description Deterministic test suite for SH_FlightSearchController matching physical schema SSOT.
 */
@IsTest
private class SH_FlightSearchController_Test {

    @TestSetup
    static void setupTestData() {
        Airport__c origin = new Airport__c(
            Name = 'Ministro Pistarini',
            IATA_Code__c = 'EZE',
            City__c = 'Buenos Aires',
            Country__c = 'Argentina'
        );
        Airport__c dest = new Airport__c(
            Name = 'Haneda',
            IATA_Code__c = 'HND',
            City__c = 'Tokyo',
            Country__c = 'Japan'
        );
        insert new List<Airport__c>{ origin, dest };

        Flight__c flight = new Flight__c(
            Flight_Number__c = 'SH-104',
            Status__c = 'Scheduled'
        );
        insert flight;

        Date targetDate = Date.today().addDays(10);
        Flight_Segment__c segment = new Flight_Segment__c(
            Flight__c = flight.Id,
            Origin_Airport__c = origin.Id,
            Destination_Airport__c = dest.Id,
            Departure_Time__c = Datetime.newInstanceGmt(targetDate, Time.newInstance(10, 0, 0, 0)),
            Arrival_Time__c = Datetime.newInstanceGmt(targetDate, Time.newInstance(22, 0, 0, 0)),
            Seat_Map_JSON__c = '{"rows":[]}'
        );
        insert segment;
    }

    @IsTest
    static void testGetSegmentsByDateRange_Success() {
        Date targetDate = Date.today().addDays(10);

        Test.startTest();
        List<Flight_Segment__c> results = SH_FlightSearchController.getSegmentsByDateRange('EZE', 'HND', targetDate, null);
        Test.stopTest();

        Assert.isNotNull(results, 'Result list must not be null.');
        Assert.areEqual(1, results.size(), 'Exactly one segment should match query criteria.');
        Assert.areEqual('SH-104', results[0].Flight__r.Flight_Number__c, 'Flight number must match.');
    }

    @IsTest
    static void testGetSegmentsByDateRange_NoResults() {
        Date futureDate = Date.today().addDays(45);

        Test.startTest();
        List<Flight_Segment__c> results = SH_FlightSearchController.getSegmentsByDateRange('EZE', 'HND', futureDate, null);
        Test.stopTest();

        Assert.isNotNull(results, 'Result list must not be null.');
        Assert.isTrue(results.isEmpty(), 'Result list should be empty for dates without segments.');
    }

    @IsTest
    static void testGetSegmentsByDateRange_InvalidParams() {
        Test.startTest();
        try {
            SH_FlightSearchController.getSegmentsByDateRange('', 'HND', null, null);
            Assert.fail('Expected AuraHandledException on invalid parameters.');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'Exception must be caught.');
        }
        Test.stopTest();

        List<Application_Log__c> logs = [
            SELECT Id, Error_Message__c 
            FROM Application_Log__c
        ];
        Assert.isFalse(logs.isEmpty(), 'An Application_Log__c record must be persisted.');
        Assert.isTrue(
            logs[0].Error_Message__c.contains('SH_FlightSearchController'), 
            'Log must contain caller class information in Error_Message__c.'
        );
    }
}