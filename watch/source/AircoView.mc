import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Layout (fractions of the screen so it fits 240x240 and 320x360):
//   top row    : status / room temperature        power button (right)
//   middle     : [ - ]      big target temp       [ + ]
//   bottom row : [ mode ]                [ fan ]
class AircoView extends WatchUi.View {
    hidden var model;
    var w = 240;
    var h = 240;

    function initialize(m) {
        View.initialize();
        model = m;
    }

    function onLayout(dc as Dc) as Void {
        w = dc.getWidth();
        h = dc.getHeight();
    }

    function modeColor() {
        if (!model.active) { return 0x555555; }
        var m = model.mode();
        if (m == MODE_HEAT) { return 0xFF8800; }
        if (m == MODE_COOL) { return 0x00AAFF; }
        if (m == MODE_DRY) { return 0x55FFAA; }
        if (m == MODE_FAN) { return 0xAAAAAA; }
        return 0xAA55FF;
    }

    // Hit areas, shared with the delegate.
    function zone(x, y) {
        if (y < h * 0.27) {
            return x > w * 0.6 ? :power : :none;
        }
        if (y < h * 0.70) {
            if (x < w * 0.28) { return :minus; }
            if (x > w * 0.72) { return :plus; }
            return :none;
        }
        return x < w / 2 ? :mode : :fan;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var accent = modeColor();
        var cx = w / 2;

        // Top: power button + status line
        var pr = (h * 0.09).toNumber();
        var px = (w * 0.80).toNumber();
        var py = (h * 0.14).toNumber();
        dc.setPenWidth(3);
        dc.setColor(model.active ? accent : 0x555555, Graphics.COLOR_TRANSPARENT);
        if (model.active) {
            dc.fillCircle(px, py, pr);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.drawCircle(px, py, pr);
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        }
        // power glyph
        dc.drawArc(px, py, pr / 2, Graphics.ARC_CLOCKWISE, 60, 120);
        dc.drawLine(px, py - pr * 0.65, px, py - pr * 0.05);

        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var top = model.status;
        if (top == null) {
            top = model.current != null ? "Room " + model.current.format("%.1f") + "°" : "";
        }
        dc.drawText((w * 0.08).toNumber(), py, Graphics.FONT_XTINY, top,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Middle: − target +
        var my = (h * 0.48).toNumber();
        var t = model.target();
        var big = "--";
        if (model.loaded) {
            if (!model.active) {
                big = "Off";
            } else if (model.mode() == MODE_FAN) {
                big = "Fan";
            } else if (t != null) {
                big = t.format(t == t.toNumber() ? "%d" : "%.1f") + "°";
            }
        }
        dc.setColor(model.active ? Graphics.COLOR_WHITE : 0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, my, Graphics.FONT_NUMBER_MEDIUM, big,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        var canAdjust = model.loaded && model.active && model.mode() != MODE_FAN;
        var br = (w * 0.09).toNumber();
        var lx = (w * 0.13).toNumber();
        var rx = (w * 0.87).toNumber();
        dc.setColor(canAdjust ? accent : 0x333333, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(lx, my, br);
        dc.drawCircle(rx, my, br);
        dc.setPenWidth(3);
        dc.drawLine(lx - br / 2, my, lx + br / 2, my);
        dc.drawLine(rx - br / 2, my, rx + br / 2, my);
        dc.drawLine(rx, my - br / 2, rx, my + br / 2);

        // Accent line under the temperature
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine((w * 0.36).toNumber(), (h * 0.65).toNumber(), (w * 0.64).toNumber(), (h * 0.65).toNumber());

        // Bottom: mode + fan pills
        var by = (h * 0.84).toNumber();
        var pw = (w * 0.40).toNumber();
        var ph = (h * 0.17).toNumber();
        pill(dc, (w * 0.06).toNumber(), by - ph / 2, pw, ph, accent, "Mode", MODE_NAMES[model.mode()]);
        pill(dc, (w * 0.54).toNumber(), by - ph / 2, pw, ph, accent, "Fan", FAN_NAMES[model.fanLevel()]);
    }

    hidden function pill(dc, x, y, pw, ph, accent, label, value) {
        dc.setPenWidth(2);
        dc.setColor(model.active ? accent : 0x444444, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, pw, ph, ph / 2);
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + pw / 2, y + ph * 0.28, Graphics.FONT_XTINY, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + pw / 2, y + ph * 0.68, Graphics.FONT_XTINY, value,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
