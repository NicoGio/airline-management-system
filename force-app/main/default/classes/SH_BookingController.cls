/**
 * @description Core controller for SkyHigh Air seat inventory lifecycle.
 * Evolved to leverage a Header-Line Item transactional PNR pattern,
 * ensuring strict concurrency isolation, anti-deadlock sorting, and data offloading.
 * @author Nico & A.E.G.I.S. Enterprise Architect & Co-Pilot
 */
public with sharing class SH_BookingController {

    private static final Integer HOLD_DURATION_MINUTES = 10;

    // =========================================================================
    // DATA CONTRACT WRAPPERS
    // =========================================================================
    
    public class SeatMapWrapper {
        @AuraEnabled public String flightNumber { get; set; }
        @AuraEnabled public String aircraftType { get; set; }
        @AuraEnabled public List<CabinWrapper> cabins { get; set; }
        
        public SeatMapWrapper() { 
            this.cabins = new List<CabinWrapper>(); 
        }
    }

    public class CabinWrapper {
        @AuraEnabled public String cabinName { get; set; }
        @AuraEnabled public List<RowWrapper> rows { get; set; }
        
        public CabinWrapper() { 
            this.rows = new List<RowWrapper>(); 
        }
    }

    public class RowWrapper {
        @AuraEnabled public String rowIndex { get; set; } 
        @AuraEnabled public List<SeatDetailWrapper> seats { get; set; }
        
        public RowWrapper() { 
            this.seats = new List<SeatDetailWrapper>(); 
        }
    }

    public class SeatDetailWrapper {
        @AuraEnabled public String code { get; set; }
        @AuraEnabled public String status { get; set; } 
        @AuraEnabled public String tier { get; set; }
        @AuraEnabled public Decimal price { get; set; }
        @AuraEnabled public Boolean isWindow { get; set; } 
        @AuraEnabled public Boolean isAisle { get; set; }  
        @AuraEnabled public String heldBySession { get; set; } 
        @AuraEnabled public Datetime holdExpires { get; set; } 
    }

    public class LegAssignment {
        @AuraEnabled public Id segmentId { get; set; }
        @AuraEnabled public String seatCode { get; set; }
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
    // BUSINESS PROCESS: INVENTORY READ (Cacheable / Lazy Evaluation)
    // =========================================================================

    @AuraEnabled(cacheable=true)
    public static SeatMapWrapper getSeatMapBySegment(Id segmentId) {
        List<Flight_Segment__c> segments = [
            SELECT Id, Seat_Map_JSON__c 
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
        if (String.isBlank(seatCode)) return new BookingResponse(false, 'Invalid seat format.', 'INVALID_SEAT_FORMAT');

        Savepoint sp = Database.setSavepoint();
        try {
            Flight_Segment__c segment = [
                SELECT Id, Seat_Map_JSON__c 
                FROM Flight_Segment__c 
                WHERE Id = :segmentId 
                FOR UPDATE
            ];
            
            SeatMapWrapper cabinMap = (SeatMapWrapper) JSON.deserialize(segment.Seat_Map_JSON__c, SeatMapWrapper.class);
            SeatDetailWrapper targetSeat = findSeatNode(cabinMap, seatCode);

            if (targetSeat == null) return new BookingResponse(false, 'Seat does not exist.', 'SEAT_NOT_FOUND');

            // Lazy Evaluation of expired locks to protect performance boundaries
            if (targetSeat.status == 'Held' && targetSeat.holdExpires != null && targetSeat.holdExpires < System.now()) {
                targetSeat.status = 'Available';
                targetSeat.heldBySession = null;
                targetSeat.holdExpires = null;
            }

            if (targetSeat.status != 'Available') {
                return new BookingResponse(false, 'Seat unavailable.', 'SEAT_UNAVAILABLE');
            }

            targetSeat.status = 'Held';
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
    // BUSINESS PROCESS: MULTI-LEG PURCHASE CONFIRMATION (PNR REFACTOR)
    // =========================================================================

    @AuraEnabled
    public static BookingResponse confirmPurchase(Id flightId, Id passengerId, List<LegAssignment> assignments, String sessionIdentifier, String transactionId) {
        // Idempotency check guarding against double payment submissions
        List<Booking__c> existingBookings = [SELECT Id FROM Booking__c WHERE Transaction_Id__c = :transactionId AND Status__c != 'Cancelled' LIMIT 1];
        if (!existingBookings.isEmpty()) return new BookingResponse(true, 'Already completed.', existingBookings[0].Id);

        if (assignments == null || assignments.isEmpty()) return new BookingResponse(false, 'No flight segments selected.', 'MISSING_ASSIGNMENTS');

        // Extract and sort segment IDs alphabetically to systematically prevent database row deadlocks
        List<Id> segmentIds = new List<Id>();
        for (LegAssignment asm : assignments) {
            segmentIds.add(asm.segmentId);
        }
        segmentIds.sort();

        Savepoint sp = Database.setSavepoint();
        try {
            // Pessimistic locking executed in uniform deterministic order
            Map<Id, Flight_Segment__c> segmentMap = new Map<Id, Flight_Segment__c>([
                SELECT Id, Seat_Map_JSON__c, Flight__c 
                FROM Flight_Segment__c 
                WHERE Id IN :segmentIds 
                FOR UPDATE
            ]);

            List<Flight_Segment__c> segmentsToUpdate = new List<Flight_Segment__c>();
            List<Booking_Line_Item__c> linesToInsert = new List<Booking_Line_Item__c>();

            // 1. Create the Commercial PNR Header
            Booking__c newBooking = new Booking__c(
                Flight__c = flightId,
                Passenger__c = passengerId,
                Transaction_Id__c = transactionId,
                Status__c = 'Confirmed'
            );
            insert newBooking;

            // 2. Mutate inventory blocks and generate structural line items
            for (LegAssignment asm : assignments) {
                Flight_Segment__c segment = segmentMap.get(asm.segmentId);
                SeatMapWrapper cabinMap = (SeatMapWrapper) JSON.deserialize(segment.Seat_Map_JSON__c, SeatMapWrapper.class);
                SeatDetailWrapper targetSeat = findSeatNode(cabinMap, asm.seatCode);

                if (targetSeat == null || targetSeat.status != 'Held' || targetSeat.heldBySession != sessionIdentifier) {
                    Database.rollback(sp);
                    return new BookingResponse(false, 'Hold expired or seat assignment mismatch.', 'HOLD_EXPIRED');
                }

                targetSeat.status = 'Occupied';
                targetSeat.heldBySession = null;
                targetSeat.holdExpires = null;
                
                segment.Seat_Map_JSON__c = JSON.serialize(cabinMap);
                segmentsToUpdate.add(segment);

                linesToInsert.add(new Booking_Line_Item__c(
                    Booking__c = newBooking.Id,
                    Flight_Segment__c = segment.Id,
                    Seat_Code__c = asm.seatCode,
                    Status__c = 'Confirmed'
                ));
            }

            update segmentsToUpdate;
            insert linesToInsert;

            return new BookingResponse(true, 'Issued.', newBooking.Id);

        } catch (Exception e) {
            Database.rollback(sp);
            logError('CONFIRM_PURCHASE_ERROR | Tx: ' + transactionId + ' | ' + e.getMessage());
            return new BookingResponse(false, 'Transaction failed.', 'SERVER_ERROR');
        }
    }

    // =========================================================================
    // BUSINESS PROCESS: CANCELLATION ENGINE
    // =========================================================================

    @AuraEnabled
    public static BookingResponse cancelBooking(Id bookingId) {
        Savepoint sp = Database.setSavepoint();
        try {
            Booking__c booking = [SELECT Id, Status__c, Transaction_Id__c FROM Booking__c WHERE Id = :bookingId FOR UPDATE];
            if (booking.Status__c == 'Cancelled') return new BookingResponse(false, 'Already cancelled.', 'ALREADY_CANCELLED');

            List<Booking_Line_Item__c> lines = [
                SELECT Id, Flight_Segment__c, Seat_Code__c, Status__c 
                FROM Booking_Line_Item__c 
                WHERE Booking__c = :bookingId AND Status__c != 'Cancelled'
            ];

            List<Id> segmentIds = new List<Id>();
            for (Booking_Line_Item__c line : lines) {
                segmentIds.add(line.Flight_Segment__c);
            }
            segmentIds.sort();

            Map<Id, Flight_Segment__c> segmentMap = new Map<Id, Flight_Segment__c>([
                SELECT Id, Seat_Map_JSON__c FROM Flight_Segment__c WHERE Id IN :segmentIds FOR UPDATE
            ]);

            List<Flight_Segment__c> segmentsToUpdate = new List<Flight_Segment__c>();

            // Revert all related leg inventory points within the transaction boundary
            for (Booking_Line_Item__c line : lines) {
                Flight_Segment__c segment = segmentMap.get(line.Flight_Segment__c);
                if (segment != null && String.isNotBlank(segment.Seat_Map_JSON__c)) {
                    SeatMapWrapper cabinMap = (SeatMapWrapper) JSON.deserialize(segment.Seat_Map_JSON__c, SeatMapWrapper.class);
                    SeatDetailWrapper targetSeat = findSeatNode(cabinMap, line.Seat_Code__c);
                    if (targetSeat != null && targetSeat.status == 'Occupied') {
                        targetSeat.status = 'Available';
                        segment.Seat_Map_JSON__c = JSON.serialize(cabinMap);
                        segmentsToUpdate.add(segment);
                    }
                }
                line.Status__c = 'Cancelled';
            }

            if (!segmentsToUpdate.isEmpty()) update segmentsToUpdate;
            if (!lines.isEmpty()) update lines;

            // Release unique financial constraint allowing rapid portal rebooking
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
    // BUSINESS PROCESS: FLIGHT CLOSURE & DATA OFFLOADING (LDV STRATEGY)
    // =========================================================================

    @AuraEnabled
    public static BookingResponse closeFlightAndGenerateSnapshot(Id segmentId) {
        Savepoint sp = Database.setSavepoint();
        try {
            Flight_Segment__c segment = [
                SELECT Id, Seat_Map_JSON__c 
                FROM Flight_Segment__c 
                WHERE Id = :segmentId 
                FOR UPDATE
            ];

            if (String.isBlank(segment.Seat_Map_JSON__c)) {
                return new BookingResponse(false, 'Seat Map is empty. Snapshot aborted.', 'EMPTY_MAP');
            }

            SeatMapWrapper cabinMap = (SeatMapWrapper) JSON.deserialize(segment.Seat_Map_JSON__c, SeatMapWrapper.class);
            
            Decimal totalSeats = 0;
            Decimal occupiedSeats = 0;
            Decimal simulatedRevenue = 0;

            if (cabinMap.cabins != null) {
                for (CabinWrapper cabin : cabinMap.cabins) {
                    if (cabin.rows == null) continue;
                    for (RowWrapper row : cabin.rows) {
                        if (row.seats == null) continue;
                        for (SeatDetailWrapper seat : row.seats) {
                            totalSeats++;
                            if (seat.status == 'Occupied') {
                                occupiedSeats++;
                                if (seat.tier == 'Premium') simulatedRevenue += 500;
                                else if (seat.tier == 'Economy' || seat.tier == 'Standard') simulatedRevenue += 150;
                            }
                        }
                    }
                }
            }

            Decimal occupancyRate = 0;
            if (totalSeats > 0) {
                occupancyRate = (occupiedSeats / totalSeats) * 100;
            }

            // 1. Write the permanent analytical audit backup record
            Flight_Snapshot__c snapshot = new Flight_Snapshot__c(
                Flight_Segment__c = segment.Id,
                Final_Seat_Map__c = segment.Seat_Map_JSON__c,
                Occupancy_Rate__c = occupancyRate.setScale(2),
                Total_Revenue__c = simulatedRevenue
            );
            insert snapshot;

            // 2. Data Offloading: Truncate operational string to zero out database footprint overhead
            segment.Seat_Map_JSON__c = null;
            update segment;

            return new BookingResponse(true, 'Flight closed and Snapshot generated successfully.', 'SNAPSHOT_CREATED');

        } catch (Exception e) {
            Database.rollback(sp);
            logError('SNAPSHOT_GENERATION_ERROR | Segment: ' + segmentId + ' | ' + e.getMessage());
            return new BookingResponse(false, 'System Error during flight closure.', 'SERVER_ERROR');
        }
    }

    // =========================================================================
    // SYSTEM HELPERS
    // =========================================================================

    private static SeatDetailWrapper findSeatNode(SeatMapWrapper cabinMap, String seatCodeTarget) {
        if (cabinMap == null || cabinMap.cabins == null) return null;
        
        for (CabinWrapper cabin : cabinMap.cabins) {
            if (cabin.rows == null) continue;
            for (RowWrapper row : cabin.rows) {
                if (row.seats == null) continue; 
                for (SeatDetailWrapper seat : row.seats) {
                    if (seat.code.equalsIgnoreCase(seatCodeTarget)) {
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