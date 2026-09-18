/*
 * Copyright (C) 2026 The Mist-OS Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.android.settings.sound;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;

import androidx.preference.Preference;

import com.android.settings.core.BasePreferenceController;

import java.util.List;

/**
 * Settings entry for Now Playing.
 *
 * Android System Intelligence disables its own AmbientMusicSettingsActivity and
 * AmbientMusicNotificationsSettingsActivity after a Play update, so the entry Google's own
 * Settings would show disappears while the feature keeps working. AOSP/Lineage Settings has
 * no entry of its own, so this one targets the activity that stays enabled, and falls back to
 * the split Now Playing app's own settings screen.
 */
public class NowPlayingPreferenceController extends BasePreferenceController {

    private static final ComponentName[] TARGETS = new ComponentName[] {
            new ComponentName("com.google.android.as",
                    "com.google.intelligence.sense.ambientmusic.NowPlayingAmbientMusicSettingsActivity"),
            new ComponentName("com.google.android.apps.pixel.nowplaying",
                    "com.google.android.apps.pixel.nowplaying.settings.MainSettingsActivity"),
    };

    public NowPlayingPreferenceController(Context context, String key) {
        super(context, key);
    }

    @Override
    public int getAvailabilityStatus() {
        return resolveTarget() != null ? AVAILABLE : CONDITIONALLY_UNAVAILABLE;
    }

    @Override
    public boolean handlePreferenceTreeClick(Preference preference) {
        if (!getPreferenceKey().equals(preference.getKey())) {
            return super.handlePreferenceTreeClick(preference);
        }
        final ComponentName target = resolveTarget();
        if (target == null) {
            return false;
        }
        preference.getContext().startActivity(new Intent()
                .setComponent(target)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        return true;
    }

    /** First target that is installed and enabled, or null when Now Playing isn't available. */
    private ComponentName resolveTarget() {
        final PackageManager pm = mContext.getPackageManager();
        for (ComponentName cn : TARGETS) {
            final List<ResolveInfo> infos =
                    pm.queryIntentActivities(new Intent().setComponent(cn), 0 /* flags */);
            if (infos != null && !infos.isEmpty()) {
                return cn;
            }
        }
        return null;
    }
}
