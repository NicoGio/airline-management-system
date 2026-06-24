/**
 * @description Core controller for SkyHigh Air seat inventory lifecycle.
 * Streamlined for Agentforce AI Concierge (Attribute-based, non-spatial)
 * and upgraded to support LDV Historical Snapshots.
 * @author A.E.G.I.S. Enterprise Architect
 */
public with sharing class SH_BookingController {

    private static final Integer HOLD_DURATION_MINUTES = 10;

    // =========================================================================
    // AI-OPTIMIZED DATA CONTRACT WRAPPERS
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
        
        // Semantic attributes for Agentforce reasoning
        @AuraEnabled public Boolean isWindow { get; set; } 
        @AuraEnabled public Boolean isAisle { get; set; }  
        
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
            SeatDetailWrapper targetSeat = findSeatNode(cabinMap, seatCode);

            if (targetSeat == null || targetSeat.status != 'Held' || targetSeat.heldBySession != sessionIdentifier) {
                return new BookingResponse(false, 'Hold expired.', 'HOLD_EXPIRED');
            }

            targetSeat.status = 'Occupied';
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
            
            SeatMapWrapper cabinMap = (SeatMapWrapper) JSON.deserialize(segment.Seat_Map_JSON__c, SeatMapWrapper.class);
            SeatDetailWrapper targetSeat = findSeatNode(cabinMap, seatCode);

            if (targetSeat != null && targetSeat.status == 'Occupied') {
                targetSeat.status = 'Available';
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
    // BUSINESS PROCESS: FLIGHT CLOSURE & SNAPSHOT ARCHIVING
    // =========================================================================

    @AuraEnabled
    public static BookingResponse closeFlightAndGenerateSnapshot(Id segmentId) {
        Savepoint sp = Database.setSavepoint();
        try {
            // 1. Lock the segment
            Flight_Segment__c segment = [
                SELECT Id, Seat_Map_JSON__c 
                FROM Flight_Segment__c 
                WHERE Id = :segmentId 
                FOR UPDATE
            ];

            if (String.isBlank(segment.Seat_Map_JSON__c)) {
                return new BookingResponse(false, 'Seat Map is empty. Snapshot aborted.', 'EMPTY_MAP');
            }

            // 2. Deserialize the AI-Optimized JSON to calculate metrics
            SeatMapWrapper cabinMap = (SeatMapWrapper) JSON.deserialize(segment.Seat_Map_JSON__c, SeatMapWrapper.class);
            
            Decimal totalSeats = 0;
            Decimal occupiedSeats = 0;
            Decimal simulatedRevenue = 0;

            // Iterate over the AI semantic attributes
            if (cabinMap.cabins != null) {
                for (CabinWrapper cabin : cabinMap.cabins) {
                    if (cabin.rows == null) continue;
                    for (RowWrapper row : cabin.rows) {
                        if (row.seats == null) continue;
                        for (SeatDetailWrapper seat : row.seats) {
                            totalSeats++;
                            if (seat.status == 'Occupied') {
                                occupiedSeats++;
                                // MVP Revenue Logic based on semantic tier
                                if (seat.tier == 'Premium') simulatedRevenue += 500;
                                else if (seat.tier == 'Economy' || seat.tier == 'Standard') simulatedRevenue += 150;
                            }
                        }
                    }
                }
            }

            // 3. Calculate exact Occupancy Rate
            Decimal occupancyRate = 0;
            if (totalSeats > 0) {
                occupancyRate = (occupiedSeats / totalSeats) * 100;
            }

            // 4. Create the Historical Snapshot
            Flight_Snapshot__c snapshot = new Flight_Snapshot__c(
                Flight_Segment__c = segment.Id,
                Final_Seat_Map__c = segment.Seat_Map_JSON__c,
                Occupancy_Rate__c = occupancyRate.setScale(2),
                Total_Revenue__c = simulatedRevenue
            );
            insert snapshot;

            // 5. Data Offloading: Free up live DB space (LDV strategy)
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
    // HELPERS
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