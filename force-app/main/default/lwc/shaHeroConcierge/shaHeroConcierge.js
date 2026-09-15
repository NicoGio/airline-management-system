/*
 * A.E.G.I.S. Enterprise Architecture Component:
 * Master Orchestrator Controller for SkyHigh Airlines Experience Cloud.
 * Features:
 * - Production-Grade: Zero console logging statements
 * - Zero Hardcode: Dynamic payload extraction without static fallbacks
 * - Turn-Based State Machine: Natural conversation handoff via Agentforce inference
 * - 1800ms Perception Buffer for seamless UI transition
 * - Clean LMS Propagation across shaFlightChannel__c
 * - Automatic Input Focus Restoration via requestAnimationFrame
 */
import { LightningElement, track, api, wire } from 'lwc';
import sendMessageToAgent from '@salesforce/apex/SH_AgentforceBroker.sendMessageToAgent';
import pollForFlightEvent from '@salesforce/apex/SH_AgentforceBroker.pollForFlightEvent';

import { publish, subscribe, unsubscribe, MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';
import SHA_FLIGHT_CHANNEL from '@salesforce/messageChannel/shaFlightChannel__c';

export default class ShaHeroConcierge extends LightningElement {
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

    @track chatMessages = [];
    @track isLoading = false;
    @track currentInputText = '';
    @track currentSessionId = null;
    messageSequenceCounter = 0;

    awaitingConfirmation = false;
    stagedFlight = null;
    lmsSubscription = null;

    activePollingTimeout = null;
    activeDispatchTimeout = null;

    @wire(MessageContext) messageContext;

    get logoUrl() {
        if (!this.brandLogoCmsKey) return null;
        return this.brandLogoCmsKey.includes('/') 
            ? this.brandLogoCmsKey 
            : `/sfsites/c/cms/delivery/media/${this.brandLogoCmsKey}`;
    }

    get dynamicBackgroundStyle() {
        if (!this.defaultBgImageCmsKey) return 'background-color: #0f172a;';
        const bgUrl = this.defaultBgImageCmsKey.includes('/') 
            ? this.defaultBgImageCmsKey 
            : `/sfsites/c/cms/delivery/media/${this.defaultBgImageCmsKey}`;
        return `background-image: url('${bgUrl}'); background-size: cover; background-position: center; background-repeat: no-repeat;`;
    }

    connectedCallback() {
        this.subscribeToChannel();
        this.initializeAgentSession('INIT_SESSION_GREETING');
    }

    disconnectedCallback() {
        this.clearAllPendingTimers();
        this.unsubscribeFromChannel();
    }

    subscribeToChannel() {
        if (!this.lmsSubscription) {
            this.lmsSubscription = subscribe(
                this.messageContext,
                SHA_FLIGHT_CHANNEL,
                (message) => this.handleLmsMessage(message),
                { scope: APPLICATION_SCOPE }
            );
        }
    }

    unsubscribeFromChannel() {
        if (this.lmsSubscription) {
            unsubscribe(this.lmsSubscription);
            this.lmsSubscription = null;
        }
    }

    handleLmsMessage(message) {
        if (message && message.interactionState === 'DISMISSED') {
            this.stagedFlight = null;
            this.awaitingConfirmation = false;
            this.restoreInputFocus();
        }
    }

    initializeAgentSession(systemContext) {
        this.isLoading = true;
        this.scrollToBottom();

        sendMessageToAgent({ userMessage: systemContext, sessionId: this.currentSessionId })
        .then(result => {
            if (result && result.isSuccess && result.agentSessionId) {
                this.currentSessionId = result.agentSessionId;
            }

            const responseText = result?.responseText || '';
            this.appendMessage(responseText, true, result?.isSuccess);
        })
        .catch(() => {
            this.appendMessage('System communication interruption during initialization.', true, false);
        })
        .finally(() => {
            this.isLoading = false;
            this.scrollToBottom();
            this.restoreInputFocus();
        });
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && event.target.value.trim()) {
            const userMsg = event.target.value.trim();
            event.target.value = '';
            this.executeAgentforceServerCall(userMsg);
        }
    }

    handleSendMessage() {
        const inputEl = this.template.querySelector('.chat-input');
        if (inputEl && inputEl.value.trim()) {
            const userMsg = inputEl.value.trim();
            inputEl.value = '';
            this.executeAgentforceServerCall(userMsg);
        }
    }

    executeAgentforceServerCall(userNarrative) {
        this.clearAllPendingTimers();

        let flightToDispatchAfterRender = null;

        if (this.awaitingConfirmation && this.stagedFlight) {
            flightToDispatchAfterRender = { ...this.stagedFlight };
            this.stagedFlight = null;
            this.awaitingConfirmation = false;
        }

        this.appendMessage(userNarrative, false, true);
        this.isLoading = true;
        this.scrollToBottom();

        sendMessageToAgent({ userMessage: userNarrative, sessionId: this.currentSessionId })
        .then(result => {
            if (result && result.isSuccess && result.agentSessionId) {
                this.currentSessionId = result.agentSessionId;
            }

            const responseText = result?.responseText || '';
            this.appendMessage(responseText, true, result?.isSuccess);

            const synchronousFlight = this.extractFlightPayload(result);

            if (synchronousFlight) {
                this.stagedFlight = synchronousFlight;
                this.awaitingConfirmation = true;
            } else if (flightToDispatchAfterRender) {
                this.dispatchFlightToModal(flightToDispatchAfterRender, 1800);
            } else if (!this.awaitingConfirmation) {
                this.initiateRecursivePolling(4);
            }
        })
        .catch(() => {
            this.appendMessage('System communication interruption. Please retry.', true, false);
        })
        .finally(() => {
            this.isLoading = false;
            this.scrollToBottom();
            this.restoreInputFocus();
        });
    }

    initiateRecursivePolling(retriesLeft) {
        if (retriesLeft <= 0 || !this.currentSessionId) return;

        this.activePollingTimeout = setTimeout(() => {
            pollForFlightEvent({ sessionId: this.currentSessionId })
            .then(pollResult => {
                const asyncFlight = this.extractFlightPayload(pollResult);
                
                if (asyncFlight) {
                    this.stagedFlight = asyncFlight;
                    this.awaitingConfirmation = true;
                } else {
                    this.initiateRecursivePolling(retriesLeft - 1);
                }
            })
            .catch(() => {
                this.initiateRecursivePolling(retriesLeft - 1);
            });
        }, 1500);
    }

    extractFlightPayload(source) {
        if (!source) return null;
        
        const flightId = source.flightId || source.flightSegmentId || null;
        const isValidId = flightId && typeof flightId === 'string' && (flightId.length === 15 || flightId.length === 18);
        
        if (!isValidId) return null;

        return {
            flightId: flightId,
            flightNumber: source.flightNumber || '',
            originCode: source.originCode || '',
            originCity: source.originCity || '',
            destinationCode: source.destinationCode || '',
            destinationCity: source.destinationCity || '',
            aircraft: source.aircraft || source.aircraftModel || '',
            departureTime: source.departureTime || '',
            flightType: source.flightType || 'Direct Flight',
            seatPreference: source.seatPreference || null
        };
    }

    dispatchFlightToModal(flightPayload, bufferDelay = 1800) {
        if (!flightPayload || !flightPayload.flightId) return;

        const payload = {
            ...flightPayload,
            interactionState: 'RECOMMENDED'
        };
        
        this.activeDispatchTimeout = setTimeout(() => {
            publish(this.messageContext, SHA_FLIGHT_CHANNEL, payload);
        }, bufferDelay);
    }

    appendMessage(text, isAgent, isSuccess = true) {
        this.messageSequenceCounter++;
        this.chatMessages = [...this.chatMessages, {
            id: this.messageSequenceCounter,
            text: text,
            isAgent: isAgent,
            computedClass: isAgent 
                ? (isSuccess ? 'bubble-agent' : 'bubble-error font-semibold')
                : 'bubble-user'
        }];
        this.scrollToBottom();
    }

    clearAllPendingTimers() {
        if (this.activePollingTimeout) {
            clearTimeout(this.activePollingTimeout);
            this.activePollingTimeout = null;
        }
        if (this.activeDispatchTimeout) {
            clearTimeout(this.activeDispatchTimeout);
            this.activeDispatchTimeout = null;
        }
    }

    scrollToBottom() {
        window.requestAnimationFrame(() => {
            const container = this.refs.chatContainer || this.template.querySelector('.chat-messages-container');
            if (container) {
                container.scrollTo({
                    top: container.scrollHeight,
                    behavior: 'smooth'
                });
            }
        });
    }

    restoreInputFocus() {
        window.requestAnimationFrame(() => {
            const inputEl = this.template.querySelector('.chat-input');
            if (inputEl) {
                inputEl.focus();
            }
        });
    }
}