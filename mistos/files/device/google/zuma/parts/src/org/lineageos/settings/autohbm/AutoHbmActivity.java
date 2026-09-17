/*
 * SPDX-FileCopyrightText: 2026 Mist-OS
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.autohbm;

import android.os.Bundle;

import com.android.settingslib.collapsingtoolbar.CollapsingToolbarBaseActivity;

public class AutoHbmActivity extends CollapsingToolbarBaseActivity {
    private static final String TAG = "AutoHbmActivity";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getSupportFragmentManager()
                .beginTransaction()
                .replace(com.android.settingslib.collapsingtoolbar.R.id.content_frame,
                        new AutoHbmFragment(), TAG)
                .commit();
    }
}
