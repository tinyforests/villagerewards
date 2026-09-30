# Two-phone demo and NFC

## Camera scanning

1. Customer phone: open `https://villagerewards.com.au/app.html`, open the customer account and tap **Show my code**.
2. Trader phone: open the same app, sign in with the existing pilot access, and choose Purchase.
3. Tap **Scan customer QR**, allow camera access, and point at the customer phone.
4. The code fills automatically. Check the customer, enter the purchase amount and confirm points.

This uses the existing pilot database, not an isolated demo ledger. Only confirm transactions you intend to record. The customer may need to reopen their dashboard to refresh their balance.

Scanning also fills customer fields in Check-in and legacy Redeem. The gated V2 Validate tab accepts a live redemption code. Mock `DEMO-` reward codes are explicitly rejected. Scanning never awards points or validates a reward automatically.

Camera frames are decoded locally using pinned jsQR 1.4.0; no images are uploaded. Only a validated code enters the existing lookup flow. Camera tracks stop on success, close, Escape, page hide or navigation away. HTTPS and camera permission are required; manual entry remains available if the camera or decoder cannot load. Physical iPhone/Android testing is still required.

## NFC

The first NFC option is a counter tag containing an NDEF URL record pointing to `https://villagerewards.com.au/app.html`. Print a QR fallback alongside it. The phone’s operating system opens the link; the website does not need to read NFC directly. Tags must be purchased, programmed and tested separately.

A tag tap opens the app; it does not prove a purchase or grant points. Shop-specific links would need a separate routing design. Phone-to-phone NFC and card emulation are not supported by Web NFC, so use camera-to-screen QR for the two-phone web demo.

Sources: [Chrome Web NFC capabilities](https://developer.chrome.com/docs/capabilities/nfc), [Apple background tag reading](https://developer.apple.com/documentation/CoreNFC/adding-support-for-background-tag-reading), [jsQR](https://github.com/cozmo/jsQR).
