/*
 * SPDX-FileCopyrightText: 2026 Mist-OS
 * SPDX-License-Identifier: Apache-2.0
 *
 * High brightness mode control for Pixel 8 / 8 Pro (zuma).
 *
 * The panel's HBM range is owned by the framework's HighBrightnessModeController
 * (services/core/.../display/HighBrightnessModeController.java, Mist-OS patched),
 * which reads these Settings.Secure keys:
 *   hbm_force               1 = allow the HBM brightness range at any time
 *   auto_hbm                1 = use auto_hbm_threshold instead of the config's minimumLux
 *   auto_hbm_threshold      lux
 *   auto_hbm_no_time_limit  1 = ignore the config's "5 min per 30 min" HBM cap
 * Writing the panel's sysfs hbm_mode directly does not work on these panels: the
 * display HAL re-asserts its own HBM state through the DRM property on the next
 * commit, so the user-space write is undone almost immediately.
 */

package org.lineageos.settings.autohbm;

import android.content.ContentResolver;
import android.content.Context;
import android.content.SharedPreferences;
import android.hardware.display.DisplayManager;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Display;

import androidx.preference.PreferenceManager;

public final class HbmController {
    static final String KEY_HBM = "hbm_force";
    static final String KEY_AUTO_HBM = "auto_hbm";
    static final String KEY_THRESHOLD = "auto_hbm_threshold";
    static final String KEY_NO_TIME_LIMIT = "auto_hbm_no_time_limit";
    static final int DEFAULT_THRESHOLD_LUX = 10000; // shiba/husky display config minimumLux

    private static final String PREF_SAVED_BRIGHTNESS = "hbm_saved_brightness";
    private static final String PREF_SAVED_MODE = "hbm_saved_brightness_mode";

    private HbmController() {}

    public static boolean isForced(Context context) {
        return Settings.Secure.getInt(context.getContentResolver(), KEY_HBM, 0) != 0;
    }

    /**
     * Manual HBM: allow the HBM range, switch to manual brightness and push it to peak (with
     * adaptive brightness on, the auto controller would otherwise keep the level low). On
     * disable, restore the brightness mode and level the user had before.
     */
    public static void setForced(Context context, boolean enabled) {
        final ContentResolver cr = context.getContentResolver();
        final DisplayManager dm = context.getSystemService(DisplayManager.class);
        final SharedPreferences prefs = PreferenceManager.getDefaultSharedPreferences(context);
        if (enabled) {
            final int mode = Settings.System.getInt(cr, Settings.System.SCREEN_BRIGHTNESS_MODE,
                    Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL);
            final SharedPreferences.Editor e = prefs.edit().putInt(PREF_SAVED_MODE, mode);
            if (dm != null) {
                e.putFloat(PREF_SAVED_BRIGHTNESS, dm.getBrightness(Display.DEFAULT_DISPLAY));
            }
            e.apply();
            Settings.Secure.putInt(cr, KEY_HBM, 1);
            Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS_MODE,
                    Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL);
            if (dm != null) {
                // The framework's HBM controller observes hbm_force asynchronously on the
                // display thread; give it a moment to raise the allowed maximum above the
                // HBM transition point (0.71 on shiba) before asking for peak brightness,
                // otherwise the request is clamped to 0.71 until the next update.
                new Handler(Looper.getMainLooper()).postDelayed(
                        () -> dm.setBrightness(Display.DEFAULT_DISPLAY, 1.0f), 400);
            }
        } else {
            Settings.Secure.putInt(cr, KEY_HBM, 0);
            if (dm != null) {
                final float saved = prefs.getFloat(PREF_SAVED_BRIGHTNESS, -1f);
                if (saved >= 0f && saved <= 1f) {
                    dm.setBrightness(Display.DEFAULT_DISPLAY, saved);
                }
            }
            final int mode = prefs.getInt(PREF_SAVED_MODE, -1);
            if (mode == Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC
                    || mode == Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL) {
                Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS_MODE, mode);
            }
        }
    }

    public static boolean isAutoEnabled(Context context) {
        return Settings.Secure.getInt(context.getContentResolver(), KEY_AUTO_HBM, 0) != 0;
    }

    public static void setAutoEnabled(Context context, boolean enabled) {
        Settings.Secure.putInt(context.getContentResolver(), KEY_AUTO_HBM, enabled ? 1 : 0);
    }

    public static int getThreshold(Context context) {
        return Settings.Secure.getInt(context.getContentResolver(), KEY_THRESHOLD,
                DEFAULT_THRESHOLD_LUX);
    }

    public static void setThreshold(Context context, int lux) {
        Settings.Secure.putInt(context.getContentResolver(), KEY_THRESHOLD, lux);
    }

    public static boolean isNoTimeLimit(Context context) {
        return Settings.Secure.getInt(context.getContentResolver(), KEY_NO_TIME_LIMIT, 0) != 0;
    }

    public static void setNoTimeLimit(Context context, boolean enabled) {
        Settings.Secure.putInt(context.getContentResolver(), KEY_NO_TIME_LIMIT,
                enabled ? 1 : 0);
    }
}
