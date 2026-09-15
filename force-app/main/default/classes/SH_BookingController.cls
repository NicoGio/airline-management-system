/**
 * @description Master Inventory & Seat Controller for SkyHigh Airlines.
 *              Scoped to Task 6 (Date refinement, Segment lookup, Seat locking).
 *              Methods are non-cacheable to enable structured exception logging.
 */
public with sharing class SH_BookingController {

    private static final Integer HOLD_TTL_MINUTES = 10;
    private static final String SEAT_STATUS_AVAILABLE = 'AVAILABLE';
    private static final String SEAT_STATUS_HELD = 'HELD';

    /**
     * @description Dynamic query endpoint for in-modal date range refinement.
     *              Imperative execution allows Application_Log__c persistence on error.
     */
    @AuraEnabled
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
                       Origin_Airport__r.City__c,
                       Destination_Airport__r.IATA_Code__c, 
                       Destination_Airport__r.City__c,
                       Flight__r.Flight_Number__c,
                       Flight__r.Status__c,
                       Seat_Map_JSON__c,
                       Asset__r.Name
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
            logException('getSegmentsByDateRange', ex);
            throw new AuraHandledException('Unable to query flight segments: ' + ex.getMessage());
        }
    }

    /**
     * @description Retrieves single recommended flight segment details.
     *              Imperative execution allows Application_Log__c persistence on error.
     */
    @AuraEnabled
    public static Flight_Segment__c getRecommendedSegment(Id segmentId) {
        try {
            if (segmentId == null) {
                throw new AuraHandledException('Segment ID is required.');
            }

            List<Flight_Segment__c> segments = [
                SELECT Id,
                       Departure_Time__c,
                       Arrival_Time__c,
                       Seat_Map_JSON__c,
                       Origin_Airport__r.IATA_Code__c,
                       Origin_Airport__r.City__c,
                       Destination_Airport__r.IATA_Code__c,
                       Destination_Airport__r.City__c,
                       Flight__r.Flight_Number__c,
                       Flight__r.Status__c,
                       Asset__r.Name
                FROM Flight_Segment__c
                WHERE Id = :segmentId
                WITH USER_MODE
                LIMIT 1
            ];

            if (segments.isEmpty()) {
                throw new AuraHandledException('Flight segment not found for ID: ' + segmentId);
            }

            return segments[0];
        } catch (Exception ex) {
            logException('getRecommendedSegment', ex);
            throw new AuraHandledException('Unable to load segment details: ' + ex.getMessage());
        }
    }

    /**
     * @description Pessimistic seat locking endpoint on Flight_Segment__c.
     *              Enforces Lazy Hold evaluation without invalid ORDER BY on FOR UPDATE.
     */
    @AuraEnabled
    public static SeatLockResult lockSeat(Id segmentId, String seatCode, String sessionIdentifier) {
        SeatLockResult result = new SeatLockResult();
        try {
            if (segmentId == null || String.isBlank(seatCode)) {
                result.isSuccess = false;
                result.message = 'Segment ID and seat code are required.';
                return result;
            }

            List<Flight_Segment__c> segments = [
                SELECT Id, Seat_Map_JSON__c 
                FROM Flight_Segment__c 
                WHERE Id = :segmentId 
                WITH USER_MODE 
                LIMIT 1 
                FOR UPDATE
            ];

            if (segments.isEmpty()) {
                result.isSuccess = false;
                result.message = 'Flight segment not found.';
                return result;
            }

            Flight_Segment__c segment = segments[0];
            if (String.isBlank(segment.Seat_Map_JSON__c)) {
                result.isSuccess = false;
                result.message = 'Seat map inventory is not initialized.';
                return result;
            }

            Map<String, Object> seatMapData = (Map<String, Object>) JSON.deserializeUntyped(segment.Seat_Map_JSON__c);
            List<Object> rows = (List<Object>) seatMapData.get('rows');
            Boolean seatFound = false;
            Boolean lockAcquired = false;
            Datetime currentGmtTime = Datetime.now();

            if (rows != null) {
                for (Object rowObj : rows) {
                    Map<String, Object> rowMap = (Map<String, Object>) rowObj;
                    List<Object> seats = (List<Object>) rowMap.get('seats');
                    if (seats == null) continue;

                    for (Object seatObj : seats) {
                        Map<String, Object> seatMap = (Map<String, Object>) seatObj;
                        String currentCode = (String) seatMap.get('code');
                        if (currentCode == null && seatMap.containsKey('seatLetter')) {
                            currentCode = String.valueOf(rowMap.get('rowNumber')) + (String) seatMap.get('seatLetter');
                        }

                        if (currentCode == seatCode) {
                            seatFound = true;
                            String currentStatus = (String) seatMap.get('status');
                            String holdExpiresStr = (String) seatMap.get('holdExpires');

                            Boolean isHoldExpired = false;
                            if (currentStatus == SEAT_STATUS_HELD && String.isNotBlank(holdExpiresStr)) {
                                try {
                                    Datetime holdExpiresTime = (Datetime) JSON.deserialize('"' + holdExpiresStr + '"', Datetime.class);
                                    if (holdExpiresTime <= currentGmtTime) {
                                        isHoldExpired = true;
                                    }
                                } catch (Exception parseEx) {
                                    isHoldExpired = true;
                                }
                            }

                            if (currentStatus == SEAT_STATUS_AVAILABLE || isHoldExpired) {
                                seatMap.put('status', SEAT_STATUS_HELD);
                                seatMap.put('holdSessionId', sessionIdentifier);
                                seatMap.put('holdExpires', currentGmtTime.addMinutes(HOLD_TTL_MINUTES).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
                                lockAcquired = true;
                            }
                            break;
                        }
                    }
                    if (seatFound) break;
                }
            }

            if (!seatFound) {
                result.isSuccess = false;
                result.message = 'Seat code ' + seatCode + ' does not exist on this aircraft.';
                return result;
            }

            if (!lockAcquired) {
                result.isSuccess = false;
                result.message = 'Seat ' + seatCode + ' is already occupied or held by another customer.';
                return result;
            }

            segment.Seat_Map_JSON__c = JSON.serialize(seatMapData);
            update as user segment;

            result.isSuccess = true;
            result.message = 'Seat successfully locked and reserved.';
            return result;
        } catch (Exception ex) {
            logException('lockSeat', ex);
            result.isSuccess = false;
            result.message = 'Failed to lock seat: ' + ex.getMessage();
            return result;
        }
    }

    /**
     * @description Centralized SSOT exception logger mapped to Application_Log__c.Error_Message__c.
     */
    private static void logException(String methodName, Exception ex) {
        String logPayload = String.format(
            'Class: SH_BookingController | Method: {0} | Type: {1} | Message: {2} | StackTrace: {3}',
            new List<String>{
                methodName,
                ex.getTypeName(),
                ex.getMessage(),
                ex.getStackTraceString()
            }
        );

        Application_Log__c log = new Application_Log__c(
            Error_Message__c = logPayload
        );
        Database.insert(log, false, AccessLevel.SYSTEM_MODE);
    }

    public class SeatLockResult {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String message;
    }
}