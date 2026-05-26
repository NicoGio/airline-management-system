/**
 * @description Controller for SkyHigh Air Seat Engine.
 * Transforms RAW JSON from Asset config into a reactive SVG-ready structure.
 * @author A.E.G.I.S. Enterprise Architect
 */
import { LightningElement, api, wire, track } from 'lwc';
import getSeatMapBySegment from '@salesforce/apex/SH_BookingController.getSeatMapBySegment';

export default class ShaSeatPicker extends LightningElement {
    @api segmentId;
    @track seatMap;

    // Wired connection to the backend logic
    @wire(getSeatMapBySegment, { segmentId: '$segmentId' })
    wiredSeatMap({ error, data }) {
        if (data) {
            this.seatMap = this.processSeatData(data);
        } else if (error) {
            console.error('Error fetching seat map:', error);
        }
    }

    processSeatData(data) {
        // We clone the data to avoid mutating read-only wired objects
        let config = JSON.parse(JSON.stringify(data.config));

        config.rows = config.rows.map((row, rowIndex) => {
            return {
                ...row,
                seats: row.seats.map((seat, seatIndex) => {
                    return {
                        ...seat,
                        id: `${row.rowNumber}-${seat.seatLetter}`,
                        code: `${row.rowNumber}${seat.seatLetter}`,
                        // Coordinate calculation logic for SVG placement
                        x: 50 + (seatIndex * 40),
                        y: 50 + (rowIndex * 40),
                        statusClass: this.getSeatClass(seat.status)
                    };
                })
            };
        });
        return config;
    }

    getSeatClass(status) {
        switch(status) {
            case 'AVAILABLE': return 'sha-seat-node_available';
            case 'HELD':      return 'sha-seat-node_held';
            case 'OCCUPIED':  return 'sha-seat-node_occupied';
            default:          return 'sha-seat-node_default';
        }
    }

    handleSeatClick(event) {
        const seatCode = event.target.dataset.seatCode;
        // Logic for locking the seat goes here
        console.log('Seat selected:', seatCode);
    }
}