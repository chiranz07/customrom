/*
 * SPDX-FileCopyrightText: 2016 The CyanogenMod Project
 * SPDX-FileCopyrightText: 2017-2024 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.utils;

import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;

public final class FileUtils {
    private static final String TAG = "FileUtils";

    private FileUtils() {}

    /** Reads the first line of a file, or {@code defValue} if it can't be read. */
    public static String readLine(String fileName, String defValue) {
        try (BufferedReader reader = new BufferedReader(new FileReader(fileName), 512)) {
            String line = reader.readLine();
            return line != null ? line.trim() : defValue;
        } catch (IOException e) {
            Log.w(TAG, "Could not read " + fileName + ": " + e.getMessage());
            return defValue;
        }
    }

    /** Writes {@code value} to a file. Returns true on success. */
    public static boolean writeLine(String fileName, String value) {
        try (FileWriter writer = new FileWriter(fileName)) {
            writer.write(value);
            return true;
        } catch (IOException e) {
            Log.w(TAG, "Could not write " + value + " to " + fileName + ": " + e.getMessage());
            return false;
        }
    }

    public static boolean fileExists(String fileName) {
        return new File(fileName).exists();
    }
}
