/**
 * @description Idempotent Purge & Seed Script for SkyHigh Airlines (Strict Schema Compliance).
 * Clears existing mock data to ensure a clean slate, then provisions infrastructure.
 * @author Nico & A.E.G.I.S. Co-Pilot
 */

// ==========================================
// PHASE 1: DATA PURGE (Anti-Clutter Lifecycle)
// ==========================================

List<Booking__c> oldBookings = [SELECT Id FROM Booking__c LIMIT 10000];
if (!oldBookings.isEmpty()) Database.delete(oldBookings, false);

List<Flight_Segment__c> oldSegments = [SELECT Id FROM Flight_Segment__c LIMIT 10000];
if (!oldSegments.isEmpty()) Database.delete(oldSegments, false);

List<Flight__c> oldFlights = [SELECT Id FROM Flight__c LIMIT 10000];
if (!oldFlights.isEmpty()) Database.delete(oldFlights, false);

// Purge old Airport infrastructure nodes[cite: 6]
List<Airport__c> oldAirports = [SELECT Id FROM Airport__c LIMIT 10000];
if (!oldAirports.isEmpty()) Database.delete(oldAirports, false);

List<Application_Log__c> oldLogs = [SELECT Id FROM Application_Log__c LIMIT 10000];
if (!oldLogs.isEmpty()) Database.delete(oldLogs, false);


// ==========================================
// PHASE 2: FRESH DATA PROVISIONING (Seeding)
// ==========================================

// 1. Create the Physical Airports (Infrastructure Nodes) - Satisfying Country__c requirement[cite: 6]
Airport__c originNode = new Airport__c(
    Name = 'Buenos Aires Ministro Pistarini',
    IATA_Code__c = 'EZE',
    Country__c = 'Argentina'
);
Airport__c destNode = new Airport__c(
    Name = 'Tokyo Haneda International',
    IATA_Code__c = 'HND',
    Country__c = 'Japan'
);
insert new List<Airport__c>{ originNode, destNode };

// 2. Create the Flight Header Contract[cite: 4, 6]
Flight__c flightHeader = new Flight__c(
    Flight_Number__c = 'SH-100'
);
insert flightHeader;

// 3. Generate the core Seat Map Matrix Data Contract[cite: 4]
String sampleSeatMap = '{' +
    '"flightNumber": "SH-100",' +
    '"aircraftType": "Boeing 787-9",' +
    '"cabins": [' +
        '{' +
            '"cabinName": "Economy Class",' +
            '"rows": [' +
                '{' +
                    '"rowIndex": 20,' +
                    '"seats": [' +
                        '{ "code": "20A", "status": "Available", "tier": "Standard" },' +
                        '{ "code": "20B", "status": "Available", "tier": "Standard" },' +
                        '{ "code": "20C", "status": "Available", "tier": "Standard" }' +
                    ']' +
                '}' +
            ']' +
        '}' +
    ']' +
'}';

// 4. Create the Flight Segment linking actual Salesforce IDs[cite: 4, 6]
Flight_Segment__c tokyoSegment = new Flight_Segment__c(
    Flight__c = flightHeader.Id,
    Origin_Airport__c = originNode.Id,     
    Destination_Airport__c = destNode.Id,  
    Seat_Map_JSON__c = sampleSeatMap
);
insert tokyoSegment;

// Log initialization success[cite: 4]
Application_Log__c infoLog = new Application_Log__c(
    Error_Message__c = 'System Provisioning: Successfully executed data purge and seeded fresh EZE-HND relational flight path.'
);
insert infoLog;