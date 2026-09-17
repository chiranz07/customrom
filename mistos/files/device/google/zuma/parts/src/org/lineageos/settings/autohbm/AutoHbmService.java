/*
 * SPDX-FileCopyrightText: 2026 Mist-OS
 * SPDX-License-Identifier: Apache-2.0
 *
 * High brightness mode (HBM) controller for Pixel 8 / 8 Pro (zuma).
 *
 * Two modes, both driving the Samsung panel driver's sysfs knob
 * (panel-samsung-drv.c hbm_mode_store: 0 = off, 1 = on/IRC on, 2 = on/IRC off;
 * vendor sepolicy labels the node sysfs_hbm so system_app may write it):
 *  - Manual ("hbm" pref, also toggled by the Quick Settings tile): HBM is forced on
 *    whenever the screen is on.
 *  - Auto ("auto_hbm" pref): HBM turns on once ambient light stays above the lux
 *    threshold for the "enable time", and turns off once it stays below it for the
 *    "disable time" (hysteresis so it doesn't flicker at the threshold edge).
 * HBM is always released on screen-off and when the service stops.
 */

package org.lineageos.settings.autohbm;

import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;

import androidx.preference.PreferenceManager;

import org.lineageos.settings.utils.FileUtils;

public class AutoHbmService extends Service {
    private static final String TAG = "AutoHbmService";
    private static final boolean DEBUG = false;

    static final String HBM_NODE =
            "/sys/class/backlight/panel0-backlight/hbm_mode";
    static final String HBM_ON = "1";
    static final String HBM_OFF = "0";

    static final String KEY_HBM = "hbm";
    static final String KEY_AUTO_HBM = "auto_hbm";
    static final String KEY_THRESHOLD = "auto_hbm_threshold";
    static final String KEY_ENABLE_TIME = "auto_hbm_enable_time";
    static final String KEY_DISABLE_TIME = "auto_hbm_disable_time";
    static final int DEFAULT_THRESHOLD_LUX = 20000;
    static final int DEFAULT_ENABLE_TIME_S = 1;
    static final int DEFAULT_DISABLE_TIME_S = 3;

    private SensorManager mSensorManager;
    private Sensor mLightSensor;
    private PowerManager mPowerManager;
    private SharedPreferences mPrefs;
    private final Handler mHandler = new Handler(Looper.getMainLooper());

    private boolean mScreenOn;
    private boolean mListening;
    private boolean mHbmActive;
    private boolean mEnableScheduled;
    private boolean mDisableScheduled;
    private boolean mManual;
    private boolean mAuto;
    private int mThresholdLux = DEFAULT_THRESHOLD_LUX;
    private long mEnableTimeMs = DEFAULT_ENABLE_TIME_S * 1000L;
    private long mDisableTimeMs = DEFAULT_DISABLE_TIME_S * 1000L;

    private final Runnable mEnableHbm = () -> {
        mEnableScheduled = false;
        setHbm(true);
    };

    private final Runnable mDisableHbm = () -> {
        mDisableScheduled = false;
        setHbm(false);
    };

    private final SensorEventListener mLightListener = new SensorEventListener() {
        @Override
        public void onSensorChanged(SensorEvent event) {
            if (mManual) return; // manual mode owns the panel
            final float lux = event.values[0];
            if (DEBUG) Log.d(TAG, "lux=" + lux + " threshold=" + mThresholdLux);
            if (lux >= mThresholdLux) {
                cancelDisable();
                if (!mHbmActive && !mEnableScheduled) {
                    mEnableScheduled = true;
                    mHandler.postDelayed(mEnableHbm, mEnableTimeMs);
                }
            } else {
                cancelEnable();
                if (mHbmActive && !mDisableScheduled) {
                    mDisableScheduled = true;
                    mHandler.postDelayed(mDisableHbm, mDisableTimeMs);
                }
            }
        }

        @Override
        public void onAccuracyChanged(Sensor sensor, int accuracy) {}
    };

    private final SharedPreferences.OnSharedPreferenceChangeListener mPrefListener =
            (prefs, key) -> {
                loadPrefs();
                applyState();
            };

    private final BroadcastReceiver mScreenReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            final String action = intent.getAction();
            if (Intent.ACTION_SCREEN_ON.equals(action)) {
                mScreenOn = true;
            } else if (Intent.ACTION_SCREEN_OFF.equals(action)) {
                mScreenOn = false;
            }
            applyState();
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        if (DEBUG) Log.d(TAG, "onCreate");
        mSensorManager = getSystemService(SensorManager.class);
        mPowerManager = getSystemService(PowerManager.class);
        mLightSensor = mSensorManager != null
                ? mSensorManager.getDefaultSensor(Sensor.TYPE_LIGHT) : null;
        mPrefs = PreferenceManager.getDefaultSharedPreferences(this);
        mPrefs.registerOnSharedPreferenceChangeListener(mPrefListener);
        loadPrefs();

        final IntentFilter filter = new IntentFilter();
        filter.addAction(Intent.ACTION_SCREEN_ON);
        filter.addAction(Intent.ACTION_SCREEN_OFF);
        registerReceiver(mScreenReceiver, filter);

        mScreenOn = mPowerManager == null || mPowerManager.isInteractive();
        applyState();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        if (DEBUG) Log.d(TAG, "onDestroy");
        stopListening();
        cancelEnable();
        cancelDisable();
        if (mHbmActive) setHbm(false);
        unregisterReceiver(mScreenReceiver);
        mPrefs.unregisterOnSharedPreferenceChangeListener(mPrefListener);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void loadPrefs() {
        mManual = mPrefs.getBoolean(KEY_HBM, false);
        mAuto = mPrefs.getBoolean(KEY_AUTO_HBM, false);
        mThresholdLux = mPrefs.getInt(KEY_THRESHOLD, DEFAULT_THRESHOLD_LUX);
        mEnableTimeMs = mPrefs.getInt(KEY_ENABLE_TIME, DEFAULT_ENABLE_TIME_S) * 1000L;
        mDisableTimeMs = mPrefs.getInt(KEY_DISABLE_TIME, DEFAULT_DISABLE_TIME_S) * 1000L;
    }

    /** Reconciles panel state with screen state + preferences. */
    private void applyState() {
        if (!mScreenOn) {
            stopListening();
            cancelEnable();
            cancelDisable();
            if (mHbmActive) setHbm(false);
            return;
        }
        if (mManual) {
            stopListening();
            cancelEnable();
            cancelDisable();
            if (!mHbmActive) setHbm(true);
            return;
        }
        if (mAuto) {
            startListening();
            // Sensor callbacks decide from here.
            return;
        }
        // Neither mode: release and idle (sync() normally stops us in this case).
        stopListening();
        cancelEnable();
        cancelDisable();
        if (mHbmActive) setHbm(false);
    }

    private void startListening() {
        if (mListening) return;
        if (mLightSensor == null) {
            Log.w(TAG, "No ambient light sensor, Auto HBM inactive");
            return;
        }
        mListening = true;
        mSensorManager.registerListener(mLightListener, mLightSensor,
                SensorManager.SENSOR_DELAY_NORMAL);
    }

    private void stopListening() {
        if (mListening) {
            mSensorManager.unregisterListener(mLightListener);
            mListening = false;
        }
    }

    private void cancelEnable() {
        if (mEnableScheduled) {
            mHandler.removeCallbacks(mEnableHbm);
            mEnableScheduled = false;
        }
    }

    private void cancelDisable() {
        if (mDisableScheduled) {
            mHandler.removeCallbacks(mDisableHbm);
            mDisableScheduled = false;
        }
    }

    private void setHbm(boolean on) {
        final boolean ok = FileUtils.writeLine(HBM_NODE, on ? HBM_ON : HBM_OFF);
        if (ok) {
            mHbmActive = on;
            Log.i(TAG, "HBM " + (on ? "enabled" : "disabled"));
        } else {
            // Leave mHbmActive as-is so the next event retries.
            Log.w(TAG, "Failed to write HBM node");
        }
    }

    /** Starts or stops the service according to the saved preferences. */
    public static void sync(Context context) {
        final SharedPreferences prefs = PreferenceManager.getDefaultSharedPreferences(context);
        final Intent intent = new Intent(context, AutoHbmService.class);
        if (prefs.getBoolean(KEY_HBM, false) || prefs.getBoolean(KEY_AUTO_HBM, false)) {
            context.startService(intent);
        } else {
            context.stopService(intent);
        }
    }
}
