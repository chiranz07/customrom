/*
 * Copyright (C) 2023 The Android Open Source Project
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

// Ported from vendor_pixel-framework (branch fifteen) SystemUIGoogle
// ambientmusic/AmbientIndicationService.java for Mist-OS 17 (shiba).
// Receives the Now Playing "ambient indication" broadcasts sent by Android
// System Intelligence (com.google.android.as) and drives the lock screen
// AmbientIndicationContainer. Unchanged apart from this header.
package com.google.android.systemui.ambientmusic;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.SystemClock;
import android.os.UserHandle;
import android.util.Log;

import com.android.keyguard.KeyguardUpdateMonitor;
import com.android.keyguard.KeyguardUpdateMonitorCallback;
import com.android.systemui.Dependency;
import com.android.systemui.user.domain.interactor.SelectedUserInteractor;

public final class AmbientIndicationService extends BroadcastReceiver {
    private static final String TAG = "AmbientIndication";

    private final AlarmManager mAlarmManager;
    private final AmbientIndicationContainer mAmbientIndicationContainer;
    private final Context mContext;
    private final SelectedUserInteractor mSelectedUserInteractor;
    private boolean mStarted = false;

    private final KeyguardUpdateMonitorCallback mCallback = new KeyguardUpdateMonitorCallback() {
        @Override
        public void onUserSwitchComplete(int userId) {
            onUserSwitched();
        }
    };

    private final AlarmManager.OnAlarmListener mHideIndicationListener;

    public AmbientIndicationService(
            Context context,
            AmbientIndicationContainer ambientIndicationContainer,
            SelectedUserInteractor selectedUserInteractor,
            AlarmManager alarmManager) {
        mContext = context;
        mAmbientIndicationContainer = ambientIndicationContainer;
        mAlarmManager = alarmManager;
        mSelectedUserInteractor = selectedUserInteractor;
        // Created here (not as a field initializer) so javac's definite-assignment
        // check is satisfied for the final container field it captures.
        mHideIndicationListener =
                () -> mAmbientIndicationContainer.setAmbientMusic(null, null, null, false, 0, null);
        start();
    }

    void start() {
        if (mStarted) {
            return;
        }
        mStarted = true;
        IntentFilter intentFilter = new IntentFilter();
        intentFilter.addAction("com.google.android.ambientindication.action.AMBIENT_INDICATION_SHOW");
        intentFilter.addAction("com.google.android.ambientindication.action.AMBIENT_INDICATION_HIDE");
        mContext.registerReceiverAsUser(this, UserHandle.ALL, intentFilter,
                "com.google.android.ambientindication.permission.AMBIENT_INDICATION", null,
                Context.RECEIVER_EXPORTED);
        Dependency.get(KeyguardUpdateMonitor.class).registerCallback(mCallback);
        Log.i(TAG, "AmbientIndicationService started.");
    }

    /** Unregisters everything; called when the keyguard blueprint rebuilds. */
    public void stop() {
        if (!mStarted) {
            return;
        }
        mStarted = false;
        mAlarmManager.cancel(mHideIndicationListener);
        try {
            mContext.unregisterReceiver(this);
        } catch (IllegalArgumentException e) {
            // already unregistered
        }
        Dependency.get(KeyguardUpdateMonitor.class).removeCallback(mCallback);
        mAmbientIndicationContainer.hideAmbientMusic();
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!isForCurrentUser()) {
            Log.i(TAG, "Suppressing ambient, not for this user.");
            return;
        }
        int version = intent.getIntExtra("com.google.android.ambientindication.extra.VERSION", 0);
        if (version != 1) {
            Log.e(TAG, "AmbientIndicationApi.EXTRA_VERSION is 1, but received an intent with version "
                    + version + ", dropping intent.");
            return;
        }
        String action = intent.getAction();
        if (action == null) {
            return;
        }
        if (action.equals("com.google.android.ambientindication.action.AMBIENT_INDICATION_HIDE")) {
            mAlarmManager.cancel(mHideIndicationListener);
            mAmbientIndicationContainer.setAmbientMusic(null, null, null, false, 0, null);
            Log.i(TAG, "Hiding ambient indication.");
            return;
        }
        if (action.equals("com.google.android.ambientindication.action.AMBIENT_INDICATION_SHOW")) {
            long ttl = Math.min(Math.max(intent.getLongExtra(
                    "com.google.android.ambientindication.extra.TTL_MILLIS", 180000L), 0L), 180000L);
            boolean skipUnlock = intent.getBooleanExtra(
                    "com.google.android.ambientindication.extra.SKIP_UNLOCK", false);
            int iconOverride = intent.getIntExtra(
                    "com.google.android.ambientindication.extra.ICON_OVERRIDE", 0);
            String iconDescription = intent.getStringExtra(
                    "com.google.android.ambientindication.extra.ICON_DESCRIPTION");
            CharSequence text = intent.getCharSequenceExtra(
                    "com.google.android.ambientindication.extra.TEXT");
            mAmbientIndicationContainer.setAmbientMusic(
                    text != null ? text.toString() : null,
                    intent.getParcelableExtra(
                            "com.google.android.ambientindication.extra.OPEN_INTENT",
                            PendingIntent.class),
                    intent.getParcelableExtra(
                            "com.google.android.ambientindication.extra.FAVORITING_INTENT",
                            PendingIntent.class),
                    skipUnlock, iconOverride, iconDescription);
            mAlarmManager.setExact(AlarmManager.ELAPSED_REALTIME,
                    SystemClock.elapsedRealtime() + ttl, TAG, mHideIndicationListener, null);
            Log.i(TAG, "Showing ambient indication.");
        }
    }

    private boolean isForCurrentUser() {
        return getSendingUserId() == getCurrentUser() || getSendingUserId() == UserHandle.USER_ALL;
    }

    private int getCurrentUser() {
        return mSelectedUserInteractor.getSelectedUserId();
    }

    private void onUserSwitched() {
        mAmbientIndicationContainer.hideAmbientMusic();
    }
}
