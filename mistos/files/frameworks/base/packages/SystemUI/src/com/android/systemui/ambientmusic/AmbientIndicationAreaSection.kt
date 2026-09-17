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
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintSet
import com.android.systemui.dagger.qualifiers.Background
import com.android.systemui.keyguard.domain.interactor.KeyguardInteractor
import com.android.systemui.keyguard.shared.model.KeyguardSection
import com.android.systemui.plugins.ActivityStarter
import com.android.systemui.power.domain.interactor.PowerInteractor
import com.android.systemui.res.R
import com.android.systemui.shade.ShadeDisplayAware
import com.android.systemui.user.domain.interactor.SelectedUserInteractor
import com.android.systemui.util.wakelock.WakeLockLogger
import com.google.android.systemui.ambientmusic.AmbientIndicationContainer
import com.google.android.systemui.ambientmusic.AmbientIndicationService
import javax.inject.Inject

/**
 * Keyguard section that hosts the Pixel "ambient indication" (Now Playing on the lock screen).
 *
 * Fills AOSP's `KEYGUARD_AMBIENT_INDICATION_AREA_SECTION` optional slot in
 * `DefaultKeyguardBlueprint`/`SplitShadeKeyguardBlueprint`, so the container lives inside the
 * live `KeyguardRootView` ConstraintLayout, directly above the keyguard indication area. (The
 * legacy `keyguard_bottom_area.xml` is still inflated on Android 17 but permanently GONE, which is
 * why parking the container there rendered nothing.)
 *
 * The section owns the whole lifecycle: it inflates the container, initialises it, starts the
 * [AmbientIndicationService] broadcast receiver, and tears everything down when the blueprint
 * rebuilds. Every step is defensive so a failure here can never crash SystemUI.
 */
class AmbientIndicationAreaSection
@Inject
constructor(
    @ShadeDisplayAware private val context: Context,
    private val activityStarter: ActivityStarter,
    private val alarmManager: AlarmManager,
    private val powerInteractor: PowerInteractor,
    private val selectedUserInteractor: SelectedUserInteractor,
    private val keyguardInteractor: KeyguardInteractor,
    private val wakeLockLogger: WakeLockLogger,
    @Background private val bgHandler: Handler,
) : KeyguardSection() {

    private var service: AmbientIndicationService? = null

    override fun addViews(constraintLayout: ConstraintLayout) {
        try {
            val view =
                LayoutInflater.from(context)
                    .inflate(R.layout.ambient_indication, constraintLayout, false)
            constraintLayout.addView(view)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to inflate ambient indication", e)
        }
    }

    override fun bindData(constraintLayout: ConstraintLayout) {
        val container =
            constraintLayout.findViewById<AmbientIndicationContainer>(
                R.id.ambient_indication_container
            )
        if (container == null) {
            Log.w(TAG, "ambient_indication_container missing, Now Playing on lock screen disabled")
            return
        }
        try {
            container.initializeView(
                powerInteractor,
                activityStarter,
                wakeLockLogger,
                bgHandler,
            ) { visible -> keyguardInteractor.setAmbientIndicationVisible(visible) }
            service?.stop()
            service =
                AmbientIndicationService(context, container, selectedUserInteractor, alarmManager)
            Log.i(TAG, "Ambient indication bound to keyguard root view")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialise ambient indication", e)
        }
    }

    override fun applyConstraints(constraintSet: ConstraintSet) {
        constraintSet.apply {
            constrainWidth(R.id.ambient_indication_container, ViewGroup.LayoutParams.MATCH_PARENT)
            constrainHeight(R.id.ambient_indication_container, ViewGroup.LayoutParams.WRAP_CONTENT)
            // Sit just above the keyguard indication text ("Charging", "Swipe up to open").
            connect(
                R.id.ambient_indication_container,
                ConstraintSet.BOTTOM,
                R.id.keyguard_indication_area,
                ConstraintSet.TOP,
            )
            connect(
                R.id.ambient_indication_container,
                ConstraintSet.START,
                ConstraintSet.PARENT_ID,
                ConstraintSet.START,
            )
            connect(
                R.id.ambient_indication_container,
                ConstraintSet.END,
                ConstraintSet.PARENT_ID,
                ConstraintSet.END,
            )
        }
    }

    override fun removeViews(constraintLayout: ConstraintLayout) {
        service?.stop()
        service = null
        keyguardInteractor.setAmbientIndicationVisible(false)
        constraintLayout.findViewById<View>(R.id.ambient_indication_container)?.let {
            constraintLayout.removeView(it)
        }
    }

    companion object {
        private const val TAG = "AmbientIndicationSection"
    }
}
