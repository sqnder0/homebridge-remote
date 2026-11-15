import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Thermostat-style screen, laid out in fractions so it fits 240x240 and 320x360:
//
//          .-~~~~~~~-.          dial: 270° track, filled up to the target temperature
//        /   COOL      \        mode name in the mode color
//       |     21.5°     |       target, big
//        \  Room 23.0° /        room temperature, or the error / status
//          '-  −   +  -'        − and + sit in the dial's open bottom
//      [mode]  (power)  [fan]   three round buttons
class AircoView extends WatchUi.View {
    hidden var model;
    var w = 240;
    var h = 240;
    // dial geometry
    var cx = 120;
    var cy = 104;
    var r = 86;
    // button row
    var by = 214;
    var br = 20;
    // − / + inside the dial gap
    var py = 170;
    var pr = 17;

    function initialize(m) {
        View.initialize();
        model = m;
    }

    function onLayout(dc as Dc) as Void {
        w = dc.getWidth();
        h = dc.getHeight();
        var s = (w < h ? w : h);
        cx = w / 2;
        r = (s * 0.36).toNumber();
        cy = (h * 0.435).toNumber();
        br = (s * 0.085).toNumber();
        by = h - br - (h * 0.04).toNumber();
        pr = (s * 0.07).toNumber();
        py = cy + (r * 0.78).toNumber();
    }

    // Hit areas, shared with the delegate.
    function zone(x, y) {
        if (y > by - br - 6) {
            if (x < w * 0.33) { return :mode; }
            if (x > w * 0.67) { return :fan; }
            return :power;
        }
        if (y > py - pr - 10) {
            return x < cx ? :minus : :plus;
        }
        return :center;
    }

    function modeColor() {
        var m = model.mode();
        if (m == MODE_HEAT) { return 0xFF7A1A; }
        if (m == MODE_COOL) { return 0x2FA8FF; }
        if (m == MODE_DRY) { return 0x3DDC97; }
        if (m == MODE_FAN) { return 0xC9C9C9; }
        return 0xB07CFF;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        var on = model.loaded && model.active;
        var accent = on ? modeColor() : 0x5A5A5A;
        var t = model.target();
        var adjustable = on && model.mode() != MODE_FAN && t != null;

        drawDial(dc, on, accent, t, adjustable);
        drawCenter(dc, on, accent, t);
        drawStep(dc, cx - (r * 0.42).toNumber(), false, adjustable, accent);
        drawStep(dc, cx + (r * 0.42).toNumber(), true, adjustable, accent);

        drawButton(dc, (w * 0.17).toNumber(), :mode, on, accent);
        drawButton(dc, cx, :power, on, accent);
        drawButton(dc, (w * 0.83).toNumber(), :fan, on, accent);
    }

    // 270° dial: 225° (bottom-left) clockwise to -45° (bottom-right).
    hidden function drawDial(dc, on, accent, t, adjustable) {
        var pen = (r * 0.13).toNumber();
        dc.setPenWidth(pen);
        dc.setColor(0x262626, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 225, -45);
        if (!adjustable) { return; }

        var span = model.maxT - model.minT;
        var f = span > 0 ? (t - model.minT) / span : 0.5;
        if (f < 0) { f = 0; }
        if (f > 1) { f = 1; }
        var end = 225 - 270 * f;
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        if (f > 0.005) {
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 225, end);
        }
        // knob
        var a = Math.toRadians(end);
        var kx = cx + r * Math.cos(a);
        var ky = cy - r * Math.sin(a);
        dc.fillCircle(kx, ky, pen * 0.85);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(kx, ky, pen * 0.38);
    }

    hidden function drawCenter(dc, on, accent, t) {
        var bigFont = Graphics.FONT_NUMBER_MEDIUM;
        var bigH = dc.getFontHeight(bigFont);
        var smallH = dc.getFontHeight(Graphics.FONT_XTINY);

        // Big value
        var big = "--";
        var font = bigFont;
        if (model.loaded) {
            if (!model.active) {
                big = "OFF";
                font = Graphics.FONT_LARGE;
            } else if (model.mode() == MODE_FAN) {
                big = "FAN";
                font = Graphics.FONT_LARGE;
            } else if (t != null) {
                big = t.format(t == t.toNumber() ? "%d" : "%.1f");
            }
        }
        dc.setColor(on ? Graphics.COLOR_WHITE : 0x8A8A8A, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, font, big, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (font == bigFont && model.loaded && t != null) {
            // degree mark, top right of the number
            var tw = dc.getTextWidthInPixels(big, bigFont);
            var dr = (bigH * 0.07).toNumber() + 2;
            dc.setPenWidth(2);
            dc.drawCircle(cx + tw / 2 + dr + 3, cy - bigH * 0.28, dr);
        }

        // Mode name above
        var top = cy - bigH / 2 - smallH / 2 - 2;
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        var label = !model.loaded ? "" : (model.active ? MODE_NAMES[model.mode()].toUpper() : "AIRCO");
        dc.drawText(cx, top, Graphics.FONT_XTINY, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Room temperature, or what's wrong, below
        var below = cy + bigH / 2 + smallH / 2;
        if (model.status != null) {
            dc.setColor(model.isError ? 0xFF6A4D : 0x8A8A8A, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, below, Graphics.FONT_XTINY, model.status,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (model.current != null) {
            dc.setColor(0x9A9A9A, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, below, Graphics.FONT_XTINY, "Room " + model.current.format("%.1f") + "°",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    hidden function drawStep(dc, x, plus, enabled, accent) {
        dc.setColor(enabled ? 0x1E1E1E : 0x111111, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, py, pr);
        dc.setColor(enabled ? accent : 0x3A3A3A, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        var l = (pr * 0.5).toNumber();
        dc.drawLine(x - l, py, x + l + 1, py);
        if (plus) { dc.drawLine(x, py - l, x, py + l + 1); }
    }

    hidden function drawButton(dc, x, kind, on, accent) {
        var lit = kind == :power ? on : false;
        dc.setColor(lit ? accent : 0x1E1E1E, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, by, br);
        var fg = lit ? Graphics.COLOR_BLACK : (on ? accent : 0x9A9A9A);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        if (kind == :power) {
            var pr2 = (br * 0.48).toNumber();
            dc.setPenWidth(3);
            dc.drawArc(x, by, pr2, Graphics.ARC_CLOCKWISE, 55, 125);
            dc.drawLine(x, by - pr2 - 2, x, by);
        } else if (kind == :mode) {
            drawModeIcon(dc, x, by, (br * 0.55).toNumber());
        } else {
            drawFanIcon(dc, x, by, (br * 0.55).toNumber(), on, accent);
        }
    }

    hidden function drawModeIcon(dc, x, y, s) {
        var m = model.mode();
        if (m == MODE_COOL) {
            // snowflake
            for (var i = 0; i < 3; i++) {
                var a = Math.toRadians(90 + i * 60);
                var dx = s * Math.cos(a);
                var dy = s * Math.sin(a);
                dc.drawLine(x - dx, y - dy, x + dx, y + dy);
            }
        } else if (m == MODE_HEAT) {
            // sun
            dc.fillCircle(x, y, s * 0.45);
            for (var i = 0; i < 8; i++) {
                var a = Math.toRadians(i * 45);
                dc.drawLine(x + s * 0.7 * Math.cos(a), y + s * 0.7 * Math.sin(a),
                    x + s * Math.cos(a), y + s * Math.sin(a));
            }
        } else if (m == MODE_DRY) {
            // drop
            var rr = s * 0.55;
            dc.fillCircle(x, y + s * 0.3, rr);
            dc.fillPolygon([[x, y - s], [x - rr, y + s * 0.25], [x + rr, y + s * 0.25]]);
        } else if (m == MODE_FAN) {
            drawBlades(dc, x, y, s);
        } else {
            dc.drawText(x, y, Graphics.FONT_TINY, "A",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    hidden function drawBlades(dc, x, y, s) {
        for (var i = 0; i < 3; i++) {
            var a = Math.toRadians(90 + i * 120);
            dc.fillCircle(x + s * 0.5 * Math.cos(a), y - s * 0.5 * Math.sin(a), s * 0.38);
        }
        dc.setColor(0x1E1E1E, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, s * 0.18);
    }

    // Fan speed as four rising bars; "A" when automatic.
    hidden function drawFanIcon(dc, x, y, s, on, accent) {
        var lvl = model.fanLevel();
        if (lvl == 0) {
            dc.drawText(x, y, Graphics.FONT_TINY, "A",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var bw = (s * 0.38).toNumber();
        if (bw < 3) { bw = 3; }
        var gap = 2;
        var total = 4 * bw + 3 * gap;
        var x0 = x - total / 2;
        var base = y + s;
        for (var i = 0; i < 4; i++) {
            var bh = (s * 0.5 + s * 1.5 * (i + 1) / 4).toNumber();
            dc.setColor(i < lvl ? (on ? accent : 0x9A9A9A) : 0x3A3A3A, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x0 + i * (bw + gap), base - bh, bw, bh);
        }
    }
}
