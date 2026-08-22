package com.squawksdk.squawk;

import android.content.Context;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;

/**
 * Fires when the device is shaken: when more than three quarters of the
 * accelerometer samples in the last half second exceed the threshold, the
 * device is shaking (or free-falling, which nobody files a bug during).
 *
 * The sampling approach is adapted from Square's seismic
 * (https://github.com/square/seismic, Apache-2.0).
 */
class ShakeDetector implements SensorEventListener {

  interface OnShake {
    void onShake();
  }

  private final SensorManager sensorManager;
  private final Sensor accelerometer;
  private final OnShake listener;
  private final double thresholdSquared;
  private final SampleQueue queue = new SampleQueue();

  /**
   * @param force the acceleration beyond gravity, in m/s², that counts as
   *     "accelerating" for a sample. Higher needs a harder shake.
   */
  ShakeDetector(Context context, float force, OnShake listener) {
    this.listener = listener;
    // Squared magnitudes throughout, so no square root runs per sample.
    thresholdSquared =
        (double) SensorManager.GRAVITY_EARTH * SensorManager.GRAVITY_EARTH
            + (double) force * force;
    sensorManager = (SensorManager) context.getSystemService(Context.SENSOR_SERVICE);
    accelerometer = sensorManager == null
        ? null
        : sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
  }

  /** Returns false when the device has no accelerometer. */
  boolean start() {
    if (accelerometer == null) {
      return false;
    }
    // GAME rate (~50Hz) gives the half-second window enough samples for the
    // three-quarters vote to mean something; FASTEST buys nothing but
    // battery drain for a trigger a human operates.
    return sensorManager.registerListener(
        this, accelerometer, SensorManager.SENSOR_DELAY_GAME);
  }

  void stop() {
    if (accelerometer != null) {
      sensorManager.unregisterListener(this, accelerometer);
    }
    queue.clear();
  }

  @Override
  public void onSensorChanged(SensorEvent event) {
    float ax = event.values[0];
    float ay = event.values[1];
    float az = event.values[2];
    boolean accelerating =
        (double) ax * ax + (double) ay * ay + (double) az * az > thresholdSquared;
    queue.add(event.timestamp, accelerating);
    if (queue.isShaking()) {
      // Clearing restarts the vote, so one sustained shake fires once
      // rather than on every sample for as long as the arm keeps moving.
      queue.clear();
      listener.onShake();
    }
  }

  @Override
  public void onAccuracyChanged(Sensor sensor, int accuracy) {}

  /** The sliding window of samples, with counts kept as a running total. */
  private static final class SampleQueue {
    /** Window size in ns. */
    private static final long MAX_WINDOW_SIZE = 500_000_000; // 0.5s
    private static final long MIN_WINDOW_SIZE = MAX_WINDOW_SIZE >> 1; // 0.25s

    /**
     * Never drop below this many samples, even when the device delivers
     * fewer events than the window expects (some do).
     */
    private static final int MIN_QUEUE_SIZE = 4;

    private final SamplePool pool = new SamplePool();
    private Sample oldest;
    private Sample newest;
    private int sampleCount;
    private int acceleratingCount;

    void add(long timestamp, boolean accelerating) {
      purge(timestamp - MAX_WINDOW_SIZE);

      Sample added = pool.acquire();
      added.timestamp = timestamp;
      added.accelerating = accelerating;
      added.next = null;
      if (newest != null) {
        newest.next = added;
      }
      newest = added;
      if (oldest == null) {
        oldest = added;
      }

      sampleCount++;
      if (accelerating) {
        acceleratingCount++;
      }
    }

    void clear() {
      while (oldest != null) {
        Sample removed = oldest;
        oldest = removed.next;
        pool.release(removed);
      }
      newest = null;
      sampleCount = 0;
      acceleratingCount = 0;
    }

    private void purge(long cutoff) {
      while (sampleCount >= MIN_QUEUE_SIZE
          && oldest != null
          && cutoff - oldest.timestamp > 0) {
        Sample removed = oldest;
        if (removed.accelerating) {
          acceleratingCount--;
        }
        sampleCount--;
        oldest = removed.next;
        if (oldest == null) {
          newest = null;
        }
        pool.release(removed);
      }
    }

    /** True when the window is full enough and >= 3/4 of it is accelerating. */
    boolean isShaking() {
      return newest != null
          && oldest != null
          && newest.timestamp - oldest.timestamp >= MIN_WINDOW_SIZE
          && acceleratingCount >= (sampleCount >> 1) + (sampleCount >> 2);
    }
  }

  private static final class Sample {
    long timestamp;
    boolean accelerating;
    Sample next;
  }

  /** Recycles samples: ~50 allocations a second is GC noise worth avoiding. */
  private static final class SamplePool {
    private Sample head;

    Sample acquire() {
      Sample acquired = head;
      if (acquired == null) {
        return new Sample();
      }
      head = acquired.next;
      return acquired;
    }

    void release(Sample sample) {
      sample.next = head;
      head = sample;
    }
  }
}
