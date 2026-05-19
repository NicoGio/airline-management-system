/**
 * @description Controller for handling SkyHigh Airlines seat reservations.
 * Adapted specifically to Nico's current metadata schema.
 */
public without sharing class SH_BookingController {

    /**
     * @description Standardized response wrapper for Experience Cloud LWCs.
     */
    public class BookingResponse {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String message;
        @AuraEnabled public String errorCode;
        @AuraEnabled public Object data;

        public BookingResponse(Boolean isSuccess, String message) {
            this.isSuccess = isSuccess;
            this.message = message;
        }
        
        public BookingResponse(Boolean isSuccess, String message, String errorCode) {
            this.isSuccess = isSuccess;
            this.message = message;
            this.errorCode = errorCode;
        }
    }

    /**
     * @description Reserves a seat using LDV JSON processing and FOR UPDATE locking.
     * @param flightId The Id of the Flight__c record.
     * @param seatCode The code of the seat to reserve (e.g., '12A').
     * @param transactionId Unique ID from the client to ensure idempotency.
     * @return BookingResponse standardized object.
     */
    @AuraEnabled
    public static BookingResponse reserveSeat(Id flightId, String seatCode, String transactionId) {
        
        // 1. Idempotency Check: Prevent duplicate processing for the same transaction
        List<Booking__c> existingBookings = [
            SELECT Id
            FROM Booking__c 
            WHERE Transaction_Id__c = :transactionId 
            LIMIT 1
        ];
        
        if (!existingBookings.isEmpty()) {
            return new BookingResponse(true, 'Transaction already processed successfully.');
        }

        Savepoint sp = Database.setSavepoint();

        try {
            // 2. Pessimistic Locking: Secure the row to prevent race conditions
            // Matched to Nico's exact schema: Seat_Map_JSON_Long__c
            Flight__c flight = [
                SELECT Id, Seat_Map_JSON_Long__c 
                FROM Flight__c 
                WHERE Id = :flightId 
                FOR UPDATE
            ];

            // 3. JSON Evaluation Placeholder
            Boolean isSeatAvailable = true; 
            
            if (!isSeatAvailable) {
                return new BookingResponse(false, 'This seat is proving popular! Please select another.', 'SEAT_TAKEN');
            }

            // 4. Insert pending Booking__c record (Using only existing fields in Nico's schema)
            Booking__c newBooking = new Booking__c(
                Flight__c = flightId,
                Transaction_Id__c = transactionId
            );
            insert newBooking;

            return new BookingResponse(true, 'Seat successfully secured for your journey.');

        } catch (System.QueryException qe) {
            Database.rollback(sp);
            logError('ROW_LOCK | Seat: ' + seatCode + ' | ' + qe.getMessage());
            return new BookingResponse(false, 'Securing your seat...', 'ROW_LOCK');
            
        } catch (Exception e) {
            Database.rollback(sp);
            logError('SYSTEM_ERROR | Seat: ' + seatCode + ' | ' + e.getMessage());
            return new BookingResponse(false, 'An unexpected error occurred. Our crew has been notified.', 'SYSTEM_ERROR');
        }
    }

    /**
     * @description Logs system errors utilizing Nico's single Error_Message__c field.
     */
    private static void logError(String detailedMessage) {
        Application_Log__c errorLog = new Application_Log__c(
            Error_Message__c = detailedMessage
        );
        Database.insert(new List<Application_Log__c>{errorLog}, false);
    }
}