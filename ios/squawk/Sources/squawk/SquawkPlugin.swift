import Flutter
import UIKit

/// Streams shake events to Dart over the "squawk/shake" event channel.
///
/// iOS rides the system shake gesture (`UIEvent.EventSubtype.motionShake`),
/// which is why no motion permission or Info.plist entry is needed. The
/// system decides what counts as a shake, so the Dart side's sensitivity
/// argument is ignored here.
public class SquawkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterEventChannel(
            name: "squawk/shake", binaryMessenger: registrar.messenger())
        channel.setStreamHandler(SquawkPlugin())
    }

    private var events: FlutterEventSink?

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.events = events
        // A hot restart re-listens without a cancel in between; never let
        // a stacked observer double-fire every shake.
        NotificationCenter.default.removeObserver(self, name: .squawkShake, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(onShake), name: .squawkShake, object: nil)
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NotificationCenter.default.removeObserver(self, name: .squawkShake, object: nil)
        events = nil
        return nil
    }

    // Motion events are delivered on the main thread, which is where an
    // event sink must be called from.
    @objc private func onShake() {
        events?(nil)
    }
}

extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .squawkShake, object: self)
        }
        // UIResponder's implementation, so anything else built on motion
        // events keeps seeing them.
        super.motionEnded(motion, with: event)
    }
}

extension Notification.Name {
    static let squawkShake = Notification.Name("com.squawksdk.squawk.shake")
}
