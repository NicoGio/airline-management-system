import { LightningElement, wire, track } from 'lwc';
import { subscribe, MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';
import SHA_FLIGHT_CHANNEL from '@salesforce/messageChannel/shaFlightChannel__c';

export default class ShaSeatRecommendation extends LightningElement {
    @wire(MessageContext) messageContext;
    subscription = null;

    @track isPanelActive = false;
    @track flightContext = {};

    badgeLabel = 'RECOMMENDED FLIGHT';
    recommendationBannerText = 'Itinerary customized by Atlas Concierge based on your preferences.';

    // Zero Hardcode Getters: Pure reactive bindings without fallback strings
    get originCode() {
        return this.flightContext.originCode || '';
    }

    get originCity() {
        return this.flightContext.originCity || '';
    }

    get destinationCode() {
        return this.flightContext.destinationCode || '';
    }

    get destinationCity() {
        return this.flightContext.destinationCity || '';
    }

    get flightNumber() {
        return this.flightContext.flightNumber || '';
    }

    get flightType() {
        return this.flightContext.flightType || 'Direct Flight';
    }

    get aircraft() {
        return this.flightContext.aircraft || '';
    }

    get departureTime() {
        return this.flightContext.departureTime || '';
    }

    get hasSeatPreference() {
        return Boolean(
            this.flightContext.seatPreference && 
            typeof this.flightContext.seatPreference === 'string' && 
            this.flightContext.seatPreference.trim() !== ''
        );
    }

    get seatPreferenceDisplay() {
        return `💺 ${this.flightContext.seatPreference}`;
    }

    connectedCallback() {
        this.subscribeToFlightChannel();
    }

    subscribeToFlightChannel() {
        if (!this.subscription) {
            this.subscription = subscribe(
                this.messageContext,
                SHA_FLIGHT_CHANNEL,
                (message) => this.handleFlightBroadcast(message),
                { scope: APPLICATION_SCOPE }
            );
        }
    }

    handleFlightBroadcast(payload) {
        if (!payload) return;

        this.flightContext = { ...this.flightContext, ...payload };

        if (payload.interactionState === 'RECOMMENDED' || payload.interactionState === 'HANDOFF') {
            this.isPanelActive = true;
        }
    }

    closePanel() {
        this.isPanelActive = false;
    }

    proceedToBooking() {
        const bookingPayload = {
            flightSegmentId: this.flightContext.flightId,
            seatPreference: this.hasSeatPreference ? this.flightContext.seatPreference : null
        };
        this.dispatchEvent(new CustomEvent('proceedbooking', { detail: bookingPayload }));
    }
}