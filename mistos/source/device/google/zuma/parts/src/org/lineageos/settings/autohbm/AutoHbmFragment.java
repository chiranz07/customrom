/*
 * SPDX-FileCopyrightText: 2026 Mist-OS
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.autohbm;

import android.content.Context;
import android.os.Bundle;

import androidx.preference.Preference;
import androidx.preference.PreferenceFragmentCompat;
import androidx.preference.SeekBarPreference;
import androidx.preference.SwitchPreferenceCompat;

import org.lineageos.settings.R;

public class AutoHbmFragment extends PreferenceFragmentCompat
        implements Preference.OnPreferenceChangeListener {

    private SwitchPreferenceCompat mForce;
    private SwitchPreferenceCompat mAuto;
    private SeekBarPreference mThreshold;
    private SwitchPreferenceCompat mNoTimeLimit;

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        setPreferencesFromResource(R.xml.autohbm_settings, rootKey);
        mForce = findPreference(HbmController.KEY_HBM);
        mAuto = findPreference(HbmController.KEY_AUTO_HBM);
        mThreshold = findPreference(HbmController.KEY_THRESHOLD);
        mNoTimeLimit = findPreference(HbmController.KEY_NO_TIME_LIMIT);
        for (Preference p : new Preference[] {mForce, mAuto, mThreshold, mNoTimeLimit}) {
            if (p != null) p.setOnPreferenceChangeListener(this);
        }
        loadFromSettings();
    }

    @Override
    public void onResume() {
        super.onResume();
        loadFromSettings(); // the QS tile may have changed the manual state
    }

    /** The source of truth is Settings.Secure (read by the framework), not SharedPreferences. */
    private void loadFromSettings() {
        final Context context = requireContext();
        if (mForce != null) mForce.setChecked(HbmController.isForced(context));
        if (mAuto != null) mAuto.setChecked(HbmController.isAutoEnabled(context));
        if (mThreshold != null) mThreshold.setValue(HbmController.getThreshold(context));
        if (mNoTimeLimit != null) mNoTimeLimit.setChecked(HbmController.isNoTimeLimit(context));
    }

    @Override
    public boolean onPreferenceChange(Preference preference, Object newValue) {
        final Context context = requireContext();
        switch (preference.getKey()) {
            case HbmController.KEY_HBM:
                HbmController.setForced(context, (Boolean) newValue);
                break;
            case HbmController.KEY_AUTO_HBM:
                HbmController.setAutoEnabled(context, (Boolean) newValue);
                break;
            case HbmController.KEY_THRESHOLD:
                HbmController.setThreshold(context, (Integer) newValue);
                break;
            case HbmController.KEY_NO_TIME_LIMIT:
                HbmController.setNoTimeLimit(context, (Boolean) newValue);
                break;
            default:
                break;
        }
        return true;
    }
}
