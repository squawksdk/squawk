package com.squawksdk.squawk;

import android.content.Context;

import androidx.annotation.NonNull;

import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;

/**
 * Streams shake events to Dart over the "squawk/shake" event channel.
 *
 * The accelerometer runs only while Dart is listening; the Dart side
 * cancels whenever the app leaves the foreground, so a backgrounded app
 * costs no battery.
 */
public class SquawkPlugin implements FlutterPlugin, EventChannel.StreamHandler {
  private EventChannel channel;
  private Context context;
  private ShakeDetector detector;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    channel = new EventChannel(binding.getBinaryMessenger(), "squawk/shake");
    channel.setStreamHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    stopDetector();
    channel.setStreamHandler(null);
    channel = null;
    context = null;
  }

  @Override
  public void onListen(Object arguments, EventChannel.EventSink events) {
    // A hot restart re-listens without a cancel in between; never let a
    // previous detector keep feeding a dead sink.
    stopDetector();
    detector = new ShakeDetector(context, forceFrom(arguments),
        () -> events.success(null));
    if (!detector.start()) {
      detector = null;
      events.error("unavailable", "this device has no accelerometer", null);
    }
  }

  @Override
  public void onCancel(Object arguments) {
    stopDetector();
  }

  private void stopDetector() {
    if (detector != null) {
      detector.stop();
      detector = null;
    }
  }

  /** The acceleration beyond gravity, in m/s², that counts as a shake. */
  private static float forceFrom(Object arguments) {
    if (arguments instanceof Map) {
      Object force = ((Map<?, ?>) arguments).get("force");
      if (force instanceof Number) {
        return ((Number) force).floatValue();
      }
    }
    // Dart always sends a force; this is reachable only if the two sides
    // get out of step, and matches ShakeSensitivity.medium.
    return 6.0f;
  }
}
