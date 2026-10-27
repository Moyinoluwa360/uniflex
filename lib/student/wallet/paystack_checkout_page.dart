// Platform-conditional export.
//
// On Flutter web (dart.library.html is available) we use a pure-JS
// injection approach because webview_flutter does not support web.
// On Android / iOS the existing WebView implementation is used.
export 'paystack_checkout_native.dart'
    if (dart.library.html) 'paystack_checkout_web.dart';
