package com.linesight.acceptance;

import android.content.Context;
import android.net.Uri;
import android.os.AsyncTask;
import java.lang.reflect.Constructor;
import java.lang.reflect.Proxy;
import java.util.Collections;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** Instrumentation only. Reflection targets the frozen 8078 R8 mapping, not a test copy of AppAuth. */
final class NativePrivacyAudit {
    static JSONObject run(Context context) throws Exception {
        JSONArray cases = new JSONArray();
        for (String mode : new String[]{"oauth", "malformed", "transport"}) {
            String marker = "LS_NATIVE61_" + mode.toUpperCase() + "_CANARY";
            CountDownLatch completed = new CountDownLatch(1);
            AtomicReference<Object> failure = new AtomicReference<>();
            ClassLoader loader = context.getClassLoader();
            Class<?> connectionClass = loader.loadClass("z8.a");
            Object connection = Proxy.newProxyInstance(loader, new Class<?>[]{connectionClass}, (proxy, method, arguments) -> {
                    return new HttpURLConnection(new URL("https://example.invalid/token")) {
                        final byte[] body = (mode.equals("oauth")
                            ? "{\"error\":\"invalid_grant\",\"error_description\":\"" + marker + "\"}"
                            : marker).getBytes(StandardCharsets.UTF_8);
                        public void connect() {}
                        public void disconnect() {}
                        public boolean usingProxy() { return false; }
                        public int getResponseCode() throws IOException {
                            if (mode.equals("transport")) throw new IOException(marker);
                            return mode.equals("oauth") ? 400 : 200;
                        }
                        public OutputStream getOutputStream() { return new ByteArrayOutputStream(); }
                        public InputStream getInputStream() { return new ByteArrayInputStream(body); }
                        public InputStream getErrorStream() { return new ByteArrayInputStream(body); }
                    };
                });
                Class<?> configClass = loader.loadClass("x8.m");
                Constructor<?> configCtor = configClass.getDeclaredConstructor(Uri.class, Uri.class, Uri.class, Uri.class);
                configCtor.setAccessible(true);
                Object config = configCtor.newInstance(Uri.parse("https://example.invalid/authorize"), Uri.parse("https://example.invalid/token"), null, null);
                Class<?> requestClass = loader.loadClass("x8.x");
                Constructor<?> requestCtor = requestClass.getDeclaredConstructors()[0];
                requestCtor.setAccessible(true);
                Object request = requestCtor.newInstance(config, "linesight-audit", null, "refresh_token", null, null, null, "synthetic-not-a-real-token", null, Collections.emptyMap());
                Class<?> callbackClass = loader.loadClass("x8.j");
                Object callback = Proxy.newProxyInstance(loader, new Class<?>[]{callbackClass}, (proxy, method, arguments) -> {
                    failure.set(arguments[1]);
                    completed.countDown();
                    return null;
                });
                Object client = loader.loadClass("x8.w").getField("a").get(null);
                Class<?> taskClass = loader.loadClass("x8.i");
                Constructor<?> taskCtor = taskClass.getDeclaredConstructors()[0];
                taskCtor.setAccessible(true);
                AsyncTask task = (AsyncTask) taskCtor.newInstance(request, client, connection, callback, false);
                task.executeOnExecutor(AsyncTask.THREAD_POOL_EXECUTOR, new Void[0]);
                if (!completed.await(20, TimeUnit.SECONDS) || failure.get() == null)
                    throw new IllegalStateException("Expected native error callback missing");
                Object error = failure.get();
                if (mode.equals("oauth") && !"invalid_grant".equals(error.getClass().getField("k").get(error)))
                    throw new IllegalStateException("Unexpected OAuth classification");
                boolean containsMarker = error.toString().contains(marker)
                    || (((Throwable) error).getCause() != null && ((Throwable) error).getCause().toString().contains(marker));
                if (!containsMarker) throw new IllegalStateException("Synthetic fault did not reach callback");
                cases.put(new JSONObject().put("mode", mode).put("callback_error_received", true)
                    .put("callback_contains_synthetic_marker", containsMarker)
                    .put("error_type", error.getClass().getField("i").get(error)).put("error_code", error.getClass().getField("j").get(error)));
        }
        return new JSONObject().put("pid", android.os.Process.myPid()).put("cases", cases)
            .put("transport", "in-memory; no external network")
            .put("customer_accounts_used", false).put("persistent_data_written", false);
    }
}
