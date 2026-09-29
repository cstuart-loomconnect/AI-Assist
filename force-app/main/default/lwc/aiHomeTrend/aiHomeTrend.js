import { LightningElement, api } from 'lwc';
import getConversationTrend from '@salesforce/apex/AIConsoleController.getConversationTrend';
import { TABS, SECTIONS, navigate, reduceError } from 'c/aiConsoleUtils';

const DEFAULT_DAYS = 14;
const PLOT_LEFT = 36;
const PLOT_RIGHT = 812;
const PLOT_BOTTOM = 190;
const PLOT_HEIGHT = 180;
const MAX_BAR_WIDTH = 26;

/*
Home › Conversations per day, as a bar chart in the design's 820 x 220 drawing. Follows the date range
picked in the summary header (pageState.dateRange). The newest bar is labelled with its count; the axis
shows the first day, the middle day and "Today".
*/
export default class AiHomeTrend extends LightningElement {
    @api section;

    trend;
    error;
    days = DEFAULT_DAYS;

    _pageState;
    @api
    get pageState() {
        return this._pageState;
    }
    set pageState(value) {
        this._pageState = value;
        if (value && value.dateRange && value.dateRange !== this.days) {
            this.days = value.dateRange;
            this.load();
        }
    }

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            this.trend = await getConversationTrend({ days: this.days });
            this.error = undefined;
        } catch (error) {
            this.error = reduceError(error);
        }
    }

    get title() {
        return `Conversations, last ${this.days} days`;
    }

    get hasData() {
        return !!this.trend;
    }

    get scaleMax() {
        return this.trend ? this.trend.scaleMax : 0;
    }

    get scaleHalf() {
        return Math.round(this.scaleMax / 2);
    }

    get spacing() {
        const count = this.trend ? this.trend.points.length : 1;
        return (PLOT_RIGHT - PLOT_LEFT) / Math.max(count, 1);
    }

    get bars() {
        if (!this.trend) return [];
        const spacing = this.spacing;
        const width = Math.min(MAX_BAR_WIDTH, spacing * 0.47);

        return this.trend.points.map((point, index) => {
            const height = this.scaleMax ? (point.count / this.scaleMax) * PLOT_HEIGHT : 0;
            const x = PLOT_LEFT + spacing * index + (spacing - width) / 2;
            return {
                key: point.day,
                x: x.toFixed(1),
                y: (PLOT_BOTTOM - height).toFixed(1),
                width: width.toFixed(1),
                height: height.toFixed(1),
                hasBase: height >= 4, // Squares off the bottom corners of the rounded bar.
                baseY: PLOT_BOTTOM - 4,
                centre: (x + width / 2).toFixed(1),
                count: point.count,
                isToday: point.isToday,
                labelY: Math.max(14, PLOT_BOTTOM - height - 6).toFixed(1),
                tooltip: `${point.label}: ${point.count}`
            };
        });
    }

    get todayBar() {
        return this.bars.find((bar) => bar.isToday);
    }

    get axisLabels() {
        if (!this.trend || !this.trend.points.length) return [];
        const points = this.trend.points;
        const indexes = [...new Set([0, Math.floor(points.length / 2), points.length - 1])];
        return indexes.map((index) => ({
            key: `axis-${index}`,
            x: (PLOT_LEFT + this.spacing * index + this.spacing / 2).toFixed(1),
            text: points[index].label
        }));
    }

    get chartLabel() {
        if (!this.trend || !this.trend.points.length) return 'Daily conversations';
        const points = this.trend.points;
        const counts = points.map((point) => point.count);
        return `Daily conversations from ${points[0].label} to today, between ${Math.min(...counts)} and ${Math.max(...counts)} a day`;
    }

    handleViewReport(event) {
        event.preventDefault();
        navigate(this, { tab: TABS.ACTIVITY, section: SECTIONS.ACTIVITY_CONVERSATIONS });
    }
}
