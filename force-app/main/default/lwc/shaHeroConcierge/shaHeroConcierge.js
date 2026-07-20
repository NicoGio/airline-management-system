/*
 * A.E.G.I.S. Architecture Note:
 * CMS Resolution Handler added. Automatically converts raw CMS Content Keys (MCZ...) 
 * into valid LWR delivery URLs for both the background and the brand logo.
 * Grounded to match verified physical repository schemas (Flight_Found__e).
 * Updated to support Enterprise decoupling via Lightning Message Service (LMS).
 */

import { LightningElement, api, track, wire } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { publish, MessageContext } from 'lightning/messageService';
import shaFlightChannel from '@salesforce/messageChannel/shaFlightChannel__c';
import basePath from '@salesforce/community/basePath';

export default class ShaHeroConcierge extends LightningElement {
    
    // --- Experience Builder Configuration Properties ---
    @api brandLogoCmsKey;           
    @api defaultBgImageCmsKey;      
    
    @api navLabel1;
    @api navLabel2;
    @api navLabel3;
    
    @api heroGreetingText;
    @api heroSubGreetingText;
    
    @api agentforceConciergeTitle;

    @api modalTitle;
    @api modalCloseText;
    @api modalSelectSeatText;

    // --- Reactive State ---
    @track currentHeroTitle;
    @track currentHeroSubtitle;
    @track showFlightCard = false;
    @track selectedDestinationCode = '';
    @track activeBackgroundUrl;

    // --- Enterprise Context Holds ---
    activeFlightRecordId = null;
    currentSessionId = 'session_nico_01'; // Hardcoded mock user session representing browser state

    channelName = '/event/Flight_Found__e';
    subscription = {};

    // Wire context broker required by the Lightning Message Service infrastructure
    @wire(MessageContext)
    messageContext;

    connectedCallback() {
        this.currentHeroTitle = this.heroGreetingText;
        this.currentHeroSubtitle = this.heroSubGreetingText;
        this.activeBackgroundUrl = this.defaultBgImageCmsKey;

        this.handleSubscribe();
        this.registerErrorListener();
    }

    // --- Utility: CMS URL Resolver ---
    resolveCmsUrl(contentKey) {
        if (!contentKey) return null;
        
        if (contentKey.includes('/')) {
            if (contentKey.startsWith('/cms')) {
                const base = basePath.endsWith('/') ? basePath.slice(0, -1) : basePath;
                return `${base}${contentKey}`;
            }
            return contentKey;
        }
        
        const base = basePath.endsWith('/') ? basePath.slice(0, -1) : basePath;
        return `${base}/sfsites/c/cms/delivery/media/${contentKey}`;
    }

    // --- Enterprise UI/UX Getters ---
    get backgroundStyle() {
        const bgKey = this.activeBackgroundUrl || this.defaultBgImageCmsKey;
        const resolvedUrl = this.resolveCmsUrl(bgKey);
        
        if (resolvedUrl) {
            return `background-image: linear-gradient(rgba(0, 0, 0, 0.4), rgba(0, 0, 0, 0.7)), url('${resolvedUrl}');`;
        }
        return undefined; 
    }

    get resolvedBrandLogoUrl() {
        return this.resolveCmsUrl(this.brandLogoCmsKey);
    }

    // --- EMP API Logic ---
    handleSubscribe() {
        const messageCallback = (response) => {
            const payload = response.data.payload;
            const broadcastSessionId = payload.Session_Id__c;
            
            // Centralized Routing Validation: Ensure transactional isolation between active guest channels
            if (broadcastSessionId === this.currentSessionId) {
                
                // Extraction of context parameters driven by the physical repository data contract
                this.selectedDestinationCode = payload.Destination_Code__c;
                this.activeFlightRecordId = payload.Flight_Id__c;
                
                if (payload.CMS_Content_Key__c) {
                    this.activeBackgroundUrl = payload.CMS_Content_Key__c;
                }
                
                // UX Fluidity boundaries: Dynamically alter hero narratives context
                this.currentHeroTitle = `Journey to ${this.selectedDestinationCode}`;
                this.currentHeroSubtitle = 'Your AI Concierge has prepared your itinerary.';
                
                // Architectural Shift: Instead of toggling local visibility flags, we broadcast state via LMS
                this.broadcastFlightRecommendation();
            }
        };

        subscribe(this.channelName, -1, messageCallback).then((response) => {
            this.subscription = response;
        });
    }

    /**
     * Publishes the validated flight recommendation payload onto the shared message channel.
     */
    broadcastFlightRecommendation() {
        const messagePayload = {
            flightId: this.activeFlightRecordId,
            destinationCode: this.selectedDestinationCode,
            interactionState: 'RECOMMENDED'
        };
        publish(this.messageContext, shaFlightChannel, messagePayload);
    }

    registerErrorListener() {
        onError((error) => {
            console.error('A.E.G.I.S. EMP API Event Connection Error: ', JSON.stringify(error));
        });
    }

    // --- Event Handlers ---
    closeFlightCard() {
        this.showFlightCard = false;
        this.currentHeroTitle = this.heroGreetingText;
        this.currentHeroSubtitle = this.heroSubGreetingText;
        this.activeBackgroundUrl = this.defaultBgImageCmsKey;

        // Broadcast the closure event to ensure workspace consistency
        publish(this.messageContext, shaFlightChannel, { interactionState: 'CLOSED' });
    }

    proceedToSeatPicker() {
        // Keeps local event dispatch active for compatibility reasons while transferring data
        this.dispatchEvent(new CustomEvent('seatselection', {
            detail: { 
                destination: this.selectedDestinationCode,
                flightId: this.activeFlightRecordId
            }
        }));

        // Broadcast transition phase directly to notify the decoupled shaSeatPicker component
        publish(this.messageContext, shaFlightChannel, {
            flightId: this.activeFlightRecordId,
            destinationCode: this.selectedDestinationCode,
            interactionState: 'SHOW_SEATS'
        });
    }

    disconnectedCallback() {
        unsubscribe(this.subscription, () => {});
    }
}