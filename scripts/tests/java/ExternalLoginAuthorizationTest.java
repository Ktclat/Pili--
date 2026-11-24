package com.example.piliplus;

import java.net.URI;
import java.util.Map;

/** Executed by the existing Android validation workflow using its JDK 17. */
public final class ExternalLoginAuthorizationTest {
    private static final String WEB = "https://account.bilibili.com/h5/account-h5/auth/scan-web";
    private static final String TV = "https://passport.bilibili.com/x/passport-tv-login/h5/qrcode/auth";
    private static final String KEY = "0123456789abcdef0123456789abcdef";

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static void expectInvalid(ExternalLoginAuthorization inbox, String link, boolean fresh) {
        inbox.receive(link, fresh, 1000);
        check(inbox.take(1001).equals(Map.of("url", "", "ageMs", 0L)), "expected an invalid marker");
        check(inbox.take(1002) == null, "invalid marker was replayed");
    }

    public static void main(String[] args) {
        String web = WEB + "?qrcode_key=" + KEY;
        String tv = TV + "?auth_code=" + KEY;
        ExternalLoginAuthorization inbox = new ExternalLoginAuthorization();
        for (String link : new String[] {web, tv, "https://passport.bilibili.com/h5-app/passport/login/scan",
                "https://passport.bilibili.com/h5-app/passport/login/scan-pad",
                "http://visitor@PASSPORT.bilibili.com:123/qrcode/h5/login",
                "https://passport.bilibili.com/h5-app/passport/login/sub/../scan/"}) {
            URI uri = URI.create(link);
            check(ExternalLoginAuthorization.isTarget(uri.getAuthority(), uri.getPath()), "missed a protected path");
        }
        check(!ExternalLoginAuthorization.isTarget("passport.bilibili.com.example.org", "/qrcode/h5/login"), "lookalike host");
        check(!ExternalLoginAuthorization.isTarget("passport.bilibili.com", "/other"), "ordinary passport page");
        check(!ExternalLoginAuthorization.isTarget("www.bilibili.com", "/video/av1"), "ordinary Bilibili link");
        check(!ExternalLoginAuthorization.isTarget(null, null), "missing URL");

        check(inbox.receive(web, true, 1000), "first request starts timer");
        check(!inbox.receive(tv, true, 1050), "later request must not restart the timer");
        check(!inbox.receive(web, false, 1100), "history cannot replace a live request");
        check(inbox.take(1210).equals(Map.of("url", web, "ageMs", 210L)), "first pending request and original age");
        check(!inbox.hasPending() && inbox.take(1210) == null, "atomic consumption");
        inbox.receive(web, true, 1000);
        check(inbox.take(1000 + ExternalLoginAuthorization.MAX_AGE_MS).get("url").equals(""), "expiry boundary");
        inbox.receive(tv, true, 1000);
        inbox.expire();
        check(inbox.take(1001).get("url").equals(""), "drop waiting challenge from memory");
        inbox.receive(web, true, 1000);
        check(inbox.receive(tv, true, 1000 + ExternalLoginAuthorization.MAX_AGE_MS), "fresh launch replaces expired request");
        check(inbox.take(1001 + ExternalLoginAuthorization.MAX_AGE_MS).equals(Map.of("url", tv, "ageMs", 1L)), "replacement age");
        expectInvalid(inbox, web, false);
        // An explicit component invocation can bypass every Manifest data constraint.
        for (String invalid : new String[] {null, "not a URL", "https://unrelated.example/?qrcode_key=" + KEY,
                "https://www.bilibili.com/video/av1?x=1", "https://passport.bilibili.com/other?x=1",
                WEB, WEB + "?", web + "#", web + "%XX",
                web.replace("https:", "http:"), web.replace("https://", "https://guest@"),
                web.replace(".com/", ".com:8443/"), web.replace("/scan-web", "/encoded/../scan-web"),
                "https://passport.bilibili.com/qrcode/h5/login?x=1", web + "x".repeat(2048)}) {
            expectInvalid(inbox, invalid, true);
        }
    }
}
