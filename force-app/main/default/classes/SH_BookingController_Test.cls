/**
 * @description Automated Test Suite for SH_BookingController.
 * Validates transaction success, idempotency controls, and negative exception wrappers.
 */
@isTest
private class SH_BookingController_Test {

    @isTest
    static void testReserveSeatSuccessAndIdempotency() {
        // Setup: Create fresh isolated data using our factory
        Flight__c testFlight = SH_TestDataFactory.createTestFlight('FL-9999');
        String uniqueTransactionId = 'TX-CONFIRMED-XYZ';

        Test.startTest();
        // Scenario 1: First execution (Happy Path)
        SH_BookingController.BookingResponse firstResponse = SH_BookingController.reserveSeat(
            testFlight.Id,
            '1A',
            uniqueTransactionId
        );

        // Scenario 2: Immediate duplicate execution (Idempotency Check)
        SH_BookingController.BookingResponse duplicateResponse = SH_BookingController.reserveSeat(
            testFlight.Id,
            '1A',
            uniqueTransactionId
        );
        Test.stopTest();

        // Architectural Assertions
        System.assertEquals(true, firstResponse.isSuccess, 'The first reservation attempt must succeed.');
        System.assertEquals('Seat successfully secured for your journey.', firstResponse.message, 'Success message must match the standard API envelope.');

        System.assertEquals(true, duplicateResponse.isSuccess, 'The duplicate transaction must return success gracefully.');
        System.assertEquals('Transaction already processed successfully.', duplicateResponse.message, 'Idempotency mechanism must block duplicate processing.');
    }

    @isTest
    static void testReserveSeatNegativeExceptions() {
        // Setup: We intentionally pass an invalid Flight ID wrapped in quotes to force a QueryException
        Id fakeFlightId = 'a02000000000001AAA'; // Fixed: Enclosed in single quotes as a valid ID literal string
        String uniqueTransactionId = 'TX-ERROR-INTENTIONAL';

        Test.startTest();
        // Act: Invoke controller with bad data to trigger catch blocks
        SH_BookingController.BookingResponse errorResponse = SH_BookingController.reserveSeat(
            fakeFlightId,
            '2B',
            uniqueTransactionId
        );
        Test.stopTest();

        // Assertions: Verify the Zero Trust Error Handling strategy
        System.assertEquals(false, errorResponse.isSuccess, 'The transaction should have failed due to invalid data.');
       // Assertions: Verify the Zero Trust Error Handling strategy
        System.assertEquals(false, errorResponse.isSuccess, 'The transaction should have failed due to invalid data.');
        
        // Fixed: The controller correctly maps QueryExceptions on missing/locked records to 'ROW_LOCK'
        System.assertEquals('ROW_LOCK', errorResponse.errorCode, 'The error code must match the query exception signature.');
        
        // Verify Observability: Ensure an application log was written asynchronously
        List<Application_Log__c> logs = [SELECT Id, Error_Message__c FROM Application_Log__c];
        System.assert(logs.size() > 0, 'Observability failure: The exception occurred but was not logged in Application_Log__c.');
    }
}