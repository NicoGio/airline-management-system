# ✈️ SKYHIGH AIRLINES - PROJECT CONTEXT & STATE ENGINE (SAVE GAME)
AEGIS-PROTOCOL-VERSION: 2.0
CURRENT_STATUS: E2E Backend Inventory Certified (Sign-Off) ➔ Ready for LWC shaSeatPicker
TARGET_ORG_API_VERSION: 66.0 (Spring '26)
REPOSITORY_BRANCH: origin/main (Clean, Committed & Synced)

🏗️ 3. SINGLE SOURCE OF TRUTH (SSOT) DATA MODEL (UPDATED)
A. Flight__c (El Core Operativo)
  - Flight_Number__c (Text, Unique, External ID, Required)
  - Seat_Map_JSON_Long__c (Long Text Area, 131,072 characters)
  - Departure_Airport__c (Lookup to Airport__c, Master-Detail)
  - Arrival_Airport__c (Lookup to Airport__c, Master-Detail)

C. Booking__c (Transacción de Pasajeros)
  - Flight__c (Master-Detail, ControlledByParent)
  - Transaction_Id__c (Text, Unique, External ID, Required)
  - Status__c (Picklist: Pending, Confirmed, Cancelled) ➔ Enforces full compliance audit trail.

✅ 5. COMPLETED MILESTONES (SAVES)
- [x] Baseline Workspace: VS Code configured with Prettier Apex, ESLint, and Apex PMD.
- [x] BRD & TDD Sign-off: Functional requirements and technical design approved.
- [x] DB Schema Deploy: XML metadata for all custom objects physically in the Org.
- [x] Custom Picklist Field Metadata: Deployed Booking__c.Status__c with active FLS permissions.
- [x] E2E Transactional Engine: Built lockSeat, confirmPurchase (with cancellation-aware idempotency), and cancelBooking methods.
- [x] Deterministic Test Suite: Achieved full coverage passing all negative exception and repurchase lifecycle flows in SH_BookingController_Test.
- [x] Git Hygiene: Main branch clean, pushed, and completely synced with origin.

🎯 6. CURRENT MILESTONE & SPECIFIC TASK
Active Sprint: Transitioning to Experience Builder Integration (shaSeatPicker LWC)
- The server layer is 100% sealed and certified. The upcoming task is to start modeling the LWC interface to parse the JSON matrix and render the immersive SVG/Glassmorphism seat picker layout.

📋 7. NEXT STRATEGIC STEPS (THE RUNWAY)
- LWR Layout Injection: Prepare global CSS tokens in the Experience Builder Head Markup to guarantee anti-FOUC immersion.
- shaSeatPicker LWC development: Wire the component asynchronously to read and mutate the strongly typed JSON layout string.