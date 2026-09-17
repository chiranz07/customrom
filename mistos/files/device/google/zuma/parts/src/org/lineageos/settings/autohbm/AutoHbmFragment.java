/*
 * SPDX-FileCopyrightText: 2026 Mist-OS
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.autohbm;

import android.os.Bundle;

import androidx.preference.Preference;
import androidx.preference.PreferenceFragmentCompat;
import androidx.preference.SwitchPreferenceCompat;

import org.lineageos.settings.R;

public class AutoHbmFragment extends PreferenceFragmentCompat
        implements Preference.OnPreferenceChangeListener {

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        setPreferencesFromResource(R.xml.autohbm_settings, rootKey);
        for (String key : new String[] {AutoHbmService.KEY_HBM, AutoHbmService.KEY_AUTO_HBM}) {
            final SwitchPreferenceCompat pref = findPreference(key);
            if (pref != null) {
                pref.setOnPreferenceChangeListener(this);
            }
        }
    }

    @Override
    public void onResume() {
        super.onResume();
        // The QS tile may have flipped the manual switch while we were away.
        final SwitchPreferenceCompat manual = findPreference(AutoHbmService.KEY_HBM);
        if (manual != null) {
            manual.setChecked(manual.getPreferenceManager().getSharedPreferences()
                    .getBoolean(AutoHbmService.KEY_HBM, false));
        }
    }

    @Override
    public boolean onPreferenceChange(Preference preference, Object newValue) {
        final String key = preference.getKey();
        if (AutoHbmService.KEY_HBM.equals(key) || AutoHbmService.KEY_AUTO_HBM.equals(key)) {
            // Persist now (returning true would do it after this callback) so sync() sees it.
            preference.getPreferenceManager().getSharedPreferences()
                    .edit().putBoolean(key, (Boolean) newValue).apply();
            AutoHbmService.sync(requireContext());
        }
        return true;
    }
}
