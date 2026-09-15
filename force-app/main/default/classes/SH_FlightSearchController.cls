/**
 * @description Enterprise controller to dynamically query flight segments by date range.
 *              Adheres to AEGIS Protocol V5.1 (User-mode security & SSOT telemetry).
 */
public with sharing class SH_FlightSearchController {

    @AuraEnabled(cacheable=true)
    public static List<Flight_Segment__c> getSegmentsByDateRange(
        String originIata,
        String destinationIata,
        Date departureDate,
        Date returnDate
    ) {
        try {
            if (String.isBlank(originIata) || String.isBlank(destinationIata) || departureDate == null) {
                throw new AuraHandledException('Invalid search parameters provided.');
            }

            Datetime startOfDay = Datetime.newInstanceGmt(departureDate, Time.newInstance(0, 0, 0, 0));
            Datetime endOfDay = returnDate != null 
                ? Datetime.newInstanceGmt(returnDate, Time.newInstance(23, 59, 59, 999))
                : Datetime.newInstanceGmt(departureDate, Time.newInstance(23, 59, 59, 999));

            return [
                SELECT Id, 
                       Departure_Time__c, 
                       Arrival_Time__c, 
                       Origin_Airport__r.IATA_Code__c, 
                       Destination_Airport__r.IATA_Code__c,
                       Flight__r.Flight_Number__c,
                       Flight__r.Status__c,
                       Seat_Map_JSON__c
                FROM Flight_Segment__c
                WHERE Origin_Airport__r.IATA_Code__c = :originIata
                  AND Destination_Airport__r.IATA_Code__c = :destinationIata
                  AND Departure_Time__c >= :startOfDay
                  AND Departure_Time__c <= :endOfDay
                  AND Flight__r.Status__c = 'Scheduled'
                WITH USER_MODE
                ORDER BY Departure_Time__c ASC
                LIMIT 50
            ];
        } catch (Exception ex) {
            String consolidatedLog = String.format(
                'Class: {0} | Method: {1} | Error: {2} | StackTrace: {3}',
                new List<String>{
                    'SH_FlightSearchController',
                    'getSegmentsByDateRange',
                    ex.getMessage(),
                    ex.getStackTraceString()
                }
            );

            Application_Log__c log = new Application_Log__c(
                Error_Message__c = consolidatedLog
            );
            Database.insert(log, false, AccessLevel.SYSTEM_MODE);
            
            throw new AuraHandledException('Unable to retrieve flight segments: ' + ex.getMessage());
        }
    }
}