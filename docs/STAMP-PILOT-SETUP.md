# Stamp pilot staging setup

Prepared 26 October 2026. The user selected preparation for a new staging project.

## What is implemented

`stamp-pilot.html` is an isolated candidate for the new customer/trader app. The live `app.html` remains the legacy points implementation. No production records have been changed and no historical point balance has been relabelled as stamps.

The candidate includes verified email sign-in, one stamp per staff-confirmed purchase, a shared marketplace, voluntary merchant offer creation and pause, claims, collection, cancellation, expiry, reversible purchase awards, customer activity and a shop-scoped purchase list. Basic participation has no subscription logic. Local tests exercise the actual SQL migration in embedded PostgreSQL plus the browser against that local database.

## Create the staging environment

1. Create a new Supabase project owned by the Village Rewards organisation. Choose the appropriate region and record the owner, access arrangements and operating costs. Use a distinct project from production.
2. In its SQL editor, run `supabase/staging-bootstrap.sql`, then `supabase/migrations/202610260001_stamp_pilot.sql`. The migration is a once-only migration, not a rerunnable reset script. Record the applied version.
3. Configure the project's email sign-in provider, site URL and exact allowed staging callback URL ending in `/stamp-pilot.html`. Verify actual email delivery and rate limits in this environment. Never use a wildcard production redirect for convenience.
4. Put only that project's public URL and public anon key into `assets/stamp-config.js`. Never use a service-role key in browser configuration. The branch now contains the isolated staging project’s public connection details; the app refuses sign-in if configuration is removed.
5. Serve this branch at a separate staging origin with HTTPS. Do not point the production `app.html` at it yet. Do not test using real customer data.
6. Add confirmed staging shops using the SQL editor. Have staff sign in with verified email and grant only their shop memberships using the SQL below.
7. Run the automated tests and the physical-device checklist. Archive test evidence, deployed SQL and Auth settings before approving rollout.

```sql
-- Substitute verified Auth user and shop UUIDs. Only an authorised operator runs this.
INSERT INTO public.vr_staff(user_id, shop_id)
VALUES ('STAFF_AUTH_UUID', 'SHOP_UUID');
```

There is no public endpoint for granting staff access. Do not expose the SQL editor or elevated key to traders. Never infer staff entitlement from an email address supplied in the browser.

## Staging choices needing product approval

- A unique receipt reference at each shop identifies a completed purchase. Retrying the same receipt does not earn again, even with a different request ID. Multiple genuine purchases can earn multiple stamps; no daily cap has been silently restored.
- Claims reserve stock and deduct the displayed cost from available stamps for 15 minutes. Cancellation or expiry returns both. Collection consumes the reservation once. Existing claim terms are a snapshot and remain valid if an offer is paused.
- Expiry cleanup runs on dashboard, claim and shop actions. A reservation is invalid at its expiry even if cleanup has not run. For unattended volume, schedule an owner-authorised cleanup transaction that takes `vr_lock()` then calls `vr_release_expired()`; do not grant those helpers to browser roles.
- A reversed purchase removes its stamp once. If the balance is already spent, reversal is refused for support resolution. Agree the full refund/debt policy before public launch.
- No automatic conversion of legacy points; no expiry of earned stamps has been invented. Decide and communicate both policies before migration.
- Offer creation is idempotent for a request. Pausing blocks new claims, not already accepted claims. To change terms, pause the old offer and create a new one; already reserved inventory must not be sold twice.

## Tests

```sh
npm ci
npm test
npx playwright install chromium
npm run test:browser
```

An existing Chrome can be used for tests by setting `CHROME_PATH` to its executable. Browser tests block all external network requests, use test identities and execute the migration against a local PGlite database. They do not establish real Supabase email delivery, network concurrency, browser camera support or deployed policy correctness.

The mutation functions use a single row lock to serialise pilot writes and stock changes. Test parallel requests from independent connections on staging before launch; embedded PostgreSQL test calls are serialised and cannot certify real multi-session races. Load-test before expanding beyond the pilot.

## Physical and deployed acceptance

- Verify email sign-in and returning sessions on real iPhone and Android browsers, plus logout on shared staff devices.
- Use separate customer and staff accounts. Verify customer isolation, wrong-shop rejection, direct-table denial and blocked anonymous RPC access against deployed Supabase.
- Confirm 30 stamps less a 10-stamp claim leaves 20. Claim the last stock item simultaneously from two accounts; exactly one must succeed.
- Retry after an interrupted award, offer creation and claim. Reuse receipt references across staff accounts; no duplicate award. Attempt mismatched replay and ensure rejection.
- Validate camera permission allowed/denied, close/Escape, manual entry, customer versus claim codes and invalid legacy codes. Scanning must never confirm a purchase or collection.
- Confirm expiry and cancellation return stock and stamps once; fulfilled, wrong-shop, cancelled and expired codes cannot be collected again.
- Verify stock exhaustion, inactive merchants, paused offers, refunded purchases, keyboard navigation, enlarged text and refresh after restoring network access.
- Assign support, backup/recovery, reward contributors and a funded operating owner. Confirm the customer-facing conditions.

## What is deliberately not enabled

Separate shop loyalty cards, a six-shop prize draw, automatic point conversion, billing and a new admin analytics dashboard are not implemented in this first candidate. The displayed distinct-shop count is lifetime exploration progress, not a campaign entry. The old admin dashboard reads the old points tables and cannot report the new stamp ledger.

## Production release

Do not merge a route change or deploy the migration to the existing project until the legacy schema/policies have been audited. The additive tables secure the new path; they do not fix any permissive legacy endpoints. Approve a legacy-balance conversion separately, back up and reconcile it, revoke obsolete writes, then switch the main app and update the service-worker cache. A new project rollout also requires an explicit data migration and origin/Auth cutover plan. Never wipe legitimate live activity to roll back.

## Deployment evidence — 26 October 2026

- Preview: https://tinyforests.github.io/villagerewards-staging/
- Preview repository: https://github.com/tinyforests/villagerewards-staging (public publication approved by Tyson).
- Supabase: `village-rewards-staging`, ref `dbxzlznscwstjklphstv`, Sydney. Bootstrap and migration `202610260001_stamp_pilot` applied successfully.
- Site URL is the preview root. Exact callback allowlist includes `stamp-pilot.html`, `index.html` and `app.html` under that root. Email confirmation remains enabled; anonymous sign-in remains disabled.
- GitHub Pages build succeeded; root returned HTTP 200 and sign-in screen rendered in Chrome.
- Live anonymous API checks returned HTTP 401 / PostgreSQL 42501 for both `vr_dashboard` and direct `vr_members` reads. This is limited evidence, not a complete deployed security audit.
- Local ledger tests (7), customer activity checks and JavaScript syntax checks passed.
- Custom SMTP is not configured. Supabase’s default sender is restricted to project team addresses and currently two emails per hour: https://supabase.com/docs/guides/auth/auth-smtp . Real sign-in delivery, authenticated acceptance, staff assignment, device and concurrent-request testing remain outstanding.
- No production cutover, legacy conversion, customer import or real reward stock has been performed. The preview marketplace starts empty.

The staging repository is a static copy, not an automatic deployment of the source branch. When updating it, copy the candidate and its dependencies only; keep `index.html` and `app.html` identical to `stamp-pilot.html`. Do not copy the production CNAME, service worker or legacy app.
