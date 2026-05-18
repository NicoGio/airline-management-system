System.debug('🕵️ STARTING DEEP DIAGNOSTIC 🕵️');
Flight__c flight = [SELECT Id FROM Flight__c WHERE Flight_Number__c = 'FL-0001' LIMIT 1];
Booking__c testBooking = new Booking__c(Flight__c = flight.Id, Transaction_Id__c = 'TEST-123');
insert testBooking;