/*
 * Copyright (C) 2026 Mist-OS
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
package com.android.systemui.ambientmusic

import android.app.AlarmManager
import android.content.Context
import android.os.Handler
import android.util.Log
import com.android.systemui.CoreStartable
import com.android.systemui.dagger.SysUISingleton
import com.android.systemui.dagger.qualifiers.Background
import com.android.systemui.plugins.ActivityStarter
import com.android.systemui.power.domain.interactor.PowerInteractor
import com.android.systemui.res.R
import com.android.systemui.shade.NotificationShadeWindowView
import com.android.systemui.user.domain.interactor.SelectedUserInteractor
import com.android.systemui.util.wakelock.WakeLockLogger
import com.google.android.systemui.ambientmusic.AmbientIndicationContainer
import com.google.android.systemui.ambientmusic.AmbientIndicationService
import javax.inject.Inject

/**
 * Starts the Pixel "ambient indication" (Now Playing on the lock screen) pipeline: finds the
 * [AmbientIndicationContainer] that keyguard_bottom_area.xml inflates via
 * layout/ambient_indication.xml, initialises it and registers the
 * [AmbientIndicationService] receiver for Android System Intelligence's broadcasts.
 *
 * This replaces the part of SystemUIGoogle's GoogleServices that Mist-OS never shipped. Every
 * step is defensive: if the container is missing, nothing is registered and SystemUI keeps
 * running as before.
 */
@SysUISingleton
class AmbientIndicationStartable
@Inject
constructor(
    private val context: Context,
    private val activityStarter: ActivityStarter,
    private val alarmManager: AlarmManager,
    private val notificationShadeWindowView: NotificationShadeWindowView,
    private val powerInteractor: PowerInteractor,
    private val selectedUserInteractor: SelectedUserInteractor,
    private val wakeLockLogger: WakeLockLogger,
    @Background private val bgHandler: Handler,
) : CoreStartable {

    private var service: AmbientIndicationService? = null
    private var attempts = 0

    override fun start() {
        tryStart()
    }

    private fun tryStart() {
        if (service != null) return
        val container =
            notificationShadeWindowView.findViewById<AmbientIndicationContainer>(
                R.id.ambient_indication_container
            )
        if (container == null) {
            // The shade hierarchy may not be fully inflated yet on the very first call.
            if (attempts++ < MAX_ATTEMPTS) {
                notificationShadeWindowView.postDelayed({ tryStart() }, RETRY_DELAY_MS)
            } else {
                Log.w(TAG, "ambient_indication_container not found, Now Playing on lock screen disabled")
            }
            return
        }
        try {
            container.initializeView(powerInteractor, activityStarter, wakeLockLogger, bgHandler)
            service = AmbientIndicationService(context, container, selectedUserInteractor, alarmManager)
            Log.i(TAG, "Ambient indication initialised")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialise ambient indication", e)
        }
    }

    companion object {
        private const val TAG = "AmbientIndicationStartable"
        private const val MAX_ATTEMPTS = 5
        private const val RETRY_DELAY_MS = 1000L
    }
}
