;(function () {
    // 用于兼容不同环境
    var originalCookieSetter = document.__lookupSetter__ && document.__lookupSetter__("cookie");
    var originalCookieGetter = document.__lookupGetter__ && document.__lookupGetter__("cookie");

    // 通知原生环境同步
    function syncCookieToNative(cookieStr) {
        var message = {
            cookie: cookieStr,
            url: document.location.href
        };
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.EMASCurlWebMessageHandler &&
            window.webkit.messageHandlers.EMASCurlWebMessageHandler.postMessage) {
            window.webkit.messageHandlers.EMASCurlWebMessageHandler.postMessage({
                method: "syncCookie",
                params: message
            });
        }
    }

    // 若原生 setter/getter 存在，直接覆盖
    if (originalCookieSetter && originalCookieGetter) {
        Object.defineProperty(document, "cookie", {
            set: function (cookieStr) {
                if (typeof cookieStr !== "string") return;
                syncCookieToNative(cookieStr);
                originalCookieSetter.call(document, cookieStr);
            },
            get: function () {
                return originalCookieGetter.call(document);
            },
            configurable: false
        });
        return;
    }
})();
