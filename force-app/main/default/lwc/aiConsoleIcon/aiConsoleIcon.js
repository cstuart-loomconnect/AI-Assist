import { LightningElement, api } from 'lwc';

const path = (d, extra = {}) => ({ type: 'path', d, ...extra });
const circle = (cx, cy, r) => ({ type: 'circle', cx, cy, r });
const rect = (x, y, width, height, rx) => ({ type: 'rect', x, y, width, height, rx });
const ellipse = (cx, cy, rx, ry) => ({ type: 'ellipse', cx, cy, rx, ry });

// The design's icons, as 24 x 24 stroke drawings. fill: 'solid' draws them filled instead of outlined.
const ICONS = {
    search: [circle(11, 11, 7), path('M20 20l-3.5-3.5')],
    refresh: [path('M20 12a8 8 0 1 1-2.3-5.7L20 8M20 3v5h-5')],
    filter: [path('M3 5h18l-7 8v6l-4 2v-8L3 5z')],
    chevronDown: [path('M6 9l6 6 6-6')],
    close: [path('M6 6l12 12M18 6L6 18')],
    lock: [rect(5, 11, 14, 10, 2), path('M8 11V8a4 4 0 0 1 8 0v3')],
    pencil: [path('M4 20h4L19 9l-4-4L4 16v4z')],
    info: [circle(12, 12, 9), path('M12 11v5M12 8h.01')],
    errorCircle: [circle(12, 12, 9), path('M12 7v6M12 16v.01')],
    check: [path('M5 12l5 5 9-10')],
    checkCircle: [path('M9 12l2 2 4-4M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z')],
    shield: [path('M12 3l8 3v6c0 4.5-3.4 8.3-8 9-4.6-.7-8-4.5-8-9V6l8-3z')],
    warning: [path('M12 8v5M12 16v.01M10.3 3.9L2.6 17.5A2 2 0 0 0 4.3 20.5h15.4a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z')],
    warningFilled: [path('M12 3l9 16H3l9-16z', { fill: '#FE9339', stroke: '#5C2B03' }), path('M12 10v4M12 17v.01', { fill: 'none', stroke: '#5C2B03' })],
    agent: [path('M12 3v3M7 7h10a3 3 0 0 1 3 3v6a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3v-6a3 3 0 0 1 3-3zM9 12h.01M15 12h.01M9.5 16h5')],
    model: [rect(5, 5, 14, 14, 2), path('M9 1v4M15 1v4M9 19v4M15 19v4M1 9h4M1 15h4M19 9h4M19 15h4')],
    datasource: [ellipse(12, 5, 8, 3), path('M4 5v14c0 1.7 3.6 3 8 3s8-1.3 8-3V5M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3')],
    action: [path('M13 2L4 14h7l-1 8 9-12h-7l1-8z')],
    conversation: [path('M4 5h16v11H9l-5 4V5z')],
    violation: [path('M12 3l8 3v6c0 4.5-3.4 8.3-8 9-4.6-.7-8-4.5-8-9V6l8-3z')],
    log: [path('M8 6l-6 6 6 6M16 6l6 6-6 6')],
    flow: [path('M5 4v6a4 4 0 0 0 4 4h10M15 10l4 4-4 4')],
    thumbsUp: [path('M7 10v11H3V10h4zM7 10l4-7c1.7 0 3 1.3 3 3v3h5.5a2 2 0 0 1 2 2.3l-1.2 8A2 2 0 0 1 18.3 21H7')],
    calendar: [rect(3, 5, 18, 16, 2), path('M3 10h18M8 3v4M16 3v4')],
    power: [path('M12 3v9M6.3 7a8 8 0 1 0 11.4 0')],
    hash: [path('M4 8h16M4 16h16M8 4v16M16 4v16')],
    star: [path('M12 2l3 6h6l-5 4 2 7-6-4-6 4 2-7-5-4h6z')],
    plus: [path('M12 5v14M5 12h14')],
    trash: [path('M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13')]
};

/*
One inline stroke icon from the console's set. Takes the text colour of wherever it sits (stroke is
currentColor), so the same icon works on a white tile, a red badge or a blue link. Always decorative -
the button or link around it carries the accessible name.
*/
export default class AiConsoleIcon extends LightningElement {
    @api name = 'info';
    @api size = 14;
    @api strokeWidth = 2;
    @api solid = false; // Filled with currentColor instead of outlined.

    get fillColor() {
        return this.solid ? 'currentColor' : 'none';
    }

    get strokeColor() {
        return this.solid ? 'none' : 'currentColor';
    }

    get shapes() {
        const drawing = ICONS[this.name] || ICONS.info;
        return drawing.map((shape, index) => ({
            ...shape,
            key: `${this.name}-${index}`,
            isPath: shape.type === 'path',
            isCircle: shape.type === 'circle',
            isRect: shape.type === 'rect',
            isEllipse: shape.type === 'ellipse'
        }));
    }
}