/**
 * @description Core controller for SkyHigh Airlines seat inventory lifecycle.
 *              Handles Temporary Locking, Purchase Confirmation, and Cancellations.
 *              Enforces Pessimistic Locking, Idempotency, and Soft-Delete Compliance.
 * @author Nico & A.E.G.I.S. Enterprise Architect
 */
public with sharing class SH_BookingController {

    private static final Integer HOLD_DURATION_MINUTES = 10;

    // =========================================================================
    // APEX JSON ENGINE WRAPPERS (Strongly Typed Schema)
    // =========================================================================

    public class SeatMapWrapper {
        public String aircraftType { get; set; }
        public List<RowWrapper> rows { get; set; }

        public SeatMapWrapper() {
            this.rows = new List<RowWrapper>();
        }
    }

    public class RowWrapper {
        public Integer rowNumber { get; set; }
        public String cabinClass { get; set; } 
        public List<SeatDetailWrapper> seats { get; set; }

        public RowWrapper() {
            this.seats = new List<SeatDetailWrapper>();
        }
    }

    public class SeatDetailWrapper {
        public String seatLetter { get; set; }
        public String status { get; set; } // AVAILABLE, OCCUPIED, HELD
        public Decimal price { get; set; }
        public String heldBySession { get; set; } 
        public Datetime holdExpires { get; set; } 
    }

    // =========================================================================
    // TRANSACTION RESPONSE ENVELOPE (UI Resilience)
    // =========================================================================

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
            this.isSuccess = isSuccess;
            this.errorCode = errorCode;
            this.message = message;
        }

        public BookingResponse(Boolean isSuccess, String message, Id bookingId) {
            this.isSuccess = isSuccess;
            this.message = message;
            this.bookingId = bookingId;
        }
    }

    // =========================================================================
    // BUSINESS PROCESS 1: TEMPORARY LOCKING (PRE-RESERVA)
    // =========================================================================

    /**
     * @description Places a temporary hold on a seat for a restricted timeframe.
     */
    @AuraEnabled
    public static BookingResponse lockSeat(Id flightId, String seatCode, String sessionIdentifier) {
        ParsedSeat seatInfo = parseSeatCode(seatCode);
        if (!seatInfo.isValid) {
            return new BookingResponse(false, 'Invalid seat format specified.', 'INVALID_SEAT_FORMAT');
        }

        Savepoint sp = Database.setSavepoint();
        try {
            Flight__c flight = [SELECT Id, Seat_Map_JSON_Long__c FROM Flight__c WHERE Id = :flightId FOR UPDATE];
            SeatMapWrapper cabinMap = (SeatMapWrapper) JSON.deserialize(flight.Seat_Map_JSON_Long__c, SeatMapWrapper.class);
            SeatDetailWrapper targetSeat = findSeatNode(cabinMap, seatInfo.rowNumber, seatInfo.seatLetter);

            if (targetSeat == null) {
                return new BookingResponse(false, 'The requested seat does not exist.', 'SEAT_NOT_FOUND');
            }

            // Lazy Evaluation of expired holds
            if (targetSeat.status == 'HELD' && targetSeat.holdExpires != null && targetSeat.holdExpires < System.now()) {
                targetSeat.status = 'AVAILABLE';
                targetSeat.heldBySession = null;
                targetSeat.holdExpires = null;
            }

            if (targetSeat.status != 'AVAILABLE') {
                return new BookingResponse(false, 'Seat is currently locked or occupied by another traveler.', 'SEAT_UNAVAILABLE');
            }

            // Apply Temporary Hold
            targetSeat.status = 'HELD';
            targetSeat.heldBySession = sessionIdentifier;
            targetSeat.holdExpires = System.now().addMinutes(HOLD_DURATION_MINUTES);

            flight.Seat_Map_JSON_Long__c = JSON.serialize(cabinMap);
            update flight;

            return new BookingResponse(true, 'Seat successfully locked for ' + HOLD_DURATION_MINUTES + ' minutes.');

        } catch (Exception e) {
            Database.rollback(sp);
            logError('LOCK_SEAT_ERROR | Flight: ' + flightId + ' | Seat: ' + seatCode + ' | ' + e.getMessage());
            return new BookingResponse(false, 'Could not secure temporary lock.', 'SERVER_ERROR');
        }
    }

    // =========================================================================
    // BUSINESS PROCESS 2: PURCHASE CONFIRMATION (COMPRA DEFINITIVA)
    // =========================================================================

    /**
     * @description Transitions a seat from HELD to OCCUPIED and updates the physical Booking__c status.
     *              Enforces cancellation-aware idempotency check.
     */
    @AuraEnabled
    public static BookingResponse confirmPurchase(Id flightId, String seatCode, String sessionIdentifier, String transactionId) {
        // Idempotency Check: Filter out active transactions, ignoring logically cancelled audit records
        List<Booking__c> existingBookings = [
            SELECT Id 
            FROM Booking__c 
            WHERE Transaction_Id__c = :transactionId 
              AND Status__c != 'Cancelled' 
            LIMIT 1
        ];
        
        if (!existingBookings.isEmpty()) {
            return new BookingResponse(true, 'Purchase already completed successfully.', existingBookings[0].Id);
        }

        ParsedSeat seatInfo = parseSeatCode(seatCode);
        Savepoint sp = Database.setSavepoint();

        try {
            Flight__c flight = [SELECT Id, Seat_Map_JSON_Long__c FROM Flight__c WHERE Id = :flightId FOR UPDATE];
            SeatMapWrapper cabinMap = (SeatMapWrapper) JSON.deserialize(flight.Seat_Map_JSON_Long__c, SeatMapWrapper.class);
            SeatDetailWrapper targetSeat = findSeatNode(cabinMap, seatInfo.rowNumber, seatInfo.seatLetter);

            if (targetSeat == null || targetSeat.status != 'HELD' || targetSeat.heldBySession != sessionIdentifier) {
                return new BookingResponse(false, 'Seat hold has expired or session mismatch. Please try again.', 'HOLD_EXPIRED');
            }

            // Transition Node to Final State
            targetSeat.status = 'OCCUPIED';
            targetSeat.heldBySession = null;
            targetSeat.holdExpires = null;

            flight.Seat_Map_JSON_Long__c = JSON.serialize(cabinMap);
            update flight;

            // Secure Audit Trail with 'Confirmed' Picklist state
            Booking__c newBooking = new Booking__c(
                Flight__c = flightId,
                Transaction_Id__c = transactionId,
                Status__c = 'Confirmed'
            );
            insert newBooking;

            return new BookingResponse(true, 'Ticket successfully issued.', newBooking.Id);

        } catch (Exception e) {
            Database.rollback(sp);
            logError('CONFIRM_PURCHASE_ERROR | Transaction: ' + transactionId + ' | ' + e.getMessage());
            return new BookingResponse(false, 'Transaction failed. Financial ledger rolled back safely.', 'SERVER_ERROR');
        }
    }

    // =========================================================================
    // BUSINESS PROCESS 3: CANCELLATION (BORRADO LÓGICO / AUDITABLE)
    // =========================================================================

    /**
     * @description Reverts an OCCUPIED seat back to AVAILABLE and flags the Booking as 'Cancelled'.
     */
    @AuraEnabled
    public static BookingResponse cancelBooking(Id bookingId, String seatCode) {
        Savepoint sp = Database.setSavepoint();
        try {
            // Enforce restrictive query for LDV compliance
            Booking__c targetBooking = [SELECT Id, Flight__c, Status__c FROM Booking__c WHERE Id = :bookingId LIMIT 1];
            ParsedSeat seatInfo = parseSeatCode(seatCode);

            Flight__c flight = [SELECT Id, Seat_Map_JSON_Long__c FROM Flight__c WHERE Id = :targetBooking.Flight__c FOR UPDATE];
            SeatMapWrapper cabinMap = (SeatMapWrapper) JSON.deserialize(flight.Seat_Map_JSON_Long__c, SeatMapWrapper.class);
            SeatDetailWrapper targetSeat = findSeatNode(cabinMap, seatInfo.rowNumber, seatInfo.seatLetter);

            // Revert Seat Inventory state in JSON matrix
            if (targetSeat != null && targetSeat.status == 'OCCUPIED') {
                targetSeat.status = 'AVAILABLE';
                targetSeat.heldBySession = null;
                targetSeat.holdExpires = null;

                flight.Seat_Map_JSON_Long__c = JSON.serialize(cabinMap);
                update flight;
            }

            // Soft Delete Execution: Mutate record status to preserve immutable history
            targetBooking.Status__c = 'Cancelled';
            update targetBooking;

            return new BookingResponse(true, 'Booking cancelled successfully. Seat inventory released.');

        } catch (Exception e) {
            Database.rollback(sp);
            logError('CANCELLATION_ERROR | Booking: ' + bookingId + ' | ' + e.getMessage());
            return new BookingResponse(false, 'Cancellation processing failed.', 'SERVER_ERROR');
        }
    }

    // =========================================================================
    // HELPER CORE UTILITIES
    // =========================================================================

    private class ParsedSeat {
        public Integer rowNumber;
        public String seatLetter;
        public Boolean isValid = false;
    }

    private static ParsedSeat parseSeatCode(String seatCode) {
        ParsedSeat result = new ParsedSeat();
        if (String.isBlank(seatCode)) {
            return result;
        }
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
                    if (seat.seatLetter.equalsIgnoreCase(letter)) {
                        return seat;
                    }
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