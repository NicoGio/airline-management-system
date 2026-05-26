/**
 * @description Primary JS controller for the SkyHigh Air hero concierge interface.
 *              Handles real-time asynchronous UI state mutations via EMP API.
 * @author Nico & A.E.G.I.S. Enterprise Architect
 */
import { LightningElement, track } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

export default class ShaHeroConcierge extends LightningElement {
    @track isFlightFound = false;
    @track destinationName = '';
    @track cmsContentKey = '';
    @track iataCode = '';

    channelName = '/event/Flight_Found__e';
    subscription = {};

    connectedCallback() {
        this.handleSubscribe();
        this.registerErrorListener();
    }

    disconnectedCallback() {
        this.handleUnsubscribe();
    }

    handleSubscribe() {
        const messageCallback = (response) => {
            // Parse Platform Event payload injected by Agentforce
            const payload = response.data.payload;
            
            this.destinationName = payload.Destination_Name__c;
            this.cmsContentKey = payload.CMS_Content_Key__c;
            this.iataCode = payload.IATA_Code__c;
            
            // Trigger reactive UI mutation to display the Flight Card Modal
            this.isFlightFound = true;
        };

        subscribe(this.channelName, -1, messageCallback).then((response) => {
            this.subscription = response;
        });
    }

    handleUnsubscribe() {
        if (this.subscription) {
            unsubscribe(this.subscription, () => {
                this.subscription = null;
            });
        }
    }

    registerErrorListener() {
        onError((error) => {
            // Silent client-side catch to maintain Zero Debugs policy
            // In a production scenario, this could trigger an Application_Log__c insertion via Apex
            console.error('EMP API streaming error encountered: ', JSON.stringify(error));
        });
    }

    handleCloseModal() {
        // Resets the UI state safely
        this.isFlightFound = false;
    }

    handleProceedToSeatPicker() {
        // Dispatches event to parent container or standard navigation mixin
        this.dispatchEvent(new CustomEvent('seatpicker', {
            detail: { flightId: this.iataCode }
        }));
    }
}