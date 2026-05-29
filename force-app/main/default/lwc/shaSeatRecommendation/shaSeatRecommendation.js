import { LightningElement, api, wire, track } from 'lwc';
import getSeatMapBySegment from '@salesforce/apex/SH_BookingController.getSeatMapBySegment';
import lockSeat from '@salesforce/apex/SH_BookingController.lockSeat';

export default class ShaSeatRecommendation extends LightningElement {
    @api recordId; 
    
    @track isLoading = true;
    @track errorMessage;
    @track flightInfo;
    @track recommendedSeat;
    @track isConfirmed = false;

    @wire(getSeatMapBySegment, { segmentId: '$recordId' })
    wiredSeatMap({ error, data }) {
        if (data) {
            try {
                this.flightInfo = { flight: data.flightNumber, aircraft: data.aircraftType };
                this.recommendedSeat = this.extractBestSeatForUser(data);
                this.errorMessage = undefined;
            } catch (err) {
                this.errorMessage = 'System Malfunction.';
            } finally {
                this.isLoading = false;
            }
        } else if (error) {
            this.errorMessage = 'Unable to load data.';
            this.isLoading = false;
        }
    }

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
                                        // ✅ strictly English attributes!
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

    confirmSuggestion() {
        this.isLoading = true;
        lockSeat({ segmentId: this.recordId, seatCode: this.recommendedSeat.code, sessionIdentifier: 'AI-CONCIERGE-01' })
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
}