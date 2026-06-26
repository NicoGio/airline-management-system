/*
 * A.E.G.I.S. Architecture Note:
 * CMS Resolution Handler added. Automatically converts raw CMS Content Keys (MCZ...) 
 * into valid LWR delivery URLs for both the background and the brand logo.
 * Grounded to match verified physical repository schemas (Flight_Found__e).
 */

import { LightningElement, api, track } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
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

    // Hardcoded mock user session representing current browser state for multi-user isolation
    currentSessionId = 'session_nico_01';

    channelName = '/event/Flight_Found__e';
    subscription = {};

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
        
        // If it's already a valid URL or path containing slashes, return as is
        if (contentKey.includes('/')) {
            // Prepend basePath if it's a relative CMS path to prevent routing issues in LWR
            if (contentKey.startsWith('/cms')) {
                const base = basePath.endsWith('/') ? basePath.slice(0, -1) : basePath;
                return `${base}${contentKey}`;
            }
            return contentKey;
        }
        
        // If it's a raw Content Key (e.g., MCZ...), construct the standard LWR delivery path
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
        
        // Return undefined to allow the CSS Unsplash fallback to take over
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
                
                // Mapping using the exact fields deployed in your Flight_Found__e metadata repository
                this.selectedDestinationCode = payload.Destination_Code__c;
                
                if (payload.CMS_Content_Key__c) {
                    this.activeBackgroundUrl = payload.CMS_Content_Key__c;
                }
                
                // UX Fluidity boundaries: Dynamically alter hero narratives context
                this.currentHeroTitle = `Journey to ${this.selectedDestinationCode}`;
                this.currentHeroSubtitle = 'Your AI Concierge has prepared your itinerary.';
                this.showFlightCard = true;
            }
        };

        subscribe(this.channelName, -1, messageCallback).then((response) => {
            this.subscription = response;
        });
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
    }

    proceedToSeatPicker() {
        this.dispatchEvent(new CustomEvent('seatselection', {
            detail: { destination: this.selectedDestinationCode }
        }));
    }

    disconnectedCallback() {
        unsubscribe(this.subscription, () => {});
    }
}