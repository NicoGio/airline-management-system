/*
 * A.E.G.I.S. Enterprise Architecture Note:
 * Refactored shaSeatPicker to consume active segments via the shaFlightChannel__c bus.
 * Parses JSON cabin payloads reactively from getSeatMapBySegment Apex configurations.
 * Implements an asynchronous short-polling retry loop (Max 5, 3000ms) to manage row collisions.
 * Variable syntax and logging architectural conventions set strictly to English.
 */

import { LightningElement, wire, track } from 'lwc';
import { subscribe, unsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import shaFlightChannel from '@salesforce/messageChannel/shaFlightChannel__c';
import getSeatMapBySegment from '@salesforce/apex/SH_BookingController.getSeatMapBySegment';
import lockSeat from '@salesforce/apex/SH_BookingController.lockSeat';

export default class ShaSeatPicker extends LightningElement {
    
    // --- Reactive Layout Controls ---
    @track isLoading = false;
    @track isComponentVisible = false;
    @track errorMessage;
    @track flightInfo = { flight: '', aircraft: '' };
    @track isConfirmed = false;
    
    // --- Seating Matrix Structures ---
    @track cabinLayoutRows = [];
    @track selectedSeatCode = '';

    // --- Technical Resilience Constants ---
    MAX_RETRIES = 5;
    RETRY_DELAY_MS = 3000;

    // --- State & Subscription Binders ---
    activeSegmentId = '';
    lmsSubscription = null;
    rawServerPayload = null;

    @wire(MessageContext)
    messageContext;

    /**
     * Context Broker Wire: Reacts to alterations on activeSegmentId to capture the operational matrix.
     */
    @wire(getSeatMapBySegment, { segmentId: '$activeSegmentId' })
    wiredSeatMap({ error, data }) {
        if (data) {
            this.rawServerPayload = data;
            this.processServerSeatConfiguration(data);
        } else if (error) {
            this.errorMessage = 'Unable to load real-time seating configuration data from server.';
            this.isLoading = false;
        }
    }

    connectedCallback() {
        this.establishLmsListenerChannel();
    }

    disconnectedCallback() {
        this.terminateLmsListenerChannel();
    }

    establishLmsListenerChannel() {
        if (this.lmsSubscription) return;

        this.lmsSubscription = subscribe(
            this.messageContext,
            shaFlightChannel,
            (message) => this.evaluateIncomingWorkspaceState(message),
            { scope: APPLICATION_SCOPE }
        );
    }

    /**
     * Evaluates state keys from the bus to trigger component initialization.
     */
    evaluateIncomingWorkspaceState(message) {
        const state = message.interactionState;

        if (state === 'SHOW_SEATS') {
            this.isLoading = true;
            this.isConfirmed = false;
            this.errorMessage = undefined;
            this.selectedSeatCode = '';
            this.activeSegmentId = message.flightId;
            this.isComponentVisible = true;
        } else if (state === 'CLOSED') {
            this.shutdownComponentWorkspace();
        }
    }

    /**
     * Maps the serialized database schema fields into an active responsive array layout.
     */
    processServerSeatConfiguration(data) {
        try {
            this.flightInfo = { flight: data.flightNumber, aircraft: data.aircraftType };
            
            if (data.cabins) {
                this.cabinLayoutRows = data.cabins.map(cabin => ({
                    name: cabin.cabinName,
                    rows: cabin.rows.map(row => ({
                        index: row.rowIndex,
                        seats: row.seats.map(seat => {
                            const isOccupied = seat.status === 'Occupied';
                            const isSelected = seat.code === this.selectedSeatCode;
                            
                            // Dynamic Class Mapping Substitution (Client-Side Visual Logic Directive)
                            let baseStyle = 'w-10 h-10 text-xs font-black rounded-lg transition-all border flex items-center justify-center ';
                            if (isOccupied) {
                                baseStyle += 'bg-gray-800/60 border-gray-700 text-gray-500 cursor-not-allowed opacity-40';
                            } else if (isSelected) {
                                baseStyle += 'bg-[#00A86B] border-[#00A86B] text-white shadow-lg shadow-green-500/30 scale-105';
                            } else {
                                baseStyle += 'bg-white/15 border-white/30 hover:bg-white/30 text-white cursor-pointer';
                            }

                            return {
                                code: seat.code,
                                isOccupied: isOccupied,
                                isDisabled: isOccupied || this.isConfirmed,
                                computedStyleClass: baseStyle
                            };
                        })
                    }))
                }));
                this.errorMessage = undefined;
            }
        } catch (err) {
            this.errorMessage = 'Fatal breakdown processing internal cabin JSON strings.';
        } finally {
            this.isLoading = false;
        }
    }

    handleSeatSelectionClick(event) {
        if (this.isConfirmed) return;
        this.selectedSeatCode = event.currentTarget.dataset.code;
        // Force evaluation refresh across the data grid nodes
        this.processServerSeatConfiguration(this.rawServerPayload);
    }

    /**
     * Resilient Transaction Trigger: Executes a deterministic short-polling retry flow upon race conditions.
     */
    async processTransactionHoldRequest() {
        this.isLoading = true;
        this.errorMessage = undefined;
        
        let currentAttemptCount = 0;
        let operationSucceeded = false;

        while (currentAttemptCount < this.MAX_RETRIES && !operationSucceeded) {
            currentAttemptCount++;
            try {
                const response = await lockSeat({
                    segmentId: this.activeSegmentId,
                    seatCode: this.selectedSeatCode,
                    sessionIdentifier: 'UI-SEAT-PICKER-01'
                });

                if (response && response.isSuccess) {
                    this.isConfirmed = true;
                    operationSucceeded = true;
                } else {
                    if (currentAttemptCount < this.MAX_RETRIES) {
                        await this.executeShortPollingDelay(this.RETRY_DELAY_MS);
                    } else {
                        this.errorMessage = response.message || 'This seat is proving popular! Please try again or select another spot.';
                    }
                }
            } catch (networkError) {
                if (currentAttemptCount < this.MAX_RETRIES) {
                    await this.executeShortPollingDelay(this.RETRY_DELAY_MS);
                } else {
                    this.errorMessage = 'Network transaction timeout. Row-level synchronization failed.';
                }
            }
        }
        
        this.isLoading = false;
    }

    executeShortPollingDelay(ms) {
        return new Promise(resolve => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(resolve, ms);
        });
    }

    shutdownComponentWorkspace() {
        this.isComponentVisible = false;
        this.activeSegmentId = '';
        this.selectedSeatCode = '';
        this.cabinLayoutRows = [];
        this.isConfirmed = false;
        this.errorMessage = undefined;
        this.isLoading = false;
        this.rawServerPayload = null;
    }

    terminateLmsListenerChannel() {
        if (this.lmsSubscription) {
            unsubscribe(this.lmsSubscription);
            this.lmsSubscription = null;
        }
    }

    // --- Reactive UI Condition Getters ---
    get selectedSeatLabel() {
        return this.selectedSeatCode || 'None';
    }

    get isSubmitDisabled() {
        return !this.selectedSeatCode || this.isConfirmed;
    }
}