package com.example.piliplus;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.HashMap;
import java.util.Map;

/** The one pending Android authorization handoff, kept on the main thread and never written to saved state. */
final class ExternalLoginAuthorization {
    static final long MAX_AGE_MS = 3 * 60 * 1000L;
    private static final String ACCOUNT = "account.bilibili.com";
    private static final String PASSPORT = "passport.bilibili.com";
    private static final String OLD_LOGIN_PATH = "/qrcode/h5/login";

    private String pending;
    private long receivedAt;

    // Android Uri is tolerant of malformed syntax. Identify the destination before
    // strict validation so an invalid login challenge cannot reach a generic WebView.
    static boolean isTarget(String authority, String path) {
        if (authority == null || path == null) return false;
        String host = authority.substring(authority.lastIndexOf('@') + 1);
        int port = host.indexOf(':');
        if (port >= 0) host = host.substring(0, port);
        if (!ACCOUNT.equalsIgnoreCase(host) && !PASSPORT.equalsIgnoreCase(host)) return false;
        if (isLoginPath(host, path)) return true;
        try {
            String normalized = new URI(null, null, path, null).normalize().getPath();
            if (normalized.endsWith("/")) normalized = normalized.substring(0, normalized.length() - 1);
            return isLoginPath(host, normalized);
        } catch (URISyntaxException ignored) {
            return false;
        }
    }

    private static boolean isLoginPath(String host, String path) {
        if (ACCOUNT.equalsIgnoreCase(host)) return "/h5/account-h5/auth/scan-web".equals(path);
        return PASSPORT.equalsIgnoreCase(host) &&
                ("/h5-app/passport/login/scan".equals(path) ||
                 "/h5-app/passport/login/scan-pad".equals(path) ||
                 "/x/passport-tv-login/h5/qrcode/auth".equals(path) || OLD_LOGIN_PATH.equals(path));
    }

    boolean receive(String raw, boolean fresh, long now) {
        // Preserve the first still-live handoff, including its original expiry timer.
        if (pending != null && !pending.isEmpty() && now >= receivedAt && now - receivedAt < MAX_AGE_MS) {
            return false;
        }
        pending = "";
        receivedAt = now;
        if (!fresh || raw == null || raw.length() > 2048) return true;
        try {
            URI uri = new URI(raw);
            String host = uri.getHost();
            String authority = uri.getRawAuthority();
            String path = uri.getRawPath();
            if (host != null && "https".equalsIgnoreCase(uri.getScheme()) &&
                    (host.equalsIgnoreCase(authority) || (host + ":443").equalsIgnoreCase(authority)) &&
                    isLoginPath(host, path) && !OLD_LOGIN_PATH.equals(path) &&
                    uri.getRawFragment() == null && uri.getRawQuery() != null && !uri.getRawQuery().isEmpty()) {
                // Only the shared Dart challenge parser accepts a key and query parameters.
                pending = raw;
            }
        } catch (URISyntaxException ignored) {
            // Exception text can include the complete URL. Return only the invalid marker.
        }
        return true;
    }

    void expire() {
        if (pending != null) pending = "";
    }

    boolean hasPending() {
        return pending != null;
    }

    Map<String, Object> take(long now) {
        String value = pending;
        pending = null;
        if (value == null) return null;
        long age = now - receivedAt;
        boolean usable = !value.isEmpty() && age >= 0 && age < MAX_AGE_MS;
        Map<String, Object> result = new HashMap<>(2);
        result.put("url", usable ? value : "");
        result.put("ageMs", usable ? age : 0L);
        return result;
    }
}
