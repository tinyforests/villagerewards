# Village Rewards

Independent spend-based QR loyalty web app for village traders in Melbourne.

## Start here

- `AGENTS.md`: engineering brief and current source state.
- `AI_CONTEXT.md`: product voice and principles.
- `docs/BRAND.md`: implementation rules for the independent identity.
- `docs/brand-book.html`: visual reference.

## Current state

Customer registration, point history and QR code generation exist. Trader login fetches a pilot code from Supabase `pilot_config`. Admin Supabase Auth email magic-link login and an `admin_users` allowlist check are implemented in code. These facts preserve the current auth work; deployed Supabase configuration has not been verified.

Admin configuration requires the Email provider, authorised redirect URL, an `admin_users` table and appropriate access policies. Trader configuration currently expects a `trader_pilot_code` row. The shared pilot-code approach is not secure authentication and should be replaced before wider rollout.

Real reward tiers, stamp cards, redemption RPC calls and `docs/schema-v2.sql` exist. `DEMO_MODE = true` exposes example rewards and mock redemption codes; `DEV_MODE = true` bypasses client proximity eligibility. Do not repeat the older claim that both auth flows are disabled or GPS is enforced.

## Brand and implementation

Use the white and pastel identity: butter yellow, pink, mint, supporting peach and sky blue; charcoal text; Nunito Sans. Rounded cards and buttons, visible primary actions, labelled hamburger customer menu. Brand book belongs in public footers. Use shared tokens in `assets/brand.css`.

Static HTML/CSS/JS, Supabase backend, GitHub Pages hosting, no build step. Keep working flows intact when changing presentation. Tier redemption currently resets all points; the separate design study’s points-deduction proposal is not implemented in the app.

## Next work

Verify database policy and migration state; secure customer/trader identity; test atomic earning, redemption caps and concurrent stamp claims; complete the manifest/icons; separate demo from live behaviour.

Public contact: `hello@villagerewards.com.au` is not yet connected. Show “coming soon” without an active mail link.
