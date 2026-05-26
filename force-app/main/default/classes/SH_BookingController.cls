/**
 * @description Core controller for SkyHigh Air seat inventory lifecycle.
 * Refactored for Segment-based itinerary management. Now targets Flight_Segment__c 
 * for JSON manipulations to ensure LDV scalability and prevent Asset locking contention.
 * @author A.E.G.I.S. Enterprise Architect
 */
public with sharing class SH_BookingController {

    private static final Integer HOLD_DURATION_MINUTES = 10;

    // =========================================================================
    // WRAPPERS
    // =========================================================================
    public class SeatMapWrapper {
        @AuraEnabled public String aircraftType { get; set; }
        @AuraEnabled public List<RowWrapper> rows { get; set; }
        public SeatMapWrapper() { this.rows = new List<RowWrapper>(); }
    }

    public class RowWrapper {
        @AuraEnabled public Integer rowNumber { get; set; }
        @AuraEnabled public String cabinClass { get; set; } 
        @AuraEnabled public List<SeatDetailWrapper> seats { get; set; }
        public RowWrapper() { this.seats = new List<SeatDetailWrapper>(); }
    }

    public class SeatDetailWrapper {
        @AuraEnabled public String seatLetter { get; set; }
        @AuraEnabled public String status { get; set; } 
        @AuraEnabled public Decimal price { get; set; }
        @AuraEnabled public String heldBySession { get; set; } 
        @AuraEnabled public Datetime holdExpires { get; set; } 
    }

    public class BookingResponse {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String errorCode { get; set; }
        @AuraEnabled public Id bookingId { get; set; }

        public BookingResponse(Boolean isSuccess, String message) {
            this.isSuccess = isSuccess;
            this.message = message;
        }
        
        public BookingResponse(Boolean isSuccess, String message, String errorCode) {
            this.errorCode = errorCode;
            this.message = message;
            this.isSuccess = isSuccess;
        }

        public BookingResponse(Boolean isSuccess, String message, Id bookingId) {
            this.isSuccess = isSuccess;
            this.message = message;
            this.bookingId = bookingId;
        }
    }

    // =========================================================================
    // BUSINESS PROCESS: QUERIES (Read-Only / Cacheable)
    // =========================================================================

    /**
     * @description Retrieves the current seat map status for a specific flight segment.
     * Uses a List query pattern to prevent automatic QueryExceptions if the segment is not found,
     * allowing for graceful error handling via AuraHandledException.
     * @param segmentId The Id of the Flight_Segment__c to query.
     * @return SeatMapWrapper The deserialized cabin configuration.
     */
    @AuraEnabled(cacheable=true)
    public static SeatMapWrapper getSeatMapBySegment(Id segmentId) {
        List<Flight_Segment__c> segments = [
            SELECT Seat_Map_JSON__c 
            FROM Flight_Segment__c 
            WHERE Id = :segmentId 
            LIMIT 1
        ];
        
        if (segments.isEmpty() || String.isBlank(segments[0].Seat_Map_JSON__c)) {
            throw new AuraHandledException('Seat map not found for this segment.');
        }
        
        return (SeatMapWrapper) JSON.deserialize(segments[0].Seat_Map_JSON__c, SeatMapWrapper.class);
    }

    // =========================================================================
    // BUSINESS PROCESS: TEMPORARY LOCKING
    // =========================================================================

    @AuraEnabled
    public static BookingResponse lockSeat(Id segmentId, String seatCode, String sessionIdentifier) {
        ParsedSeat seatInfo = parseSeatCode(seatCode);
        if (!seatInfo.isValid) return new BookingResponse(false, 'Invalid seat format.', 'INVALID_SEAT_FORMAT');

        Savepoint sp = Database.setSavepoint();
        try {
            Flight_Segment__c segment = [
                SELECT Id, Seat_Map_JSON__c 
                FROM Flight_Segment__c 
                WHERE Id = :segmentId 
                FOR UPDATE
            ];
            
            SeatMapWrapper cabinMap = (SeatMapWrapper) JSON.deserialize(segment.Seat_Map_JSON__c, SeatMapWrapper.class);
            SeatDetailWrapper targetSeat = findSeatNode(cabinMap, seatInfo.rowNumber, seatInfo.seatLetter);

            if (targetSeat == null) return new BookingResponse(false, 'Seat does not exist.', 'SEAT_NOT_FOUND');

            if (targetSeat.status == 'HELD' && targetSeat.holdExpires != null && targetSeat.holdExpires < System.now()) {
                targetSeat.status = 'AVAILABLE';
                targetSeat.heldBySession = null;
                targetSeat.holdExpires = null;
            }

            if (targetSeat.status != 'AVAILABLE') {
                return new BookingResponse(false, 'Seat unavailable.', 'SEAT_UNAVAILABLE');
            }

            targetSeat.status = 'HELD';
            targetSeat.heldBySession = sessionIdentifier;
            targetSeat.holdExpires = System.now().addMinutes(HOLD_DURATION_MINUTES);

            segment.Seat_Map_JSON__c = JSON.serialize(cabinMap);
            update segment; 

            return new BookingResponse(true, 'Seat locked.');

        } catch (Exception e) {
            Database.rollback(sp);
            logError('LOCK_SEAT_ERROR | Segment: ' + segmentId + ' | ' + e.getMessage());
            return new BookingResponse(false, 'Locking failed.', 'SERVER_ERROR');
        }
    }

    // =========================================================================
    // BUSINESS PROCESS: PURCHASE CONFIRMATION
    // =========================================================================

    @AuraEnabled
    public static BookingResponse confirmPurchase(Id segmentId, String seatCode, String sessionIdentifier, String transactionId) {
        List<Booking__c> existingBookings = [SELECT Id FROM Booking__c WHERE Transaction_Id__c = :transactionId AND Status__c != 'Cancelled' LIMIT 1];
        if (!existingBookings.isEmpty()) return new BookingResponse(true, 'Already completed.', existingBookings[0].Id);

        Savepoint sp = Database.setSavepoint();
        try {
            Flight_Segment__c segment = [
                SELECT Id, Seat_Map_JSON__c, Flight__c 
                FROM Flight_Segment__c 
                WHERE Id = :segmentId 
                FOR UPDATE
            ];
            
            SeatMapWrapper cabinMap = (SeatMapWrapper) JSON.deserialize(segment.Seat_Map_JSON__c, SeatMapWrapper.class);
            SeatDetailWrapper targetSeat = findSeatNode(cabinMap, parseSeatCode(seatCode).rowNumber, parseSeatCode(seatCode).seatLetter);

            if (targetSeat == null || targetSeat.status != 'HELD' || targetSeat.heldBySession != sessionIdentifier) {
                return new BookingResponse(false, 'Hold expired.', 'HOLD_EXPIRED');
            }

            targetSeat.status = 'OCCUPIED';
            targetSeat.heldBySession = null;
            targetSeat.holdExpires = null;

            segment.Seat_Map_JSON__c = JSON.serialize(cabinMap);
            update segment;

            Booking__c newBooking = new Booking__c(
                Flight__c = segment.Flight__c,
                Transaction_Id__c = transactionId,
                Status__c = 'Confirmed'
            );
            insert newBooking;

            return new BookingResponse(true, 'Issued.', newBooking.Id);

        } catch (Exception e) {
            Database.rollback(sp);
            logError('CONFIRM_PURCHASE_ERROR | Segment: ' + segmentId + ' | ' + e.getMessage());
            return new BookingResponse(false, 'Transaction failed.', 'SERVER_ERROR');
        }
    }

    // =========================================================================
    // BUSINESS PROCESS: CANCELLATION
    // =========================================================================

    @AuraEnabled
    public static BookingResponse cancelBooking(Id bookingId, Id segmentId, String seatCode) {
        Savepoint sp = Database.setSavepoint();
        try {
            Booking__c booking = [SELECT Id, Status__c, Transaction_Id__c FROM Booking__c WHERE Id = :bookingId FOR UPDATE];
            if (booking.Status__c == 'Cancelled') return new BookingResponse(false, 'Already cancelled.', 'ALREADY_CANCELLED');

            Flight_Segment__c segment = [
                SELECT Id, Seat_Map_JSON__c 
                FROM Flight_Segment__c 
                WHERE Id = :segmentId 
                FOR UPDATE
            ];
            
            ParsedSeat seatInfo = parseSeatCode(seatCode);
            SeatMapWrapper cabinMap = (SeatMapWrapper) JSON.deserialize(segment.Seat_Map_JSON__c, SeatMapWrapper.class);
            SeatDetailWrapper targetSeat = findSeatNode(cabinMap, seatInfo.rowNumber, seatInfo.seatLetter);

            if (targetSeat != null && targetSeat.status == 'OCCUPIED') {
                targetSeat.status = 'AVAILABLE';
                segment.Seat_Map_JSON__c = JSON.serialize(cabinMap);
                update segment;
            }

            booking.Status__c = 'Cancelled';
            booking.Transaction_Id__c += '-CNCL';
            update booking;

            return new BookingResponse(true, 'Booking released.');

        } catch (Exception e) {
            Database.rollback(sp);
            logError('CANCEL_BOOKING_ERROR | Booking: ' + bookingId + ' | ' + e.getMessage());
            return new BookingResponse(false, 'Cancellation failed.', 'SERVER_ERROR');
        }
    }

    // =========================================================================
    // HELPERS
    // =========================================================================

    private class ParsedSeat {
        public Integer rowNumber;
        public String seatLetter;
        public Boolean isValid = false;
    }

    private static ParsedSeat parseSeatCode(String seatCode) {
        ParsedSeat result = new ParsedSeat();
        if (String.isBlank(seatCode)) return result;
        System.Pattern seatPattern = System.Pattern.compile('(\\d+)([A-Z])');
        System.Matcher seatMatcher = seatPattern.matcher(seatCode.toUpperCase());
        if (seatMatcher.matches()) {
            result.rowNumber = Integer.valueOf(seatMatcher.group(1));
            result.seatLetter = seatMatcher.group(2);
            result.isValid = true;
        }
        return result;
    }

    private static SeatDetailWrapper findSeatNode(SeatMapWrapper cabinMap, Integer rowNum, String letter) {
        for (RowWrapper row : cabinMap.rows) {
            if (row.rowNumber == rowNum) {
                for (SeatDetailWrapper seat : row.seats) {
                    if (seat.seatLetter.equalsIgnoreCase(letter)) return seat;
                }
            }
        }
        return null;
    }

    private static void logError(String detailedMessage) {
        Application_Log__c errorLog = new Application_Log__c(Error_Message__c = detailedMessage);
        Database.insert(new List<Application_Log__c>{errorLog}, false);
    }
}