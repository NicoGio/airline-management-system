/**
 * @description Automated Test Suite for SH_BookingController lifecycle operations.
 * Refactored for the Flight_Segment__c Seat_Map_JSON__c architecture.
 * @author A.E.G.I.S. Enterprise Architect & Co-Pilot
 */
@IsTest
private class SH_BookingController_Test {

    @TestSetup
    static void makeData() {
        // 1. Create an Account for Asset integrity
        Account testAcc = new Account(Name = 'SkyHigh Test Customer');
        insert testAcc;

        // 2. Create Airports
        Airport__c departureAirport = new Airport__c(
            IATA_Code__c = 'EZE', City__c = 'Buenos Aires', Country__c = 'Argentina'
        );
        Airport__c arrivalAirport = new Airport__c(
            IATA_Code__c = 'MIA', City__c = 'Miami', Country__c = 'USA'
        );
        insert new List<Airport__c>{ departureAirport, arrivalAirport };

        // 3. Define the Factory JSON Template
        String initialSeatMap = '{"aircraftType":"Boeing 737","rows":[{"rowNumber":12,"cabinClass":"Economy","seats":[{"seatLetter":"A","status":"AVAILABLE","price":100.0,"heldBySession":null,"holdExpires":null},{"seatLetter":"B","status":"OCCUPIED","price":100.0,"heldBySession":null,"holdExpires":null}]}]}';

        // 4. Create Asset (Static Template)
        Asset testAsset = new Asset(
            Name = 'Boeing 737-SkyHigh',
            AccountId = testAcc.Id,
            Cabin_Configuration__c = initialSeatMap
        );
        insert testAsset;

        // 5. Create Flight Header
        Flight__c testFlight = new Flight__c(Flight_Number__c = 'SH-2026');
        insert testFlight;

        // 6. Create Flight Segment with LIVE JSON Inventory
        Flight_Segment__c testSegment = new Flight_Segment__c(
            Flight__c = testFlight.Id,
            Asset__c = testAsset.Id,
            Origin_Airport__c = departureAirport.Id, 
            Destination_Airport__c = arrivalAirport.Id,
            Seat_Map_JSON__c = initialSeatMap 
        );
        insert testSegment;
    }

    @IsTest
    static void testGetSeatMapBySegment_Success() {
        Flight_Segment__c segment = [SELECT Id FROM Flight_Segment__c LIMIT 1];
        
        Test.startTest();
        SH_BookingController.SeatMapWrapper wrapper = SH_BookingController.getSeatMapBySegment(segment.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrapper, 'The wrapper should be successfully deserialized.');
    }

    @IsTest
    static void testGetSeatMapBySegment_Failure() {
        Id fakeId = 'a02000000000001AAA'; 
        
        Test.startTest();
        try {
            SH_BookingController.getSeatMapBySegment(fakeId);
            System.assert(false, 'Should have thrown an AuraHandledException.');
        } catch (Exception e) {
            System.assert(e instanceof AuraHandledException, 'Exception should be instance of AuraHandledException.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testLockSeatSuccess() {
        Flight_Segment__c segment = [SELECT Id FROM Flight_Segment__c LIMIT 1];
        
        Test.startTest();
        SH_BookingController.BookingResponse response = SH_BookingController.lockSeat(segment.Id, '12A', 'session_nico_01');
        Test.stopTest();

        System.assertEquals(true, response.isSuccess, 'The temporary seat lock operation must succeed.');
        
        Flight_Segment__c updatedSegment = [SELECT Seat_Map_JSON__c FROM Flight_Segment__c WHERE Id = :segment.Id];
        System.assert(updatedSegment.Seat_Map_JSON__c.contains('HELD'), 'The target seat node must register as HELD.');
    }

    @IsTest
    static void testLockSeatFailures() {
        Flight_Segment__c segment = [SELECT Id FROM Flight_Segment__c LIMIT 1];
        
        Test.startTest();
        SH_BookingController.BookingResponse respInvalidFormat = SH_BookingController.lockSeat(segment.Id, 'INVALID', 'session_nico_01');
        SH_BookingController.BookingResponse respNotFound = SH_BookingController.lockSeat(segment.Id, '99Z', 'session_nico_01');
        SH_BookingController.BookingResponse respOccupied = SH_BookingController.lockSeat(segment.Id, '12B', 'session_nico_01');
        Test.stopTest();

        System.assertEquals(false, respInvalidFormat.isSuccess, 'Should fail on invalid format.');
        System.assertEquals('INVALID_SEAT_FORMAT', respInvalidFormat.errorCode);

        System.assertEquals(false, respNotFound.isSuccess, 'Should fail when seat does not exist.');
        System.assertEquals('SEAT_NOT_FOUND', respNotFound.errorCode);

        System.assertEquals(false, respOccupied.isSuccess, 'Should fail when seat is already occupied.');
        System.assertEquals('SEAT_UNAVAILABLE', respOccupied.errorCode);
    }

    @IsTest
    static void testConfirmPurchaseAndIdempotencySuccess() {
        Flight_Segment__c segment = [SELECT Id FROM Flight_Segment__c LIMIT 1];
        String uniqueTxId = 'TX-ID-9999-CONFIRMED';
        String sessionIdentifier = 'session_nico_01';
        
        SH_BookingController.lockSeat(segment.Id, '12A', sessionIdentifier);

        Test.startTest();
        SH_BookingController.BookingResponse firstResponse = SH_BookingController.confirmPurchase(
            segment.Id, '12A', sessionIdentifier, uniqueTxId
        );
        SH_BookingController.BookingResponse duplicateResponse = SH_BookingController.confirmPurchase(
            segment.Id, '12A', sessionIdentifier, uniqueTxId
        );
        Test.stopTest();

        System.assertEquals(true, firstResponse.isSuccess, 'The first purchase must succeed.');
        System.assertEquals(true, duplicateResponse.isSuccess, 'The duplicate call must exit gracefully.');
    }

    @IsTest
    static void testCancelBookingLifecycle() {
        Flight_Segment__c segment = [SELECT Id FROM Flight_Segment__c LIMIT 1];
        String sessionIdentifier = 'session_nico_01';
        
        SH_BookingController.lockSeat(segment.Id, '12A', sessionIdentifier);
        SH_BookingController.BookingResponse purchaseResponse = SH_BookingController.confirmPurchase(
            segment.Id, '12A', sessionIdentifier, 'TX-ID-CANCELLATION'
        );

        Test.startTest();
        SH_BookingController.BookingResponse cancelResponse = SH_BookingController.cancelBooking(purchaseResponse.bookingId, segment.Id, '12A');
        SH_BookingController.BookingResponse duplicateCancel = SH_BookingController.cancelBooking(purchaseResponse.bookingId, segment.Id, '12A');
        Test.stopTest();

        System.assertEquals(true, cancelResponse.isSuccess, 'Cancellation failed.');
        System.assertEquals(false, duplicateCancel.isSuccess, 'Duplicate cancellation should block.');
        System.assertEquals('ALREADY_CANCELLED', duplicateCancel.errorCode);

        Flight_Segment__c releasedSegment = [SELECT Seat_Map_JSON__c FROM Flight_Segment__c WHERE Id = :segment.Id];
        System.assert(releasedSegment.Seat_Map_JSON__c.contains('AVAILABLE'), 'Seat did not revert to AVAILABLE in Segment JSON.');
    }

    @IsTest
    static void testConfirmPurchaseAllowsRepurchaseAfterCancellation() {
        Flight_Segment__c segment = [SELECT Id FROM Flight_Segment__c LIMIT 1];
        String sessionIdentifierNico = 'session_nico_01';
        String reusableTransactionId = 'TX-ID-REUSABLE-101';

        SH_BookingController.lockSeat(segment.Id, '12A', sessionIdentifierNico);
        SH_BookingController.BookingResponse originalPurchase = SH_BookingController.confirmPurchase(
            segment.Id, '12A', sessionIdentifierNico, reusableTransactionId
        );
        SH_BookingController.cancelBooking(originalPurchase.bookingId, segment.Id, '12A');

        SH_BookingController.lockSeat(segment.Id, '12A', sessionIdentifierNico);

        Test.startTest();
        SH_BookingController.BookingResponse secondaryPurchase = SH_BookingController.confirmPurchase(
            segment.Id, '12A', sessionIdentifierNico, reusableTransactionId
        );
        Test.stopTest();

        System.assertEquals(true, secondaryPurchase.isSuccess, 'Repurchase should be allowed after cancellation.');
    }

    @IsTest
    static void testConfirmPurchaseFailsOnSessionMismatch() {
        Flight_Segment__c segment = [SELECT Id FROM Flight_Segment__c LIMIT 1];
        
        SH_BookingController.lockSeat(segment.Id, '12A', 'session_nico_01');

        Test.startTest();
        SH_BookingController.BookingResponse response = SH_BookingController.confirmPurchase(
            segment.Id, '12A', 'session_hijacker_99', 'TX-ID-HIJACK'
        );
        Test.stopTest();

        System.assertEquals(false, response.isSuccess, 'Purchase should fail on session mismatch.');
        System.assertEquals('HOLD_EXPIRED', response.errorCode, 'Error code must be HOLD_EXPIRED.');
    }

    @IsTest
    static void testExceptionHandling() {
        Id fakeSegmentId = 'a02000000000001AAA'; 

        Test.startTest();
        SH_BookingController.BookingResponse errorResponse = SH_BookingController.lockSeat(fakeSegmentId, '12A', 'session_nico_01');
        Test.stopTest();

        System.assertEquals(false, errorResponse.isSuccess, 'Operation should fail for invalid Id.');
        System.assertEquals('SERVER_ERROR', errorResponse.errorCode, 'Error code must be SERVER_ERROR.');
        
        System.assertEquals(1, [SELECT COUNT() FROM Application_Log__c], 'An Application_Log__c record should have been inserted.');
    }

    // --- NEW A.E.G.I.S. TESTS FOR SNAPSHOT & OFFLOADING ---

    @isTest
    static void testCloseFlightAndGenerateSnapshot_Success() {
        // Retrieve the test segment
        Flight_Segment__c segment = [SELECT Id, Seat_Map_JSON__c FROM Flight_Segment__c LIMIT 1];
        
        Test.startTest();
        // Execute the snapshot and offload logic
        SH_BookingController.closeFlightAndGenerateSnapshot(segment.Id);
        Test.stopTest();

        // Assert 1: The JSON field must be cleared (Data Offloading)
        Flight_Segment__c updatedSegment = [SELECT Seat_Map_JSON__c FROM Flight_Segment__c WHERE Id = :segment.Id];
        System.assertEquals(null, updatedSegment.Seat_Map_JSON__c, 'The operational JSON field should be cleared after snapshot creation.');

        // Assert 2: The Snapshot record must exist
        List<Flight_Snapshot__c> snapshots = [SELECT Final_Seat_Map__c FROM Flight_Snapshot__c];
        System.assertEquals(1, snapshots.size(), 'One Flight Snapshot should be generated.');
        System.assertNotEquals(null, snapshots[0].Final_Seat_Map__c, 'The historical JSON must be stored in the snapshot.');
    }

    @isTest
    static void testCloseFlightAndGenerateSnapshot_Negative() {
        // Intentionally pass a null ID to force an exception
        Test.startTest();
        try {
            SH_BookingController.closeFlightAndGenerateSnapshot(null);
            System.assert(false, 'Expected an Exception to be thrown.');
        } catch (Exception e) {
            System.assert(true, 'Exception caught successfully.');
        }
        Test.stopTest();

        // Assert 3: Application_Log__c must be inserted for observability
        List<Application_Log__c> logs = [SELECT Class_Name__c, Method_Name__c FROM Application_Log__c];
        // Note: Ensure your catch block in closeFlightAndGenerateSnapshot inserts an Application_Log__c!
        System.assert(logs.size() > 0, 'An application log must be generated upon failure.');
    }
}