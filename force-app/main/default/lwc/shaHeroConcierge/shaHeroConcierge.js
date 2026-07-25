/*
 * A.E.G.I.S. Enterprise Architecture Component:
 * Core Orchestrator for the SkyHigh Airlines Experience Cloud LWR Portal.
 * Integrates the Guest Auth Gate pattern using @salesforce/user/isGuest.
 * Preserves pending search context in sessionStorage upon login redirection.
 * Refactored for Zero-Hardcode Agentforce Initial Greeting & Resilient Session Handshake.
 */

import { LightningElement, api, track, wire } from 'lwc';
import isGuestUser from '@salesforce/user/isGuest';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { publish, MessageContext } from 'lightning/messageService';
import shaFlightChannel from '@salesforce/messageChannel/shaFlightChannel__c';
import basePath from '@salesforce/community/basePath';
import sendMessageToAgent from '@salesforce/apex/SH_AgentforceBroker.sendMessageToAgent';

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

    // --- Core Visual Reactive State ---
    @track currentHeroTitle;
    @track currentHeroSubtitle;
    @track showFlightCard = false;
    @track selectedDestinationCode = '';
    @track activeBackgroundUrl;

    // --- Chat Terminal Reactive State ---
    @track userInput = '';
    @track isLoading = false;
    @track chatMessages = [];

    // --- Enterprise Context Trackers ---
    activeFlightRecordId = null;
    currentSessionId = null; 
    messageSequenceCounter = 0;

    channelName = '/event/Flight_Found__e';
    subscription = {};

    @wire(MessageContext)
    messageContext;

    connectedCallback() {
        this.currentHeroTitle = this.heroGreetingText;
        this.currentHeroSubtitle = this.heroSubGreetingText;
        this.activeBackgroundUrl = this.defaultBgImageCmsKey;

        if (!this.agentforceConciergeTitle) {
            this.agentforceConciergeTitle = 'Where is your next story?';
        }

        // AEGIS Linter: Delegating initial greeting to Agentforce (Zero-Hardcode Rule)
        this.initializeDynamicWelcome();
        this.handleSubscribe();
        this.registerErrorListener();
    }

    /**
     * Imperative silent invocation to Apex Broker to fetch LLM-generated greeting.
     */
    initializeDynamicWelcome() {
        this.isLoading = true;
        this.messageSequenceCounter++;
        
        // Render a temporary typing indicator while the LLM computes the greeting
        this.chatMessages = [
            {
                id: this.messageSequenceCounter,
                text: '...', 
                isAgent: true,
                computedClass: 'bubble-agent typing-indicator'
            }
        ];

        // Silent backend trigger using a clean payload contract
        sendMessageToAgent({
            userMessage: 'HELLO_AGENTFORCE_SYSTEM_INIT', 
            sessionId: null // Explicitly forced to null to trigger backend session generation
        })
        .then(result => {
            if (result.isSuccess && result.agentSessionId) {
                this.currentSessionId = result.agentSessionId;
            }

            // Replace typing indicator with the dynamic LLM narrative
            this.chatMessages = [
                {
                    id: this.messageSequenceCounter,
                    text: result.responseText,
                    isAgent: true,
                    computedClass: result.isSuccess ? 'bubble-agent' : 'bubble-error font-semibold'
                }
            ];
        })
        .catch(error => {
            console.error('AEGIS Dynamic Welcome Error:', error);
            this.chatMessages = [
                {
                    id: this.messageSequenceCounter,
                    text: 'System processing error. Unable to connect to the travel network.',
                    isAgent: true,
                    computedClass: 'bubble-error font-semibold'
                }
            ];
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

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

    handleInputChange(event) {
        this.userInput = event.target.value;
    }

    handleInputKeyUp(event) {
        if (event.key === 'Enter' && this.userInput.trim().length > 0 && !this.isLoading) {
            this.processUserMessageSubmission();
        }
    }

    processUserMessageSubmission() {
        if (this.userInput.trim().length === 0 || this.isLoading) return;
        const textPayload = this.userInput.trim();
        this.userInput = ''; 
        this.executeAgentforceServerCall(textPayload);
    }

    executeAgentforceServerCall(userNarrative) {
        this.isLoading = true;

        this.messageSequenceCounter++;
        this.chatMessages = [...this.chatMessages, {
            id: this.messageSequenceCounter,
            text: userNarrative,
            isAgent: false,
            computedClass: 'bubble-user'
        }];

        sendMessageToAgent({
            userMessage: userNarrative,
            sessionId: this.currentSessionId
        })
        .then(result => {
            if (result.isSuccess && result.agentSessionId) {
                this.currentSessionId = result.agentSessionId; 
            }

            this.messageSequenceCounter++;
            this.chatMessages = [...this.chatMessages, {
                id: this.messageSequenceCounter,
                text: result.responseText,
                isAgent: true,
                computedClass: result.isSuccess ? 'bubble-agent' : 'bubble-error font-semibold'
            }];
        })
        .catch(() => {
            this.messageSequenceCounter++;
            this.chatMessages = [...this.chatMessages, {
                id: this.messageSequenceCounter,
                text: 'System processing error. Connection with the travel network timed out.',
                isAgent: true,
                computedClass: 'bubble-error font-semibold'
            }];
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    handleSubscribe() {
        const messageCallback = (response) => {
            const payload = response.data.payload;
            if (payload.Session_Id__c === this.currentSessionId) {
                this.selectedDestinationCode = payload.Destination_Code__c;
                this.activeFlightRecordId = payload.Flight_Id__c;
                
                if (payload.CMS_Content_Key__c) {
                    this.activeBackgroundUrl = payload.CMS_Content_Key__c;
                }
                
                this.currentHeroTitle = `Journey to ${this.selectedDestinationCode}`;
                this.currentHeroSubtitle = 'Your AI Concierge has prepared your itinerary.';
                this.showFlightCard = true;
                this.broadcastFlightRecommendation();
            }
        };

        subscribe(this.channelName, -1, messageCallback).then((response) => {
            this.subscription = response;
        });
    }

    broadcastFlightRecommendation() {
        publish(this.messageContext, shaFlightChannel, {
            flightId: this.activeFlightRecordId,
            destinationCode: this.selectedDestinationCode,
            interactionState: 'RECOMMENDED'
        });
    }

    registerErrorListener() {
        onError((error) => {
            console.error('A.E.G.I.S. EMP API Event Connection Error: ', JSON.stringify(error));
        });
    }

    closeFlightCard() {
        this.showFlightCard = false;
        this.currentHeroTitle = this.heroGreetingText;
        this.currentHeroSubtitle = this.heroSubGreetingText;
        this.activeBackgroundUrl = this.defaultBgImageCmsKey;
        
        // AEGIS Linter: Resetting session and re-fetching dynamic greeting
        this.currentSessionId = null;
        this.initializeDynamicWelcome();
        
        publish(this.messageContext, shaFlightChannel, { interactionState: 'CLOSED' });
    }

    /**
     * Auth Gate Evaluator: Intercepts seat picker selection requests.
     * Redirects Guest Users to the Experience Cloud login page while saving search state.
     */
    proceedToSeatPicker() {
        if (isGuestUser) {
            const pendingContext = {
                flightId: this.activeFlightRecordId,
                destinationCode: this.selectedDestinationCode
            };
            sessionStorage.setItem('skyhigh_pending_booking', JSON.stringify(pendingContext));

            const base = basePath.endsWith('/') ? basePath.slice(0, -1) : basePath;
            window.location.href = `${base}/s/login`;
            return;
        }

        publish(this.messageContext, shaFlightChannel, {
            flightId: this.activeFlightRecordId,
            destinationCode: this.selectedDestinationCode,
            interactionState: 'SHOW_SEATS'
        });
    }

    disconnectedCallback() {
        unsubscribe(this.subscription, () => {});
    }

    get isSendButtonDisabled() {
        return this.userInput.trim().length === 0 || this.isLoading;
    }
}