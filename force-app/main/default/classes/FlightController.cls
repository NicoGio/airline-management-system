public with sharing class FlightController {

    // ==========================================
    // FASE DE LECTURA (Rápida y delegada al cliente)
    // ==========================================
    @AuraEnabled(cacheable=true)
    public static String getSeatMap(String flightId) {
        Flight__c flight = [
            SELECT Seat_Map_JSON_Long__c 
            FROM Flight__c 
            WHERE Flight_Number__c = :flightId 
            LIMIT 1
        ];
        return flight.Seat_Map_JSON_Long__c;
    }

    // ==========================================
    // FASE DE ESCRITURA (Pessimistic Locking & Idempotencia)
    // ==========================================
    @AuraEnabled
    public static String bookSeat(String flightId, String seatCode, String transactionId) {
        // Establecemos un Savepoint para hacer Rollback total si algo falla
        Savepoint sp = Database.setSavepoint();
        
        try {
            // 1. BLOQUEO PESIMISTA: "FOR UPDATE" bloquea esta fila de la BD 
            // durante los milisegundos que dura esta transacción.
            Flight__c flight = [
                SELECT Id, Seat_Map_JSON_Long__c
                FROM Flight__c
                WHERE Flight_Number__c = :flightId
                FOR UPDATE
            ];

            // 2. PARSEO EN MEMORIA: Transformamos el texto JSON a objetos Apex
            Map<String, Object> seatMap = (Map<String, Object>) JSON.deserializeUntyped(flight.Seat_Map_JSON_Long__c);
            List<Object> rows = (List<Object>) seatMap.get('rows');
            Boolean seatReserved = false;

            // 3. ACTUALIZACIÓN DEL NODO: Buscamos el asiento y lo marcamos ocupado
            for(Object rowObj : rows) {
                Map<String, Object> rowMap = (Map<String, Object>) rowObj;
                List<Object> seats = (List<Object>) rowMap.get('seats');
                
                for(Object seatObj : seats) {
                    Map<String, Object> seatMapNode = (Map<String, Object>) seatObj;
                    if(seatMapNode.get('code') == seatCode) {
                        if(seatMapNode.get('status') == 'AVAILABLE') {
                            seatMapNode.put('status', 'OCCUPIED'); // ¡Reservado!
                            seatReserved = true;
                        }
                        break;
                    }
                }
            }

            // Si otro usuario nos ganó en el milisegundo anterior, abortamos.
            if(!seatReserved) {
                throw new AuraHandledException('El asiento ' + seatCode + ' acaba de ser reservado por otro usuario.');
            }

            // 4. PERSISTENCIA: Volvemos a convertir a String y guardamos el vuelo
            flight.Seat_Map_JSON_Long__c = JSON.serialize(seatMap);
            update flight;

            // 5. IDEMPOTENCIA: Creamos el Booking con su ID de transacción único
            Booking__c newBooking = new Booking__c(
                Flight__c = flight.Id,
                Transaction_Id__c = transactionId
            );
            insert newBooking;

            return 'SUCCESS';

        } catch(QueryException qe) {
            // Error clásico de concurrencia: El sistema no pudo obtener el bloqueo de la fila a tiempo
            logError('FlightController.bookSeat - Lock Timeout', qe.getMessage());
            throw new AuraHandledException('El sistema está procesando muchas reservas simultáneas. Por favor, reintenta.');
        } catch(Exception e) {
            // Error crítico: Deshacemos cualquier cambio a medias (Rollback) y registramos
            Database.rollback(sp);
            logError('FlightController.bookSeat - Critical', e.getMessage());
            throw new AuraHandledException('Error inesperado. Nuestro equipo técnico ha sido notificado automáticamente.');
        }
    }

    // ==========================================
    // OBSERVABILIDAD (Zero Debugs)
    // ==========================================
    private static void logError(String context, String message) {
        Application_Log__c log = new Application_Log__c(
            Error_Message__c = '[' + context + '] ' + message
        );
        insert log;
    }
}