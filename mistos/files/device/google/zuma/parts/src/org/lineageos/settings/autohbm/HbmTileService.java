/*
 * SPDX-FileCopyrightText: 2026 Mist-OS
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.autohbm;

import android.content.SharedPreferences;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

import androidx.preference.PreferenceManager;

/** Quick Settings tile toggling manual high brightness mode. */
public class HbmTileService extends TileService {

    @Override
    public void onStartListening() {
        super.onStartListening();
        updateTile();
    }

    @Override
    public void onClick() {
        super.onClick();
        final SharedPreferences prefs = PreferenceManager.getDefaultSharedPreferences(this);
        final boolean enabled = !prefs.getBoolean(AutoHbmService.KEY_HBM, false);
        prefs.edit().putBoolean(AutoHbmService.KEY_HBM, enabled).apply();
        AutoHbmService.sync(this);
        updateTile();
    }

    private void updateTile() {
        final Tile tile = getQsTile();
        if (tile == null) return;
        final boolean enabled = PreferenceManager.getDefaultSharedPreferences(this)
                .getBoolean(AutoHbmService.KEY_HBM, false);
        tile.setState(enabled ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        tile.updateTile();
    }
}
