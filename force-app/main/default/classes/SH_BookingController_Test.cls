/**
 * @description Automated Test Suite for SH_BookingController lifecycle operations.
 *              Validates Temporary Holds, Purchases, Soft-Deletes, Idempotency, and Observability.
 * @author Nico & A.E.G.I.S. Enterprise Architect
 */
@IsTest
private class SH_BookingController_Test {

    @TestSetup
    static void makeData() {
        // Create an active Flight record with a minimal initialized JSON Seat Map matrix
        Flight__c testFlight = new Flight__c(
            Flight_Number__c = 'SH-2026',
            Seat_Map_JSON_Long__c = '{"aircraftType":"Boeing 737","rows":[{"rowNumber":12,"cabinClass":"Economy","seats":[{"seatLetter":"A","status":"AVAILABLE","price":100.0,"heldBySession":null,"holdExpires":null},{"seatLetter":"B","status":"OCCUPIED","price":100.0,"heldBySession":null,"holdExpires":null}]}]}'
        );
        insert testFlight;
    }

    @IsTest
    static void testLockSeatSuccess() {
        Flight__c flight = [SELECT Id FROM Flight__c LIMIT 1];
        
        Test.startTest();
        SH_BookingController.BookingResponse response = SH_BookingController.lockSeat(flight.Id, '12A', 'session_nico_01');
        Test.stopTest();

        System.assertEquals(true, response.isSuccess, 'The temporary seat lock operation must succeed.');
        
        // Verify state mutation inside the JSON database field
        Flight__c updatedFlight = [SELECT Seat_Map_JSON_Long__c FROM Flight__c WHERE Id = :flight.Id];
        System.assert(updatedFlight.Seat_Map_JSON_Long__c.contains('HELD'), 'The target seat node inside the JSON must register as HELD.');
    }

    @IsTest
    static void testConfirmPurchaseAndIdempotencySuccess() {
        Flight__c flight = [SELECT Id FROM Flight__c LIMIT 1];
        String uniqueTxId = 'TX-ID-9999-CONFIRMED';
        String sessionIdentifier = 'session_nico_01';
        
        // Pre-stage the temporary lock required for checkout validation
        SH_BookingController.lockSeat(flight.Id, '12A', sessionIdentifier);

        Test.startTest();
        // Scenario 1: First execution (Happy Path purchase confirmation)
        SH_BookingController.BookingResponse firstResponse = SH_BookingController.confirmPurchase(
            flight.Id, '12A', sessionIdentifier, uniqueTxId
        );

        // Scenario 2: Immediate duplicate request (Idempotency Check)
        SH_BookingController.BookingResponse duplicateResponse = SH_BookingController.confirmPurchase(
            flight.Id, '12A', sessionIdentifier, uniqueTxId
        );
        Test.stopTest();

        // Assertions for core purchase confirmation flow
        System.assertEquals(true, firstResponse.isSuccess, 'The first purchase confirmation attempt must succeed.');
        System.assertNotEquals(null, firstResponse.bookingId, 'A valid persistent booking record Id must be generated.');

        // Verify the Soft Delete assignment states
        Booking__c persistentBooking = [SELECT Status__c FROM Booking__c WHERE Id = :firstResponse.bookingId];
        System.assertEquals('Confirmed', persistentBooking.Status__c, 'The persistent row state must register as Confirmed.');

        // Assertions for Idempotency block engine mechanics
        System.assertEquals(true, duplicateResponse.isSuccess, 'The duplicate call must exit gracefully with success.');
        System.assertEquals('Purchase already completed successfully.', duplicateResponse.message, 'The engine must block duplicated DML executions.');
    }

    @IsTest
    static void testCancelBookingSoftDeleteSuccess() {
        Flight__c flight = [SELECT Id FROM Flight__c LIMIT 1];
        String sessionIdentifier = 'session_nico_01';
        
        // Execute E2E setup to issue a valid purchase ticket
        SH_BookingController.lockSeat(flight.Id, '12A', sessionIdentifier);
        SH_BookingController.BookingResponse purchaseResponse = SH_BookingController.confirmPurchase(
            flight.Id, '12A', sessionIdentifier, 'TX-ID-CANCELLATION-FLOW'
        );

        Test.startTest();
        SH_BookingController.BookingResponse cancelResponse = SH_BookingController.cancelBooking(purchaseResponse.bookingId, '12A');
        Test.stopTest();

        System.assertEquals(true, cancelResponse.isSuccess, 'The cancellation request should process smoothly.');

        // Enforce compliance audit trail validation (Anti-Hard Delete assertion)
        Booking__c auditedBooking = [SELECT Status__c FROM Booking__c WHERE Id = :purchaseResponse.bookingId];
        System.assertEquals('Cancelled', auditedBooking.Status__c, 'The booking record must be preserved and set to Cancelled for auditing.');

        // Verify seat matrix rollback inside the long text database cluster
        Flight__c releasedFlight = [SELECT Seat_Map_JSON_Long__c FROM Flight__c WHERE Id = :flight.Id];
        System.assert(releasedFlight.Seat_Map_JSON_Long__c.contains('AVAILABLE'), 'The target seat node inside the JSON string must revert to AVAILABLE.');
    }

    @IsTest
    static void testConfirmPurchaseAllowsRepurchaseAfterCancellation() {
        Flight__c flight = [SELECT Id FROM Flight__c LIMIT 1];
        String sessionIdentifierNico = 'session_nico_01';
        String reusableTransactionId = 'TX-ID-REUSABLE-101';

        // 1. First Cycle: Lock, Purchase and Logically Cancel the Booking
        SH_BookingController.lockSeat(flight.Id, '12A', sessionIdentifierNico);
        SH_BookingController.BookingResponse originalPurchase = SH_BookingController.confirmPurchase(
            flight.Id, '12A', sessionIdentifierNico, reusableTransactionId
        );
        SH_BookingController.cancelBooking(originalPurchase.bookingId, '12A');

        // 2. Second Cycle: Re-lock the now AVAILABLE seat and attempt purchase with the REUSED Transaction ID
        SH_BookingController.lockSeat(flight.Id, '12A', sessionIdentifierNico);

        Test.startTest();
        SH_BookingController.BookingResponse secondaryPurchase = SH_BookingController.confirmPurchase(
            flight.Id, '12A', sessionIdentifierNico, reusableTransactionId
        );
        Test.stopTest();

        // Architectural Assertions: Enforce that the engine ignored the 'Cancelled' row and issued a new valid Booking
        System.assertEquals(true, secondaryPurchase.isSuccess, 'The purchase validation engine must allow repurchase if previous transactions were logically cancelled.');
        System.assertNotEquals(null, secondaryPurchase.bookingId, 'A brand new persistent record Id must be successfully generated.');
        System.assertNotEquals(originalPurchase.bookingId, secondaryPurchase.bookingId, 'The new booking record must be an entirely separate persistent database row.');

        // Verify both rows coexist cleanly in the database to satisfy the SSOT traceability rule
        List<Booking__c> finalLedgerState = [SELECT Id, Status__c FROM Booking__c WHERE Transaction_Id__c = :reusableTransactionId ORDER BY CreatedDate ASC];
        System.assertEquals(2, finalLedgerState.size(), 'The data ledger must preserve exactly two physical rows for full audit traceability.');
        System.assertEquals('Cancelled', finalLedgerState[0].Status__c, 'The initial transaction row must remain unmutated as Cancelled.');
        System.assertEquals('Confirmed', finalLedgerState[1].Status__c, 'The secondary transaction row must record successfully as Confirmed.');
    }

    @IsTest
    static void testNegativeExceptionWrappersAndObservability() {
        // Pass an intentional invalid record Id format constraint literal to force catch exceptions
        Id fakeFlightId = 'a02000000000001AAA'; 

        Test.startTest();
        SH_BookingController.BookingResponse errorResponse = SH_BookingController.lockSeat(fakeFlightId, '12A', 'session_err_01');
        Test.stopTest();

        // Verify Zero Trust exception wrapping structures
        System.assertEquals(false, errorResponse.isSuccess, 'The operation should fail under invalid data criteria structures.');
        System.assertEquals('SERVER_ERROR', errorResponse.errorCode, 'The return response code must match the generic catch layout.');
        
        // Verify Observability compliance logging engines
        List<Application_Log__c> logs = [SELECT Id, Error_Message__c FROM Application_Log__c];
        System.assert(logs.size() > 0, 'The exception execution must safely insert a persistent record inside Application_Log__c.');
    }
}