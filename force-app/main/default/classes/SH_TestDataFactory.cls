/**
 * @description Test Data Factory for SkyHigh Airlines.
 * Adheres strictly to Nico's current database schema.
 */
@isTest
public class SH_TestDataFactory {

    /**
     * @description Creates a flight record and its associated segment with a mock seat map JSON.
     * @param flightNumber Unique identifier for the flight.
     * @return Inserted Flight__c record.
     */
    public static Flight__c createTestFlight(String flightNumber) {
        // 1. Create the Flight header record (without non-existent fields)[cite: 4]
        Flight__c flight = new Flight__c(
            Flight_Number__c = flightNumber
        );
        insert flight;

        // 2. Generate mock JSON aligned with our semantic contract (TDD Section 3.1)[cite: 4]
        String mockSeatMap = '{' +
            '"flightNumber": "' + flightNumber + '",' +
            '"aircraftType": "Boeing 737-800",' +
            '"cabins": [' +
                '{' +
                    '"cabinName": "First Class",' +
                    '"rows": [' +
                        '{' +
                            '"rowIndex": 1,' +
                            '"seats": [' +
                                '{ "code": "1A", "status": "Available", "tier": "Premium" },' +
                                '{ "code": "1B", "status": "Available", "tier": "Premium" }' +
                            ']' +
                        '}' +
                    ']' +
                '}' +
            ']' +
        '}';

        // 3. Create the Flight Segment (where the JSON engine actually lives)[cite: 6]
        Flight_Segment__c segment = new Flight_Segment__c(
            Flight__c = flight.Id,
            Seat_Map_JSON__c = mockSeatMap
        );
        insert segment;

        return flight;
    }
}