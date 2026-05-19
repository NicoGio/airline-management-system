/**
 * @description Test Data Factory for SkyHigh Airlines.
 * Adheres strictly to Nico's current database schema.
 */
@isTest
public class SH_TestDataFactory {

    /**
     * @description Creates a flight record with a mock seat map JSON.
     * @param flightNumber Unique identifier for the flight.
     * @return Inserted Flight__c record.
     */
    public static Flight__c createTestFlight(String flightNumber) {
        String mockSeatMap = '{' +
            '"flightId": "' + flightNumber + '",' +
            '"rows": [' +
                '{ "rowNumber": 1, "seats": [' +
                    '{ "code": "1A", "status": "AVAILABLE", "class": "FIRST" },' +
                    '{ "code": "1B", "status": "AVAILABLE", "class": "FIRST" }' +
                ']}' +
            ']' +
    	'}';

        Flight__c flight = new Flight__c(
            Flight_Number__c = flightNumber,
            Seat_Map_JSON_Long__c = mockSeatMap
        );
        insert flight;
        return flight;
    }
}