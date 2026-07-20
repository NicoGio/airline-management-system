# ✈️ SKYHIGH AIRLINES - PROJECT CONTEXT & STATE ENGINE (SAVE GAME)

**AEGIS Protocol Version**: 3.1 (Refactored for Header-Line Item Architecture)  
**Current Phase**: Phase 3 - Agentforce AI Orchestration & Frontend E2E Integration  
**Overall Status**: 🟢 GREEN (Backend Transaccional Estable / Pivot Arquitectónico en Consolidación)  
**Target Org API Version**: 66.0 (Spring '26)[cite: 6]  
**Repository Branch**: `origin/main`[cite: 6]  
**Component Prefix**: `sha` (SkyHigh Airlines)[cite: 6]  

---

## 🏛️ 1. ARCHITECTURAL PERSONA & GOVERNANCE DIRECTIVES (A.E.G.I.S.)

* **Role**: Elite Technical Architect & AI Co-Pilot (+10 years CRM Enterprise Experience).
* **The Handbrake Protocol**: Hyper-focus on the CURRENT task. Do not advance to Front-End integration or Agentforce wiring until the underlying database schema and Apex transactional mutations are 100% certified via deterministic testing.[cite: 6]
* **Language Rules**: Strategy and workflow alignment in **Spanish**. Code, XML metadata, logs, and comments strictly in **English**.[cite: 6]
* **Observability Directive**: Absolute zero tolerance for `System.debug`. Operational metrics and handled exceptions must be logged silently into `Application_Log__c`.[cite: 6]

---

## 🎨 2. BRANDING, EXPERIENCE CLOUD & UI IDENTITY

* **Architecture**: Experience Cloud using **Build Your Own (LWR)** template.[cite: 6]
* **Anti-FOUC Strategy**: Critical CSS tokens injected in the Experience Builder Head Markup to prevent layout flickering.[cite: 6]
* **Visual Paradigm**: Immersive Mobile-First Glassmorphism. Dynamic background images are resolved at runtime via standard UI API using CMS Content Keys mapped by Agentforce Platform Events.

---

## 🏗️ 3. PHYSICAL METADATA & DATA MODEL (SSOT - PNR MODEL)

Evolved into a robust Header-Line Item paradigm to support multi-leg itineraries (scales), prevent concurrency deadlocks, and guarantee transaction idempotency.[cite: 4, 6]

### A. Airport__c (Master Location Catalog)
* `IATA_Code__c` (Text, Unique, External ID, Required, Indexed).[cite: 6]
* `Country__c` (Text, Required).[cite: 6]

### B. Flight__c (Commercial Itinerary Header)
* `Flight_Number__c` (Text, Unique, External ID, Required).[cite: 6]

### C. Flight_Segment__c (Operational Leg Inventory & JSON Engine Core)
* `Flight__c` (Lookup to Flight__c).[cite: 6]
* `Origin_Airport__c` (Lookup to Airport__c).[cite: 6]
* `Destination_Airport__c` (Lookup to Airport__c).[cite: 6]
* `Seat_Map_JSON__c` (Long Text Area, 131k chars): Holds the segment cabin layout array as the Single Source of Truth for availability.[cite: 6]

### D. Booking__c (Commercial Transaction Header / PNR)
* `Passenger__c` (Lookup to Account/Contact).
* `Flight__c` (Lookup to Flight__c).[cite: 4]
* `Transaction_Id__c` (Text, Unique, External ID, Required): Idempotency key ensuring financial double-charge protection.[cite: 4, 6]
* `Status__c` (Picklist: Pending, Confirmed, Cancelled).[cite: 6]

### E. Booking_Line_Item__c (Granular Seat Assignment per Leg - NEW)
* `Booking__c` (Master-Detail to Booking__c): Enforces cascade deletion and security inheritance.[cite: 4]
* `Flight_Segment__c` (Lookup to Flight_Segment__c): Maps the specific leg.[cite: 4]
* `Seat_Code__c` (Text): e.g., "12A".[cite: 4, 6]
* `Status__c` (Picklist: Confirmed, Cancelled).

### F. Flight_Snapshot__c (Historical Audit & Data Offloading)
* `Flight_Segment__c` (Lookup to Flight_Segment__c).[cite: 6]
* `Final_Seat_Map__c` (Long Text Area), `Total_Revenue__c` (Currency), `Occupancy_Rate__c` (Percent).[cite: 6]

### G. Application_Log__c (Enterprise Observability)
* `Error_Message__c` (Long Text Area): Consolidated logger field capturing exception context.[cite: 6]

---

## 🛡️ 4. BACKEND ARCHITECTURE & TRANSACTIONAL LOGIC

* **Pessimistic Locking (`FOR UPDATE`)**: The reservation transaction enforces atomic row-level locks on all involved `Flight_Segment__c` records simultaneously to mitigate race conditions during multi-leg purchases.[cite: 4, 6]
* **Lazy Evaluation**: Automated cleaning of expired `Held` seats during fetch operations, supplemented by a nightly cleanup Batch Apex process.[cite: 4, 6]
* **Data Offloading Strategy**: Upon flight closure, operational JSON structures are evaluated to compute final revenue and occupancy, written into the immutable `Flight_Snapshot__c` table, and then purged from the operational segment record to control storage footprint.[cite: 6]

---

## 🏆 5. COMPLETED MILESTONES

- [x] Initial SFDX project setup and Git integration completed.[cite: 1, 6]
- [x] Core schema infrastructure deployed (`Airport__c`, `Flight__c`, `Flight_Segment__c`, `Booking__c`, `Application_Log__c`).[cite: 6]
- [x] Immersive HTML Prototyping for LWR Experience Cloud completed.[cite: 2]
- [x] Agentforce custom platform event communication stream (`Flight_Found__e`) tested.[cite: 5, 6]
- [x] Flight Closure logic (`closeFlightAndGenerateSnapshot`) written inside the core controller.[cite: 6]

---

## 🚀 6. NEXT STEPS FOR PHASE 3 ADVANCEMENT (THE RUNWAY)

1. **Task 1: Metadata Deployment**: Create and deploy the local XML files for the new junction object `Booking_Line_Item__c`, ensuring Custom Tab creation and Guest Profile FLS provision.
2. **Task 2: Transactional Apex Refactoring**: Update `SH_BookingController.confirmPurchase` to accept bulk leg-to-seat mappings, processing the mutation securely by inserting multiple `Booking_Line_Item__c` records under a single `Booking__c` transaction.
3. **Task 3: Testing Suite Upgrades**: Refactor `SH_BookingController_Test.cls` using the native API 66.0 `Assert` class to validate the data offloading metrics accuracy (Meta: 100% Pass Rate).[cite: 6]
4. **Task 4: Prompt Builder Integration**: Map custom fields inside Contact/Account preferences to enhance Agentforce context capabilities.[cite: 6]