import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class HomebridgeApp extends Application.AppBase {
    var model;

    function initialize() {
        AppBase.initialize();
        model = new AircoModel();
    }

    function onStart(state as Dictionary?) as Void {
        model.start();
    }

    function onStop(state as Dictionary?) as Void {
        model.stop();
    }

    function getInitialView() {
        var view = new AircoView(model);
        return [view, new AircoDelegate(model, view)];
    }
}
