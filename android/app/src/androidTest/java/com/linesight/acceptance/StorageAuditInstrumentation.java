package com.linesight.acceptance;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.pm.PackageInfo;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.os.Bundle;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Collections;

/** Separate, same-certificate instrumentation APK. Never packaged in the app. */
public final class StorageAuditInstrumentation extends Instrumentation {
    private boolean seed;
    @Override public void onCreate(Bundle arguments) {
        seed = arguments != null && "true".equals(arguments.getString("seed"));
        start();
    }
    private static String hex(byte[] value) {
        StringBuilder result = new StringBuilder();
        for (byte item : value) result.append(String.format("%02x", item & 255));
        return result.toString();
    }
    private static String hash(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] buffer = new byte[65536]; int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        return hex(digest.digest());
    }
    private static void files(File base, File folder, JSONObject result) throws Exception {
        File[] children = folder.listFiles();
        if (children == null) return;
        for (File file : children) {
            if (!file.getCanonicalPath().startsWith(base.getCanonicalPath() + File.separator)) continue;
            if (file.isDirectory()) files(base, file, result);
            else if (!file.getName().endsWith(".lock") && !file.getName().endsWith("-shm") && !file.getName().endsWith("-wal")) {
                result.put(file.getAbsolutePath().substring(base.getAbsolutePath().length() + 1).replace(File.separatorChar, '/'),
                    new JSONObject().put("bytes", file.length()).put("sha256", hash(file)));
            }
        }
    }
    private static String quoted(String name) { return "\"" + name.replace("\"", "\"\"") + "\""; }
    private static JSONObject database(File file) throws Exception {
        JSONObject result = new JSONObject();
        try (SQLiteDatabase db = SQLiteDatabase.openDatabase(file.getPath(), null, SQLiteDatabase.OPEN_READONLY)) {
            result.put("user_version", db.getVersion());
            try (Cursor check = db.rawQuery("PRAGMA quick_check", null)) {
                check.moveToFirst(); result.put("integrity", check.getString(0));
            }
            JSONObject tables = new JSONObject();
            try (Cursor names = db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name", null)) {
                while (names.moveToNext()) {
                    String name = names.getString(0);
                    MessageDigest digest = MessageDigest.getInstance("SHA-256");
                    int count = 0;
                    try (Cursor rows = db.rawQuery("SELECT * FROM " + quoted(name) + " ORDER BY rowid", null)) {
                        while (rows.moveToNext()) {
                            count++;
                            for (int column=0; column<rows.getColumnCount(); column++) {
                                int type = rows.getType(column); digest.update((byte) type);
                                byte[] data = type == Cursor.FIELD_TYPE_BLOB ? rows.getBlob(column)
                                    : (type == Cursor.FIELD_TYPE_NULL ? new byte[0] : rows.getString(column).getBytes(StandardCharsets.UTF_8));
                                digest.update(java.nio.ByteBuffer.allocate(4).putInt(data.length).array());
                                digest.update(data);
                            }
                        }
                    }
                    tables.put(name, new JSONObject().put("rows", count).put("content_sha256", hex(digest.digest())));
                }
            }
            result.put("tables", tables);
        }
        return result;
    }
    @Override public void onStart() {
        Bundle output = new Bundle();
        try {
            Context context = getTargetContext();
            PackageInfo info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
            JSONObject report = new JSONObject().put("version_name", info.versionName)
                .put("version_code", android.os.Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode)
                .put("package", context.getPackageName());
            File probe = new File(context.getFilesDir(), "linesight_upgrade_acceptance_probe.bin");
            if (seed && !probe.exists()) {
                byte[] bytes = new byte[128]; new SecureRandom().nextBytes(bytes);
                try (FileOutputStream file = new FileOutputStream(probe)) { file.write(bytes); }
            }
            report.put("probe_exists", probe.isFile());
            if (probe.isFile()) report.put("probe_sha256", hash(probe));
            File base = context.getFilesDir().getParentFile();
            JSONObject persisted = new JSONObject();
            for (String name : new String[]{"files", "app_flutter", "shared_prefs", "no_backup", "databases"}) files(base, new File(base, name), persisted);
            report.put("persisted_files", persisted);
            JSONObject databases = new JSONObject();
            for (String name : context.databaseList()) {
                if (context.getDatabasePath(name).isFile() && !name.endsWith("-journal") && !name.endsWith("-wal") && !name.endsWith("-shm")) {
                    databases.put(name, database(context.getDatabasePath(name)));
                }
            }
            report.put("databases", databases);
            KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore"); keyStore.load(null);
            ArrayList<String> aliases = Collections.list(keyStore.aliases());
            ArrayList<String> hashes = new ArrayList<>();
            for (String alias : aliases) hashes.add(hex(MessageDigest.getInstance("SHA-256").digest(alias.getBytes(StandardCharsets.UTF_8))));
            Collections.sort(hashes); report.put("keystore_alias_hashes", new JSONArray(hashes));
            output.putString("stream", "LINESIGHT_STORAGE_AUDIT=" + report + "\n");
            finish(Activity.RESULT_OK, output);
        } catch (Exception failure) {
            // Do not expose stored values, credentials, keys, or raw exception messages.
            output.putString("stream", "LINESIGHT_STORAGE_AUDIT_FAILED=" + failure.getClass().getSimpleName() + "\n");
            finish(Activity.RESULT_CANCELED, output);
        }
    }
}
