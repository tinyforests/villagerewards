# Village Rewards brand standard

Approved direction · 30 September 2026. Visual reference: [Brand book](brand-book.html).

## Idea and voice

**Shop local. Score more.**

Sunny, playful and easy. Use short, warm sentences and useful information. “Your everyday favourites. Your next little treat.” Celebrate verified wins; make errors plain and actionable.

## Colour

| Token | Colour | Role |
|---|---|---|
| `--vr-white` | `#FFFFFF` | Main canvas |
| `--vr-butter` | `#FFF0A8` | Signature highlights and reward moments |
| `--vr-pink` | `#FBDCE7` | Treats and welcome cards |
| `--vr-mint` | `#D8F2E5` | Points and progress |
| `--vr-peach` | `#FFDFC8` | Supporting reward imagery |
| `--vr-sky` | `#DCEEFA` | Discovery and information |
| `--vr-ink` | `#29332F` | Essential text and primary buttons |
| `--vr-muted` | `#56635C` | Supporting text |
| `--vr-error` | `#A52A31` | Errors, always with text |

Use roughly 60% white, 30% pastel and 10% charcoal as a composition guide. Usually use two pastels per screen. Use charcoal text on pastels and white text on charcoal buttons. Purple is outside the palette. Core charcoal/pastel pairings exceed 10:1 contrast.

## Type and shapes

Nunito Sans, with Arial/sans-serif fallback. Weights 400–600 for text, 800 for controls and 900 for short headings and points. Body 16px, secondary text 14px, app headings 24–32px, points 48–72px. Allow text enlargement and wrapping.

24px card corners, 16px button corners, at least 48px action targets. Round reward badges, simple consistent illustrations and real local photography. The lowercase wordmark and small four-point sparkle are the current direction; a final logo master is still future work.

## Navigation and components

Customer navigation: labelled ☰ Menu; Show my code and Browse rewards remain visible on Home. No customer bottom bar. Use semantic controls, clear focus styles, keyboard access and Escape-to-close for menu disclosures. Admin analytical tabs may remain visible.

Reward cards show merchant, item, points required and conditions. Mock offers must be labelled before the user claims. Keep QR codes dark on white with a clear quiet zone. Keep Brand book in public footers.

Brief animation may acknowledge earned points; honour reduced motion. Do not use animation as a prerequisite for completing an action.

## Engineering ownership

`assets/brand.css` owns tokens; page styles adapt the existing HTML. `docs/redesign-concept.html` is a fictional design study and can contain proposed business rules. Do not copy those rules into production without a separate product decision and backend implementation.

The public contact address is `hello@villagerewards.com.au`, currently coming soon. Do not add an active email link until the mailbox is connected.

## Customer profile activity

Keep customer badges inside the mint points card. A butter-yellow latest-activity notice sits immediately below it. Use the actual shop name, points and known reward title. Say “you just” only for activity within five minutes, and show a timestamp for older records. Coffee/tea rewards can say “Enjoy the cuppa!”; unknown rewards use a generic message. Never invent an item from a points amount.

The profile refreshes balances, activity and badges every 15 seconds while visible and when returning to the browser tab. A confirmed reward title is available in the current redemption session; ordinary history may contain only the shop and points. Empty profiles receive an invitation to start earning. These are in-app messages, not push notifications.

## Shop window decals

The [brand book decal section](brand-book.html#window-decals) includes four 200 mm designs in butter, pink, mint and sky. Use the lowercase wordmark, sparkle, one short line and website address. Window decals also include a black-on-white 40 mm QR panel, “Scan to join”, “No download needed” and a brief earn-and-reward explanation. The QR opens `app.html?join=1`, routing visitors into the customer flow. Downloadable outlined SVG masters are in `assets/decals/`; [printer notes](../assets/decals/PRINT-NOTES.md) describe sizing, window application and proof requirements. Printers must add their own bleed and cut contour and confirm colour on the chosen material before production.
