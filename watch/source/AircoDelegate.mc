import Toybox.Attention;
import Toybox.Lang;
import Toybox.WatchUi;

class AircoDelegate extends WatchUi.BehaviorDelegate {
    hidden var model;
    hidden var view;

    function initialize(m, v) {
        BehaviorDelegate.initialize();
        model = m;
        view = v;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        var z = view.zone(xy[0], xy[1]);
        if (z == :none) { return false; }
        if (z == :power) {
            model.togglePower();
        } else if (z == :minus) {
            model.adjust(-0.5);
        } else if (z == :plus) {
            model.adjust(0.5);
        } else if (z == :mode) {
            model.nextMode();
        } else if (z == :fan) {
            model.nextFan();
        }
        buzz();
        WatchUi.requestUpdate();
        return true;
    }

    // Bottom button (Venu Sq "back/lap") would close the app; keep default.
    // Swipe up/down = temperature, as an alternative to tapping.
    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var d = evt.getDirection();
        if (d == WatchUi.SWIPE_UP) {
            model.adjust(0.5);
        } else if (d == WatchUi.SWIPE_DOWN) {
            model.adjust(-0.5);
        } else {
            return false;
        }
        buzz();
        WatchUi.requestUpdate();
        return true;
    }

    hidden function buzz() {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(30, 40)]);
        }
    }
}
