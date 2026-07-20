/**
 * @description Automated Framework Verification Suite for SH_BookingController lifecycle operations.
 * Fully optimized for API 66.0 modern Assert syntax and the 3NF PNR data contract layout.
 * @author Nico & A.E.G.I.S. Enterprise Architect & Co-Pilot
 */
@IsTest
private class SH_BookingController_Test {

    @TestSetup
    static void makeData() {
        // 1. Establish core Customer entity
        Account testAcc = new Account(Name = 'SkyHigh Test Customer');
        insert testAcc;

        // 2. Populate operational field catalog infrastructure
        Airport__c departureAirport = new Airport__c(
            IATA_Code__c = 'EZE', City__c = 'Buenos Aires', Country__c = 'Argentina'
        );
        Airport__c arrivalAirport = new Airport__c(
            IATA_Code__c = 'MIA', City__c = 'Miami', Country__c = 'USA'
        );
        insert new List<Airport__c>{ departureAirport, arrivalAirport };

        // 3. Define accurate hierarchical seating layout JSON (cabins -> rows -> seats)
        // Seat 12A is Available, Seat 12B is Occupied initially
        String hierarchicalSeatingMap = '{"flightNumber":"SH-2026","aircraftType":"Boeing 737","cabins":[{"cabinName":"Economy","rows":[{"rowIndex":"12","seats":[{"code":"12A","status":"Available","tier":"Standard","price":150.0,"isWindow":true,"isAisle":false,"heldBySession":null,"holdExpires":null},{"code":"12B","status":"Occupied","tier":"Standard","price":150.0,"isWindow":false,"isAisle":true,"heldBySession":null,"holdExpires":null}]}]}]}';

        // 4. Create Asset record representation
        Asset testAsset = new Asset(
            Name = 'Boeing 737-SkyHigh',
            AccountId = testAcc.Id,
            Cabin_Configuration__c = hierarchicalSeatingMap
        );
        insert testAsset;

        // 5. Create Flight itinerary header boundary
        Flight__c testFlight = new Flight__c(Flight_Number__c = 'SH-2026');
        insert testFlight;

        // 6. Deploy physical Flight Segment with operational inventory mapping
        Flight_Segment__c testSegment = new Flight_Segment__c(
            Flight__c = testFlight.Id,
            Asset__c = testAsset.Id,
            Origin_Airport__c = departureAirport.Id, 
            Destination_Airport__c = arrivalAirport.Id,
            Seat_Map_JSON__c = hierarchicalSeatingMap 
        );
        insert testSegment;
    }

    @IsTest
    static void testGetSeatMapBySegment_Success() {
        Flight_Segment__c segment = [SELECT Id FROM Flight_Segment__c LIMIT 1];
        
        Test.startTest();
        SH_BookingController.SeatMapWrapper wrapper = SH_BookingController.getSeatMapBySegment(segment.Id);
        Test.stopTest();

        Assert.isNotNull(wrapper, 'The seating JSON must be successfully mapped into its wrapper hierarchy.');
    }

    @IsTest
    static void testGetSeatMapBySegment_Failure() {
        Id fakeId = 'a02000000000001AAA'; 
        
        Test.startTest();
        try {
            SH_BookingController.getSeatMapBySegment(fakeId);
            Assert.fail('The controller should have immediately thrown an AuraHandledException upon record absence.');
        } catch (Exception e) {
            Assert.isTrue(e instanceof AuraHandledException, 'The intercepted exception type must map directly to AuraHandledException.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testLockSeatSuccess() {
        Flight_Segment__c segment = [SELECT Id FROM Flight_Segment__c LIMIT 1];
        
        Test.startTest();
        SH_BookingController.BookingResponse response = SH_BookingController.lockSeat(segment.Id, '12A', 'session_nico_01');
        Test.stopTest();

        Assert.isTrue(response.isSuccess, 'The in-memory seating hold assignment transaction must report success.');
        
        Flight_Segment__c updatedSegment = [SELECT Seat_Map_JSON__c FROM Flight_Segment__c WHERE Id = :segment.Id];
        Assert.isTrue(updatedSegment.Seat_Map_JSON__c.contains('Held'), 'The specific seat node state variable must register as Held.');
    }

    @IsTest
    static void testLockSeatFailures() {
        Flight_Segment__c segment = [SELECT Id FROM Flight_Segment__c LIMIT 1];
        
        Test.startTest();
        SH_BookingController.BookingResponse respInvalidFormat = SH_BookingController.lockSeat(segment.Id, '', 'session_nico_01');
        SH_BookingController.BookingResponse respNotFound = SH_BookingController.lockSeat(segment.Id, '99Z', 'session_nico_01');
        SH_BookingController.BookingResponse respOccupied = SH_BookingController.lockSeat(segment.Id, '12B', 'session_nico_01');
        Test.stopTest();

        Assert.isFalse(respInvalidFormat.isSuccess, 'Empty inputs must fail processing criteria.');
        Assert.areEqual('INVALID_SEAT_FORMAT', respInvalidFormat.errorCode);

        Assert.isFalse(respNotFound.isSuccess, 'Non-existent matrices nodes must throw error bounds.');
        Assert.areEqual('SEAT_NOT_FOUND', respNotFound.errorCode);

        Assert.isFalse(respOccupied.isSuccess, 'Pre-occupied rows cannot accept temporary locks.');
        Assert.areEqual('SEAT_UNAVAILABLE', respOccupied.errorCode);
    }

    @IsTest
    static void testConfirmPurchaseAndIdempotencySuccess() {
        Flight_Segment__c segment = [SELECT Id FROM Flight_Segment__c LIMIT 1];
        Flight__c flight = [SELECT Id FROM Flight__c LIMIT 1];
        Account customer = [SELECT Id FROM Account LIMIT 1];
        String uniqueTxId = 'TX-ID-9999-CONFIRMED';
        String sessionIdentifier = 'session_nico_01';
        
        SH_BookingController.lockSeat(segment.Id, '12A', sessionIdentifier);

        // Map assignments data contract arrays matching new method signature
        SH_BookingController.LegAssignment leg = new SH_BookingController.LegAssignment();
        leg.segmentId = segment.Id;
        leg.seatCode = '12A';
        List<SH_BookingController.LegAssignment> assignments = new List<SH_BookingController.LegAssignment>{ leg };

        Test.startTest();
        SH_BookingController.BookingResponse firstResponse = SH_BookingController.confirmPurchase(
            flight.Id, customer.Id, assignments, sessionIdentifier, uniqueTxId
        );
        SH_BookingController.BookingResponse duplicateResponse = SH_BookingController.confirmPurchase(
            flight.Id, customer.Id, assignments, sessionIdentifier, uniqueTxId
        );
        Test.stopTest();

        Assert.isTrue(firstResponse.isSuccess, 'Initial execution run must process successfully.');
        Assert.isTrue(duplicateResponse.isSuccess, 'Subsequent duplicate hits must complete gracefully via idempotency check logic.');
        Assert.areEqual(firstResponse.bookingId, duplicateResponse.bookingId, 'Both transactions must reference the same PNR record identifier.');
    }

    @IsTest
    static void testCancelBookingLifecycle() {
        Flight_Segment__c segment = [SELECT Id FROM Flight_Segment__c LIMIT 1];
        Flight__c flight = [SELECT Id FROM Flight__c LIMIT 1];
        Account customer = [SELECT Id FROM Account LIMIT 1];
        String sessionIdentifier = 'session_nico_01';
        
        SH_BookingController.lockSeat(segment.Id, '12A', sessionIdentifier);
        
        SH_BookingController.LegAssignment leg = new SH_BookingController.LegAssignment();
        leg.segmentId = segment.Id;
        leg.seatCode = '12A';
        List<SH_BookingController.LegAssignment> assignments = new List<SH_BookingController.LegAssignment>{ leg };

        SH_BookingController.BookingResponse purchaseResponse = SH_BookingController.confirmPurchase(
            flight.Id, customer.Id, assignments, sessionIdentifier, 'TX-ID-CANCELLATION'
        );

        Test.startTest();
        SH_BookingController.BookingResponse cancelResponse = SH_BookingController.cancelBooking(purchaseResponse.bookingId);
        SH_BookingController.BookingResponse duplicateCancel = SH_BookingController.cancelBooking(purchaseResponse.bookingId);
        Test.stopTest();

        Assert.isTrue(cancelResponse.isSuccess, 'The core inventory cancellation statement must pass.');
        Assert.isFalse(duplicateCancel.isSuccess, 'Re-submitting cancellation steps against inactive lines must be blocked.');
        Assert.areEqual('ALREADY_CANCELLED', duplicateCancel.errorCode);

        Flight_Segment__c releasedSegment = [SELECT Seat_Map_JSON__c FROM Flight_Segment__c WHERE Id = :segment.Id];
        Assert.isTrue(releasedSegment.Seat_Map_JSON__c.contains('Available'), ' Purged configurations nodes must correctly revert state back to Available.');
    }

    @IsTest
    static void testCloseFlightAndGenerateSnapshot_Success() {
        Flight_Segment__c segment = [SELECT Id, Seat_Map_JSON__c FROM Flight_Segment__c LIMIT 1];
        
        Test.startTest();
        SH_BookingController.BookingResponse response = SH_BookingController.closeFlightAndGenerateSnapshot(segment.Id);
        Test.stopTest();

        Assert.isTrue(response.isSuccess, 'The data aggregation engine closure task must return successfully.');
        Assert.areEqual('SNAPSHOT_CREATED', response.errorCode);

        // Confirm operational data table offloading
        Flight_Segment__c updatedSegment = [SELECT Seat_Map_JSON__c FROM Flight_Segment__c WHERE Id = :segment.Id];
        Assert.isNull(updatedSegment.Seat_Map_JSON__c, 'Operational text block fields must be completely truncated to preserve storage size.');

        // Validate analytical calculations integrity
        List<Flight_Snapshot__c> snapshots = [
            SELECT Final_Seat_Map__c, Total_Revenue__c, Occupancy_Rate__c 
            FROM Flight_Snapshot__c 
            WHERE Flight_Segment__c = :segment.Id
        ];
        Assert.areEqual(1, snapshots.size(), 'Exactly one database audit tracking entry must be generated.');
        Assert.isNotNull(snapshots[0].Final_Seat_Map__c, 'The historical map backup reference field cannot remain empty.');
        
        // Mathematical matrix analysis: 2 total seats, 1 Occupied (Standard tier = $150.00) -> 50.00% Occupancy, $150.00 Revenue
        Assert.areEqual(50.00, snapshots[0].Occupancy_Rate__c, 'Occupancy calculation calculation does not match actual allocation.');
        Assert.areEqual(150.00, snapshots[0].Total_Revenue__c, 'Financial revenue revenue total deviates from business rules expectations.');
    }

    @IsTest
    static void testCloseFlightAndGenerateSnapshot_Negative() {
        Test.startTest();
        SH_BookingController.BookingResponse errorResponse = SH_BookingController.closeFlightAndGenerateSnapshot(null);
        Test.stopTest();

        Assert.isFalse(errorResponse.isSuccess, 'Transactions containing parameter violations must return failure status blocks.');
        Assert.areEqual('SERVER_ERROR', errorResponse.errorCode);

        // Verify that the error is successfully written into the telemetry database table
        List<Application_Log__c> logs = [SELECT Id, Error_Message__c FROM Application_Log__c];
        Assert.isFalse(logs.isEmpty(), 'A secure monitoring log telemetry entry must be written silently.');
        Assert.isTrue(logs[0].Error_Message__c.contains('SNAPSHOT_GENERATION_ERROR'), 'The persistent error context must be captured inside the log message.');
    }
}