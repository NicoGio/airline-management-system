// 1. Definimos la estructura inicial del avión (Matriz JSON)
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

// 2. Instanciamos nuestro objeto Flight__c
Flight__c newFlight = new Flight__c(
    Flight_Number__c = 'FL-0001',
    Seat_Map_JSON_Long__c = initialSeatMap
);

// 3. Insertamos en la base de datos de forma segura
try {
    insert newFlight;
    System.debug('¡Vuelo creado con éxito! ID: ' + newFlight.Id);
} catch (Exception e) {
    System.debug('Error creando el vuelo: ' + e.getMessage());
}