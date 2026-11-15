import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Display order of modes on the watch.
const MODE_AUTO = 0;
const MODE_COOL = 1;
const MODE_HEAT = 2;
const MODE_DRY = 3;
const MODE_FAN = 4;
const MODE_NAMES = ["Auto", "Cool", "Heat", "Dry", "Fan"];
const FAN_NAMES = ["Auto", "Quiet", "Low", "Mid", "High"];

// Talks to the Homebridge UI REST API through the phone (Garmin Connect).
// Only fetches the 4 services the watch needs, one at a time, to stay inside
// the small memory budget of the Venu Sq.
class AircoModel {
    // What the watch shows
    var active = false;
    var hcMode = 2;          // TargetHeaterCoolerState: 0 auto, 1 heat, 2 cool
    var dry = false;
    var fanOnly = false;
    var autoFan = false;
    var fanPct = 0;
    var coolT = null;
    var heatT = null;
    var current = null;
    var minT = 16.0;
    var maxT = 30.0;
    var loaded = false;
    var status = "Connecting";  // null when everything is fine
    var isError = false;

    hidden var token = null;
    hidden var ops = [];      // queue of requests, run one after another
    hidden var running = false;
    hidden var retriedLogin = false;
    hidden var lastWrite = -100000;
    hidden var pendingTemp = null;
    hidden var pollTimer = null;
    hidden var refreshTimer = null;
    hidden var tempTimer = null;
    hidden var retryTimer = null;
    hidden var retries = 0;

    function initialize() {
    }

    function start() {
        pollTimer = new Timer.Timer();
        pollTimer.start(method(:refresh), 20000, true);
        refreshTimer = new Timer.Timer();
        tempTimer = new Timer.Timer();
        retryTimer = new Timer.Timer();
        refresh();
    }

    function stop() {
        if (pollTimer != null) { pollTimer.stop(); }
        if (refreshTimer != null) { refreshTimer.stop(); }
        if (tempTimer != null) { tempTimer.stop(); }
        if (retryTimer != null) { retryTimer.stop(); }
    }

    // Tap on the dial: try again right away.
    function retry() as Void {
        retries = 0;
        ops = [];
        running = false;
        status = "Connecting";
        isError = false;
        WatchUi.requestUpdate();
        refresh();
    }

    // Phone-link errors are often momentary: try again a few times on our own.
    hidden function fail(code) {
        status = errorText(code);
        isError = true;
        ops = [];
        if (code < 0 && retries < 3) {
            retries++;
            retryTimer.stop();
            retryTimer.start(method(:refresh), 2500 * retries, false);
        }
        WatchUi.requestUpdate();
    }

    function prop(key) {
        var v = null;
        try {
            v = Application.Properties.getValue(key);
        } catch (e) {
            v = null;
        }
        return v == null ? "" : v;
    }

    // MARK: Derived state

    function mode() {
        if (dry) { return MODE_DRY; }
        if (fanOnly) { return MODE_FAN; }
        if (hcMode == 1) { return MODE_HEAT; }
        if (hcMode == 2) { return MODE_COOL; }
        return MODE_AUTO;
    }

    function target() {
        return mode() == MODE_HEAT ? heatT : coolT;
    }

    function targetKey() {
        return mode() == MODE_HEAT ? "HeatingThresholdTemperature" : "CoolingThresholdTemperature";
    }

    function fanLevel() {
        if (autoFan || fanPct <= 0) { return 0; }
        var l = (fanPct + 24) / 25;
        return l > 4 ? 4 : l;
    }

    // MARK: Actions

    function togglePower() {
        active = !active;
        put(prop("idMain"), "Active", active ? 1 : 0);
    }

    function nextMode() {
        var m = mode();
        for (var i = 0; i < 5; i++) {
            m = (m + 1) % 5;
            if (m == MODE_DRY && prop("idDry").equals("")) { continue; }
            if (m == MODE_FAN && prop("idFanMode").equals("")) { continue; }
            break;
        }
        setMode(m);
    }

    function setMode(m) {
        var main = prop("idMain");
        if (!active) {
            active = true;
            put(main, "Active", 1);
        }
        if (m == MODE_DRY) {
            fanOnly = false;
            dry = true;
            put(prop("idDry"), "On", true);
        } else if (m == MODE_FAN) {
            dry = false;
            fanOnly = true;
            put(prop("idFanMode"), "On", true);
        } else {
            dry = false;
            fanOnly = false;
            hcMode = m == MODE_AUTO ? 0 : (m == MODE_COOL ? 2 : 1);
            put(main, "TargetHeaterCoolerState", hcMode);
        }
    }

    function nextFan() {
        var l = (fanLevel() + 1) % 5;
        if (l == 0 && prop("idAutoFan").equals("")) { l = 1; }
        if (l == 0) {
            autoFan = true;
            fanPct = 0;
            put(prop("idAutoFan"), "On", true);
        } else {
            autoFan = false;
            fanPct = l * 25;
            put(prop("idMain"), "RotationSpeed", fanPct);
        }
    }

    // Temperature taps are collected and sent once, shortly after the last tap.
    function adjust(delta) {
        var t = target();
        if (t == null || !active || mode() == MODE_FAN) { return; }
        t = t + delta;
        if (t < minT) { t = minT; }
        if (t > maxT) { t = maxT; }
        if (mode() == MODE_HEAT) { heatT = t; } else { coolT = t; }
        pendingTemp = t;
        lastWrite = System.getTimer();
        tempTimer.stop();
        tempTimer.start(method(:sendTemp), 900, false);
    }

    function sendTemp() as Void {
        if (pendingTemp != null) {
            put(prop("idMain"), targetKey(), pendingTemp);
            pendingTemp = null;
        }
    }

    // MARK: Networking

    function refresh() as Void {
        if (prop("hbUrl").equals("") || prop("idMain").equals("")) {
            status = "Not set up";
            isError = true;
            WatchUi.requestUpdate();
            return;
        }
        if (ops.size() > 0) { return; }
        var ids = [prop("idMain"), prop("idDry"), prop("idFanMode"), prop("idAutoFan")];
        for (var i = 0; i < ids.size(); i++) {
            if (!ids[i].equals("")) {
                ops.add({ :kind => :get, :id => ids[i] });
            }
        }
        pump();
    }

    hidden function put(id, key, value) {
        if (id == null || id.equals("")) { return; }
        lastWrite = System.getTimer();
        ops.add({ :kind => :put, :id => id, :key => key, :value => value });
        refreshTimer.stop();
        refreshTimer.start(method(:refresh), 3000, false);
        WatchUi.requestUpdate();
        pump();
    }

    hidden function pump() {
        if (running || ops.size() == 0) { return; }
        running = true;
        if (token == null) {
            login();
            return;
        }
        var op = ops[0];
        var url = prop("hbUrl") + "/api/accessories/" + op[:id];
        if (op[:kind] == :put) {
            var opts = {
                :method => Communications.HTTP_REQUEST_METHOD_PUT,
                :headers => {
                    "Authorization" => "Bearer " + token,
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            };
            Communications.makeWebRequest(url,
                { "characteristicType" => op[:key], "value" => op[:value] },
                opts, method(:onDone));
        } else {
            var opts = {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => { "Authorization" => "Bearer " + token },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            };
            Communications.makeWebRequest(url, null, opts, method(:onDone));
        }
    }

    hidden function login() {
        var user = prop("hbUser");
        var opts = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        if (user.equals("")) {
            Communications.makeWebRequest(prop("hbUrl") + "/api/auth/noauth", {}, opts, method(:onLogin));
        } else {
            Communications.makeWebRequest(prop("hbUrl") + "/api/auth/login",
                { "username" => user, "password" => prop("hbPass") }, opts, method(:onLogin));
        }
    }

    function onLogin(code as Number, data as Dictionary or String or Null) as Void {
        running = false;
        if ((code == 200 || code == 201) && data instanceof Dictionary && data["access_token"] != null) {
            token = data["access_token"];
            pump();
        } else if (code == 400 || code == 401) {
            status = "Login failed";
            isError = true;
            ops = [];
            WatchUi.requestUpdate();
        } else {
            fail(code);
        }
    }

    function onDone(code as Number, data as Dictionary or String or Null) as Void {
        running = false;
        if (code == 401) {
            token = null;
            if (!retriedLogin) {
                retriedLogin = true;
                pump();
                return;
            }
            status = "Login failed";
            isError = true;
            ops = [];
            WatchUi.requestUpdate();
            return;
        }
        retriedLogin = false;
        var op = ops[0];
        ops.remove(op);
        var ok = code == 200 || code == 201 || code == 204 || (op[:kind] == :put && code == -400);
        if (ok) {
            status = null;
            isError = false;
            retries = 0;
            // Ignore reads that race a change we just made; Homebridge lags a little.
            if (op[:kind] == :get && data instanceof Dictionary && System.getTimer() - lastWrite > 2500) {
                apply(op[:id], data);
                if (op[:id].equals(prop("idMain"))) { loaded = true; }
            }
        } else {
            fail(code);
            return;
        }
        WatchUi.requestUpdate();
        pump();
    }

    hidden function apply(id, data) {
        var chars = data["serviceCharacteristics"];
        if (!(chars instanceof Array)) { return; }
        var isMain = id.equals(prop("idMain"));
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            var t = c["type"];
            var v = c["value"];
            if (t == null || v == null) { continue; }
            if (isMain) {
                if (t.equals("Active")) {
                    active = num(v) != 0;
                } else if (t.equals("TargetHeaterCoolerState")) {
                    hcMode = num(v);
                } else if (t.equals("CoolingThresholdTemperature")) {
                    coolT = v.toFloat();
                    if (c["minValue"] != null) { minT = c["minValue"].toFloat(); }
                    if (c["maxValue"] != null) { maxT = c["maxValue"].toFloat(); }
                } else if (t.equals("HeatingThresholdTemperature")) {
                    heatT = v.toFloat();
                } else if (t.equals("CurrentTemperature")) {
                    current = v.toFloat();
                } else if (t.equals("RotationSpeed")) {
                    fanPct = num(v);
                }
            } else if (t.equals("On")) {
                var on = num(v) != 0;
                if (id.equals(prop("idDry"))) {
                    dry = on;
                } else if (id.equals(prop("idFanMode"))) {
                    fanOnly = on;
                } else if (id.equals(prop("idAutoFan"))) {
                    autoFan = on;
                }
            }
        }
    }

    hidden function num(v) {
        if (v instanceof Boolean) { return v ? 1 : 0; }
        return v.toNumber();
    }

    // Short enough for one line on a 240px screen; the code is what tells causes apart.
    function errorText(code) {
        if (code == -104) { return "No phone -104"; }
        if (code == -2 || code == -3) { return "Timeout " + code; }
        if (code == -300) { return "Server timeout"; }
        if (code == -400) { return "Bad reply -400"; }
        if (code == -402 || code == -403) { return "Reply too big"; }
        if (code == 403) { return "Blocked 403"; }
        if (code == 404) { return "Airco not found"; }
        return "Error " + code;
    }
}
