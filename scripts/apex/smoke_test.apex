// ==========================================
// SKYHIGH AIRLINES - INTEGRATION SMOKE TEST
// ==========================================

System.debug('🧹 CLEANING UP PREVIOUS TEST DATA...');
// Delete old test bookings and flights to prevent Unique Constraint (External ID) errors
List<Booking__c> oldBookings = [SELECT Id FROM Booking__c WHERE Transaction_Id__c = 'TEST-123'];
if (!oldBookings.isEmpty()) { delete oldBookings; }

List<Flight__c> oldFlights = [SELECT Id FROM Flight__c WHERE Flight_Number__c = 'FL-0001'];
if (!oldFlights.isEmpty()) { delete oldFlights; }


System.debug('🛫 STEP 1: DEFINING SEAT MAP INITIAL MATRIX (JSON)...');
String initialSeatMap = '{' +
    '"flightId": "FL-0001",' +
    '"rows": [' +
        '{ "rowNumber": 1, "seats": [' +
            '{ "code": "1A", "status": "AVAILABLE", "class": "FIRST" },' +
            '{ "code": "1B", "status": "AVAILABLE", "class": "FIRST" },' +
            '{ "code": "1C", "status": "OCCUPIED",  "class": "FIRST" }' +
        ']},' +
        '{ "rowNumber": 2, "seats": [' +
            '{ "code": "2A", "status": "AVAILABLE", "class": "ECONOMY" },' +
            '{ "code": "2B", "status": "AVAILABLE", "class": "ECONOMY" },' +
            '{ "code": "2C", "status": "AVAILABLE", "class": "ECONOMY" }' +
        ']}' +
    ']' +
'}';


System.debug('🛠️ STEP 2: INSTANTIATING & INSERTING FLIGHT__C...');
Flight__c newFlight = new Flight__c(
    Flight_Number__c = 'FL-0001',
    Seat_Map_JSON_Long__c = initialSeatMap
);

try {
    insert newFlight;
    System.debug('✅ Flight record inserted successfully! ID: ' + newFlight.Id);
} catch (Exception e) {
    System.debug('❌ Error inserting flight: ' + e.getMessage());
}


System.debug('🕵️ STEP 3: EXECUTE TRANSACTION VIA SH_BOOKINGCONTROLLER 🕵️');
// Fetch the fresh flight record
Flight__c flight = [SELECT Id FROM Flight__c WHERE Flight_Number__c = 'FL-0001' LIMIT 1];

// Invoke our controller using the precise Envelope Pattern structure
SH_BookingController.BookingResponse response = SH_BookingController.reserveSeat(
    flight.Id, 
    '2B', 
    'TEST-123'
);

// Verify the transaction outcome
System.debug('📊 RESPONSE SUCCESS: ' + response.isSuccess);
System.debug('💬 RESPONSE MESSAGE: ' + response.message);
if(response.errorCode != null) {
    System.debug('⚠️ RESPONSE ERROR CODE: ' + response.errorCode);
}