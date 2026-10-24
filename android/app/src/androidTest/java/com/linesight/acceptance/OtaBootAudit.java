package com.linesight.acceptance;

import android.app.Instrumentation;
import android.content.Context;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.security.MessageDigest;
import java.util.HashMap;
import java.util.Map;
import org.json.JSONArray;
import org.json.JSONObject;

/** Separate audit APK only; local fault payload is never published to OTA. */
final class OtaBootAudit {
    static JSONObject run(Instrumentation instrumentation, Bundle arguments) throws Exception {
        Context context = instrumentation.getTargetContext();
        if (!"ranchu".equals(android.os.Build.HARDWARE))
            throw new IllegalStateException("Emulator only");
        String mode = arguments.getString("otaMode", "inspect");
        File patch = new File(context.getFilesDir(), "flutter_patcher/libapp_patch.so");
        JSONObject result = new JSONObject().put("mode", mode).put("pid", android.os.Process.myPid());
        if (mode.equals("framework") || mode.equals("asynchronous")) {
            File staged = new File(context.getCacheDir(), "ota67-local-fault.so");
            try (ParcelFileDescriptor descriptor = instrumentation.getUiAutomation()
                    .executeShellCommand("cat /data/local/tmp/linesight-ota-boot-fault.so");
                 FileInputStream input = new FileInputStream(descriptor.getFileDescriptor());
                 FileOutputStream output = new FileOutputStream(staged)) {
                byte[] block = new byte[65536]; int count;
                while ((count = input.read(block)) != -1) output.write(block, 0, count);
            }
            MessageDigest digest = MessageDigest.getInstance("MD5");
            try (FileInputStream input = new FileInputStream(staged)) {
                byte[] block = new byte[65536]; int count;
                while ((count = input.read(block)) != -1) digest.update(block, 0, count);
            }
            StringBuilder md5 = new StringBuilder();
            for (byte value : digest.digest()) md5.append(String.format("%02x", value & 255));
            try (FileOutputStream output = new FileOutputStream(new File(context.getCacheDir(), "ota67-fault-mode.txt"))) {
                output.write(mode.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            }
            // Frozen production 8078 R8 mapping is checked by the host verifier.
            Class<?> type = context.getClassLoader().loadClass("o3.n");
            Constructor<?> constructor = type.getDeclaredConstructors()[0];
            constructor.setAccessible(true);
            Object manager = constructor.newInstance(context, null);
            Method apply = type.getDeclaredMethod("b", Map.class);
            apply.setAccessible(true);
            Map<String,Object> values = new HashMap<>();
            values.put("version", "local-ota67-" + mode);
            values.put("patchUrl", staged.toURI().toString());
            values.put("md5", md5.toString());
            values.put("targetVersionCode", 8078L);
            Object installed = apply.invoke(manager, values);
            result.put("install_result", installed.toString());
        }
        result.put("patch_exists", patch.isFile());
        String blacklist = context.getSharedPreferences("flutter_patcher_prefs", Context.MODE_PRIVATE)
            .getString("patch_blacklist", "[]");
        result.put("blacklist", new JSONArray(blacklist));
        result.put("customer_accounts_used", false).put("public_patch_published", false);
        return result;
    }
}
