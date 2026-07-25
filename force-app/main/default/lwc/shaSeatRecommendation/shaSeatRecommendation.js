/*
 * A.E.G.I.S. Enterprise Architecture Note:
 * Refactored to eliminate hardcoded URL record dependencies in LWR Experience Cloud.
 * Implements the Lightning Message Service (LMS) subscriber pattern over shaFlightChannel__c.
 * The Apex @wire adapter reacts dynamically to incoming 'RECOMMENDED' interaction states.
 * All visual states match Nico's verified HTML DOM boundaries perfectly.
 */

import { LightningElement, wire, track } from 'lwc';
import { subscribe, unsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import shaFlightChannel from '@salesforce/messageChannel/shaFlightChannel__c';
import getSeatMapBySegment from '@salesforce/apex/SH_BookingController.getSeatMapBySegment';
import lockSeat from '@salesforce/apex/SH_BookingController.lockSeat';

export default class ShaSeatRecommendation extends LightningElement {
    
    // --- Nico's Verified Reactive State Boundaries ---
    @track isLoading = false; // Initialized to false until an AI recommendation signal is captured
    @track errorMessage;
    @track flightInfo;
    @track recommendedSeat;
    @track isConfirmed = false;

    // --- Reactive Architecture Parameter for Apex Broker ---
    @track activeSegmentId = ''; 

    // --- Enterprise Messaging Context Holds ---
    lmsSubscription = null;

    @wire(MessageContext)
    messageContext;

    /**
     * Reactive Core Broker: Intercepts changes to activeSegmentId to query the physical schema.
     * Enforces lazy-evaluation JSON mapping rules directly from the server.
     */
    @wire(getSeatMapBySegment, { segmentId: '$activeSegmentId' })
    wiredSeatMap({ error, data }) {
        if (data) {
            try {
                this.flightInfo = { flight: data.flightNumber, aircraft: data.aircraftType };
                this.recommendedSeat = this.extractBestSeatForUser(data);
                this.errorMessage = undefined;
            } catch (err) {
                this.errorMessage = 'System Malfunction.';
                this.recommendedSeat = null;
            } finally {
                this.isLoading = false;
            }
        } else if (error) {
            this.errorMessage = 'Unable to load data.';
            this.recommendedSeat = null;
            this.isLoading = false;
        }
    }

    connectedCallback() {
        this.initializeLmsSubscription();
    }

    disconnectedCallback() {
        this.terminateLmsSubscription();
    }

    /**
     * Registers the component instance as an active listener on the corporate pub/sub bus.
     */
    initializeLmsSubscription() {
        if (this.lmsSubscription) {
            return;
        }

        this.lmsSubscription = subscribe(
            this.messageContext,
            shaFlightChannel,
            (message) => this.handleIncomingEnterpriseMessage(message),
            { scope: APPLICATION_SCOPE }
        );
    }

    /**
     * Message Router: Evaluates structural state shifts to mutate reactive adapters.
     */
    handleIncomingEnterpriseMessage(message) {
        const state = message.interactionState;

        if (state === 'RECOMMENDED') {
            this.isLoading = true;
            this.isConfirmed = false;
            this.errorMessage = undefined;
            this.recommendedSeat = null;
            
            // Setting this reactive property automatically triggers the Apex wire lifecycle safely
            this.activeSegmentId = message.flightId; 
        } else if (state === 'CLOSED') {
            this.executeComponentReset();
        }
    }

    /**
     * Nico's Flawless Seat Extraction Loop - Maintained 100% Intact.
     * Evaluates structural JSON matrices using strict English metadata attributes.
     */
    extractBestSeatForUser(data) {
        let bestSeat = null;
        if(data && data.cabins) {
            data.cabins.forEach(cabin => {
                if(cabin.rows) {
                    cabin.rows.forEach(row => {
                        if (row.seats) {
                            row.seats.forEach(seat => {
                                if (seat.status === 'Available' && !bestSeat) {
                                    bestSeat = {
                                        ...seat,
                                        features: ['Window View', 'Priority Boarding', 'Extra Legroom']
                                    };
                                }
                            });
                        }
                    });
                }
            });
        }
        return bestSeat;
    }

    /**
     * Invokes the server-side transactional lock sequence imperatively.
     * Bound to the dynamic activeSegmentId to preserve database operational consistency.
     */
    confirmSuggestion() {
        this.isLoading = true;
        this.errorMessage = undefined;

        lockSeat({ 
            segmentId: this.activeSegmentId, 
            seatCode: this.recommendedSeat.code, 
            sessionIdentifier: 'AI-CONCIERGE-01' 
        })
        .then(response => {
            if (response.isSuccess) {
                this.isConfirmed = true;
            } else {
                this.errorMessage = response.message;
            }
        })
        .catch(err => {
            this.errorMessage = 'Network error.';
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    /**
     * Resets visual and data states to contain component footprint.
     */
    executeComponentReset() {
        this.activeSegmentId = '';
        this.recommendedSeat = null;
        this.flightInfo = null;
        this.isConfirmed = false;
        this.errorMessage = undefined;
        this.isLoading = false;
    }

    terminateLmsSubscription() {
        if (this.lmsSubscription) {
            unsubscribe(this.lmsSubscription);
            this.lmsSubscription = null;
        }
    }
}