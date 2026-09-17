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
// ambientmusic/AmbientIndicationContainer.kt for Mist-OS 17 (shiba).
// Changes vs. the Android 15 original, all forced by SystemUI API drift:
//  - NotificationMediaManager moved to com.android.systemui.media.
//  - DelayedWakeLock no longer takes a main-thread Handler.
//  - ShadeViewController.setAmbientIndicationTop() no longer exists; the
//    call was dropped (it only nudged the panel's bottom-area layout).
//  - Everything that touches views is null-safe so a missing inner view
//    can never crash SystemUI.
package com.google.android.systemui.ambientmusic

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.app.PendingIntent
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Rect
import android.graphics.drawable.AnimatedVectorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.DrawableWrapper
import android.media.MediaMetadata
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.text.TextUtils
import android.util.AttributeSet
import android.util.Log
import android.util.MathUtils
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import com.android.app.animation.Interpolators.DECELERATE_QUINT
import com.android.app.animation.Interpolators.LINEAR_OUT_SLOW_IN
import com.android.systemui.AutoReinflateContainer
import com.android.systemui.Dependency
import com.android.systemui.doze.DozeReceiver
import com.android.systemui.media.NotificationMediaManager
import com.android.systemui.plugins.ActivityStarter
import com.android.systemui.plugins.statusbar.StatusBarStateController
import com.android.systemui.power.domain.interactor.PowerInteractor
import com.android.systemui.res.R
import com.android.systemui.statusbar.StatusBarState
import com.android.systemui.util.wakelock.DelayedWakeLock
import com.android.systemui.util.wakelock.WakeLock
import com.android.systemui.util.wakelock.WakeLockLogger

class AmbientIndicationContainer(private val context: Context, attrs: AttributeSet) :
    AutoReinflateContainer(context, attrs),
    DozeReceiver,
    StatusBarStateController.StateListener,
    NotificationMediaManager.MediaListener {

    private var activityStarter: ActivityStarter? = null
    private var powerInteractor: PowerInteractor? = null
    private val handler: Handler = Handler(Looper.getMainLooper())
    private val iconBounds: Rect = Rect()
    private var wakeLock: WakeLock? = null
    private var ambientIconOverride: Drawable? = null
    private var ambientIndicationIconSize: Int = 0
    private var ambientMusicAnimation: Drawable? = null
    private var ambientMusicNoteIcon: Drawable? = null
    private var ambientMusicNoteIconSize: Int = 0
    private var ambientMusicText: String? = null
    private var ambientSkipUnlock: Boolean = false
    private var bottomMarginPx: Int = 0
    private var dozing: Boolean = false
    private var favoritingIntent: PendingIntent? = null
    private var iconDescription: String? = null
    private var iconOverride: Int = -1
    private var iconView: ImageView? = null
    private var indicationTextMode: Int = 0
    private var mediaPlaybackState: Int = 0
    private var openIntent: PendingIntent? = null
    private var barState: Int = 0
    private var textColor: Int = 0
    private var textColorAnimator: ValueAnimator? = null
    private var textView: TextView? = null
    private var reverseChargingMessage: String = ""

    fun initializeView(
        powerInteractor: PowerInteractor,
        activityStarter: ActivityStarter,
        wakeLockLogger: WakeLockLogger,
        bgHandler: Handler,
    ) {
        this.activityStarter = activityStarter
        this.powerInteractor = powerInteractor
        wakeLock = DelayedWakeLock(bgHandler, context, wakeLockLogger, TAG)
        addInflateListener {
            textView = findViewById(R.id.ambient_indication_text)
            iconView = findViewById(R.id.ambient_indication_icon)
            ambientMusicAnimation = context.getDrawable(R.anim.audioanim_animation)
            ambientMusicNoteIcon = context.getDrawable(R.drawable.ic_music_note)
            textColor = textView?.currentTextColor ?: textColor
            ambientIndicationIconSize =
                resources.getDimensionPixelSize(R.dimen.ambient_indication_icon_size)
            ambientMusicNoteIconSize =
                resources.getDimensionPixelSize(R.dimen.ambient_indication_note_icon_size)
            textView?.isEnabled = !dozing
            updateColors()
            updatePill()
            textView?.setOnClickListener { onTextClick() }
            iconView?.setOnClickListener { onIconClick() }
        }
        addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> updateSpacing() }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        Dependency.get(StatusBarStateController::class.java).addCallback(this)
        Dependency.get(NotificationMediaManager::class.java).addCallback(this)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        Dependency.get(StatusBarStateController::class.java).removeCallback(this)
        Dependency.get(NotificationMediaManager::class.java).removeCallback(this)
    }

    fun setAmbientMusic(
        text: String?,
        openIntent: PendingIntent?,
        favoriteIntent: PendingIntent?,
        skipUnlock: Boolean,
        iconOverride: Int,
        iconDescription: String?,
    ) {
        if (
            this.ambientMusicText != text ||
                this.openIntent != openIntent ||
                this.favoritingIntent != favoriteIntent ||
                this.iconOverride != iconOverride ||
                this.ambientSkipUnlock != skipUnlock ||
                this.iconDescription != iconDescription
        ) {
            this.ambientMusicText = text
            this.openIntent = openIntent
            this.favoritingIntent = favoriteIntent
            this.ambientSkipUnlock = skipUnlock
            this.iconOverride = iconOverride
            this.iconDescription = iconDescription
            this.ambientIconOverride = getAmbientIconOverride(iconOverride)
            updatePill()
        }
    }

    private fun getAmbientIconOverride(iconOverride: Int): Drawable? {
        return when (iconOverride) {
            1 -> context.getDrawable(R.drawable.ic_music_search)
            2 -> null
            3 -> context.getDrawable(R.drawable.ic_music_not_found)
            4 -> context.getDrawable(R.drawable.ic_cloud_off)
            5 -> context.getDrawable(R.drawable.ic_favorite)
            6 -> context.getDrawable(R.drawable.ic_favorite_border)
            7 -> context.getDrawable(R.drawable.ic_error)
            8 -> context.getDrawable(R.drawable.ic_favorite_note)
            else -> null
        }
    }

    private fun updatePill() {
        val textView = textView ?: return
        val iconView = iconView ?: return
        val wakeLock = wakeLock ?: return
        val oldIndicationTextMode = indicationTextMode
        var updatePill = true
        indicationTextMode = 1
        var text = ambientMusicText
        val textVisible = textView.visibility == View.VISIBLE
        var icon: Drawable? = if (textVisible) ambientMusicNoteIcon else ambientMusicAnimation
        if (ambientIconOverride != null) {
            icon = ambientIconOverride
        }
        var showAmbientMusicText = ambientMusicText != null && ambientMusicText!!.isEmpty()
        textView.isClickable = openIntent != null
        iconView.isClickable = favoritingIntent != null || openIntent != null
        var iconDescription = if (TextUtils.isEmpty(iconDescription)) text else this.iconDescription
        if (!TextUtils.isEmpty(reverseChargingMessage)) {
            indicationTextMode = 2
            text = reverseChargingMessage
            icon = null
            textView.isClickable = false
            iconView.isClickable = false
            showAmbientMusicText = false
            iconDescription = null
        }
        textView.text = text
        textView.contentDescription = text
        iconView.contentDescription = iconDescription
        var drawableWrapper: Drawable? = null
        if (icon != null) {
            iconBounds.set(0, 0, icon.intrinsicWidth, icon.intrinsicHeight)
            MathUtils.fitRect(
                iconBounds,
                if (icon == ambientMusicNoteIcon) ambientMusicNoteIconSize
                else ambientIndicationIconSize,
            )
            drawableWrapper =
                object : DrawableWrapper(icon) {
                    override fun getIntrinsicWidth(): Int = iconBounds.width()
                    override fun getIntrinsicHeight(): Int = iconBounds.height()
                }
            val endPadding =
                if (!TextUtils.isEmpty(text)) (resources.displayMetrics.density * 24).toInt() else 0
            textView.setPaddingRelative(
                textView.paddingStart, textView.paddingTop, endPadding, textView.paddingBottom)
        } else {
            textView.setPaddingRelative(
                textView.paddingStart, textView.paddingTop, 0, textView.paddingBottom)
        }
        iconView.setImageDrawable(drawableWrapper)
        if (TextUtils.isEmpty(text) && !showAmbientMusicText) {
            updatePill = false
        }
        val vis = if (updatePill) View.VISIBLE else View.GONE
        textView.visibility = vis
        iconView.visibility = if (icon == null) View.GONE else vis
        if (!updatePill) {
            textView.animate().cancel()
            if (icon is AnimatedVectorDrawable) {
                icon.reset()
            }
            handler.post(wakeLock.wrap {})
        } else if (!textVisible) {
            wakeLock.acquire(TAG)
            if (icon is AnimatedVectorDrawable) {
                icon.start()
            }
            textView.translationY = textView.height.toFloat() / 2f
            textView.alpha = 0.0f
            textView
                .animate()
                .alpha(1.0f)
                .translationY(0.0f)
                .setStartDelay(150L)
                .setDuration(100L)
                .setListener(
                    object : AnimatorListenerAdapter() {
                        override fun onAnimationEnd(animator: Animator) {
                            wakeLock.release(TAG)
                            textView.animate().setListener(null)
                        }
                    }
                )
                .setInterpolator(DECELERATE_QUINT)
                .start()
        } else if (oldIndicationTextMode != indicationTextMode) {
            if (icon is AnimatedVectorDrawable) {
                wakeLock.acquire(TAG)
                icon.start()
                wakeLock.release(TAG)
            }
        } else {
            handler.post(wakeLock.wrap {})
        }
        updateSpacing()
    }

    private fun updateHorizontalSpacing() {
        val textView = textView ?: return
        val iconView = iconView ?: return
        val lp = layoutParams as? FrameLayout.LayoutParams ?: return
        val centerX = resources.displayMetrics.widthPixels / 2
        val totalWidth = textView.width + iconView.width
        lp.marginStart = centerX - totalWidth / 2
    }

    private fun updateSpacing() {
        val marginBottom = resources.getDimensionPixelSize(R.dimen.ambient_indication_margin_bottom)
        if (bottomMarginPx != marginBottom) {
            bottomMarginPx = marginBottom
            (layoutParams as? FrameLayout.LayoutParams)?.bottomMargin = bottomMarginPx
        }
        updateHorizontalSpacing()
    }

    fun hideAmbientMusic() {
        setAmbientMusic(null, null, null, false, 0, null)
    }

    private fun onTextClick() {
        openIntent?.let {
            powerInteractor?.wakeUpIfDozing("AMBIENT_MUSIC_CLICK", PowerManager.WAKE_REASON_GESTURE)
            if (ambientSkipUnlock) {
                sendBroadcastWithoutDismissingKeyguard(it)
            } else {
                activityStarter?.startPendingIntentDismissingKeyguard(it)
            }
        }
    }

    private fun onIconClick() {
        favoritingIntent?.let {
            powerInteractor?.wakeUpIfDozing("AMBIENT_MUSIC_CLICK", PowerManager.WAKE_REASON_GESTURE)
            sendBroadcastWithoutDismissingKeyguard(it)
            return
        }
        onTextClick()
    }

    override fun onDozingChanged(isDozing: Boolean) {
        dozing = isDozing
        updateVisibility()
        textView?.let {
            it.isEnabled = !isDozing
            updateColors()
        }
    }

    override fun dozeTimeTick() = updatePill()

    private fun updateColors() {
        val textView = textView ?: return
        val iconView = iconView ?: return
        textColorAnimator?.let {
            if (it.isRunning) {
                it.cancel()
            }
        }
        val defaultColor = textView.textColors.defaultColor
        val dozeColor = if (dozing) -1 else textColor
        if (dozeColor == defaultColor) {
            textView.setTextColor(dozeColor)
            iconView.imageTintList = ColorStateList.valueOf(dozeColor)
        }
        val animator = ValueAnimator.ofArgb(defaultColor, dozeColor)
        animator.interpolator = LINEAR_OUT_SLOW_IN
        animator.duration = 500L
        animator.addUpdateListener {
            val color = it.animatedValue as Int
            textView.setTextColor(color)
            iconView.imageTintList = ColorStateList.valueOf(color)
        }
        animator.addListener(
            object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(a: Animator) {
                    textColorAnimator = null
                }
            }
        )
        textColorAnimator = animator
        animator.start()
    }

    override fun onStateChanged(state: Int) {
        barState = state
        updateVisibility()
    }

    private fun sendBroadcastWithoutDismissingKeyguard(pendingIntent: PendingIntent) {
        if (pendingIntent.isActivity) {
            return
        }
        try {
            pendingIntent.send()
        } catch (e: PendingIntent.CanceledException) {
            Log.w(TAG, "Sending intent failed: $e")
        }
    }

    private fun updateVisibility() {
        visibility = if (barState == StatusBarState.KEYGUARD) View.VISIBLE else View.INVISIBLE
    }

    override fun onPrimaryMetadataOrStateChanged(mediaMetadata: MediaMetadata?, mediaState: Int) {
        if (mediaPlaybackState != mediaState) {
            mediaPlaybackState = mediaState
            if (!isMediaPlaying()) {
                return
            }
            hideAmbientMusic()
        }
    }

    private fun isMediaPlaying(): Boolean = NotificationMediaManager.isPlayingState(mediaPlaybackState)

    fun setReverseChargingMessage(message: String) {
        if (TextUtils.isEmpty(message) && reverseChargingMessage == message) {
            return
        }
        reverseChargingMessage = message
        updatePill()
    }

    companion object {
        private const val TAG = "AmbientIndication"
    }
}
