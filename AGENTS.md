# Village Rewards engineering brief

Repository: `github.com/tinyforests/villagerewards` · Updated 30 September 2026

## Product

Village Rewards is an independent web loyalty platform for local village traders and customers. The current pilot is in Mont Albert, Melbourne. Customers collect points across participating shops and explore merchant rewards.

## Brand source of truth

Read `docs/BRAND.md` and `docs/brand-book.html` before changing presentation or copy. Shared tokens live in `assets/brand.css`.

- Promise: **Shop local. Score more.**
- Personality: sunny, playful and easy.
- White canvas; butter yellow signature; pink and mint main accents; peach and sky blue supporting accents.
- Charcoal text and primary buttons. Nunito Sans throughout, bold short headlines and readable body text.
- Cards use 24px corners, buttons 16px corners and at least 48px tap targets.
- Customer navigation uses a labelled hamburger menu. Keep Show my code and Browse rewards visible on Home. Do not introduce a customer bottom navigation bar.
- Keep a Brand book link in public footers.
- Use clear reward prices, conditions and availability. Identify demo data and offers as examples.
- Honour reduced motion and keep contrast strong.

## Repository and deployment

Static HTML/CSS/JavaScript with no build step, deployed through GitHub Pages at `villagerewards.com.au`. Backend: Supabase, project `hwtwfhvaeczofqktychc.supabase.co`. Public anon keys in frontend source are expected; authorisation must be enforced in the backend.

- `index.html`: consumer homepage, trader information and brand-book footer.
- `app.html`: customer and trader app, with existing demo and database-backed flows.
- `village-rewards-admin.html`: analytics and admin magic-link UI.
- `ma-presentation.html`: trader presentation.
- `village-rewards-pwa.html`: legacy URL redirects to `app.html`.
- `assets/brand.css`: shared identity tokens and accessibility defaults.
- `assets/app-brand.css`, `admin-brand.css`, `presentation-brand.css`: page-specific presentation.
- `assets/customer-activity.js`: transaction-based profile copy; badges live inside the score card; visible profiles refresh every 15 seconds.
- `assets/qr-scanner.js`: camera QR reader using pinned jsQR; fills existing trader fields, never auto-confirms transactions.
- `sw.js`: service worker; increment cache version when changing cached app assets.
- `docs/brand-book.html`: visual brand reference; `docs/BRAND.md`: implementation rules.
- `docs/schema-v2.sql`: checked-in tier, stamp and redemption migration, not proof of deployed state.
- `docs/redesign-concept.html`: isolated fictional design study, not the live app.

## Current source state, not deployment verification

- Customer registration and returning access use email lookup and a customer ID in localStorage. This is not verified customer authentication.
- Trader pilot login compares a shared code fetched from `pilot_config`. Moving it out of the source does not make a publicly readable code secure.
- Admin email magic-link auth is implemented, including an `admin_users` allowlist lookup. Supabase configuration and database authorisation must be verified separately.
- `DEMO_MODE = true`: mock tier offers and mock redemption QR codes are exposed in the customer experience. The app labels this demo and keeps real earning separate.
- `DEV_MODE = true`: the client proximity eligibility check is bypassed. Do not describe GPS enforcement as active. Backend enforcement is unverified.
- Real reward/stamp RPC calls exist. The SQL includes customer locking for tier validation, but ownership, stamp concurrency and monthly caps need review.
- A service worker exists. Manifest and icon assets are still absent; do not claim installation is fully verified.

## Business rules

Current source: $1 spent earns 1 point, rounded to the nearest whole point. Check-ins award 8 points with a client-side four-hour eligibility check per shop. Legacy redemption expresses 100 points as $1.

The tier implementation resets the entire village balance when a merchant confirms redemption. Stamp rewards affect their own card. The design study proposes retaining excess points; that is not an approved or deployed business-rule change. Do not change financial or earning logic as part of a visual redesign.

## Engineering priorities

1. Verify deployed schema, policies, functions and auth configuration against checked-in source.
2. Bind customer and trader operations to verified identity; scope reads to authorised users.
3. Enforce earning rules, cooldowns, monthly caps and redemption consistency on the server.
4. Separate demo from production behaviour before broader rollout.
5. Complete PWA manifest/icons and test mobile browser and standalone modes.

Run syntax and local-link checks after page edits. For interaction changes, check keyboard navigation and mobile layout. Stub the backend during UI tests to avoid production writes. Do not claim production security or successful deployment based on local source checks.

## Public contact

`hello@villagerewards.com.au` is planned but not connected yet. Show it as coming soon without a mail link until Tyson confirms the mailbox is active.

## Reading order

`AI_CONTEXT.md` → `docs/BRAND.md` → this brief → `docs/SCHEMA.md` / `docs/SECURITY.md` / `docs/TIERED-SYSTEM.md` as required. `SUPER_MIND.md` is a compatibility pointer to the current independent product context.
