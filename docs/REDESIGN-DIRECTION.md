# Village Rewards: shop local, score more

Design study and source review · 30 September 2026

## Direction

Make Village Rewards an independent consumer brand. The approved brief uses white, happy pastels, bold sans-serif typography and rounded controls. Lead with the reward people want and how soon they can get it.

**Promise:** Shop local. Score more.

**Supporting copy:** Your coffee runs, lunch breaks and local favourites. All adding up to your next treat.

Updated after feedback: use white as the main surface, with butter yellow, blush pink and mint. Use charcoal for text and primary buttons; remove violet as the dominant brand colour. Rounded cards, bold sans-serif headings, large readable numbers and generous tap targets. Prize illustrations or photography should make rewards tangible. Motion belongs at earned moments: points arriving, a milestone unlocking, a reward being confirmed. Respect reduced motion.

The accompanying `redesign-concept.html` is a local, interactive design study with fictional offers and balances. It has no backend connection. Its proposed points-deduction rule differs from the current reset-to-zero implementation. None of these illustrative offers are merchant commitments.

## What to borrow from rewards programs

| Reference | Observed pattern | Village Rewards application |
|---|---|---|
| [Bubblehouse gamified loyalty](https://www.bubblehouse.com/gamified-loyalty) | Achievements combine actions and milestone rewards; examples show explicit progress counts. | A village trail: shop at three distinct traders, see three stamps fill, earn a stated bonus. |
| [Bubblehouse points and rewards](https://www.bubblehouse.com/rewards-and-points) | Configurable earning and redemption alongside other loyalty features. | One legible points wallet, with clearly priced rewards and visible ways to earn. |
| [Everyday Rewards](https://www.everyday.com.au/) | Boost, shop, enjoy; offers explicitly activate bonus earning. | One-tap merchant boosts with visible qualification rules, end dates and funding limits. |
| [Starbucks Rewards, March 2026 launch](https://about.starbucks.com/press/2026/reimagined-starbucks-rewards-loyalty-program-launches-with-new-member-benefits/) | Green, Gold and Reserve levels offer increasing benefits and earning power. | Keep long-term achievement separate from spendable points, so redemption preserves a customer's sense of progress. |

These are design inferences from public product material, not evidence that the same features will increase Village Rewards retention. Natasha's open Bubblehouse session could not be inspected because the computer tool failed to initialise twice.

## The customer experience

1. **Before joining:** show example rewards and participating shops. Primary action: Join free. Put trader acquisition on its own route.
2. **Home:** points, one chosen reward, distance to that reward, and one obvious Show my code action. Show usable rewards before transaction history.
3. **Rewards:** browse by desired item and availability. Show merchant, points required, conditions and availability before confirmation.
4. **Missions:** start with one village trail. Reward verified visits or purchases across distinct shops; avoid making customers learn several currencies.
5. **Win moment:** acknowledge the verified action, show the exact points gained, update progress, then offer one relevant next step.

Navigation: Home / Rewards / My code / Missions. Account and history can sit behind the profile entry. The trader interface should optimise for speed: identify customer, enter spend, confirm; reward validation should clearly identify the item and customer.

## Mechanics worth testing

- **Next reward:** “3 points to your next treat” with the actual item visible.
- **Village trail:** a stated bonus for qualifying purchases at three different shops in a defined period. This directly supports cross-shop discovery.
- **Merchant boosts:** funded bonus points for quiet periods or new-shop discovery. Show terms before activation.
- **Repeat visits:** flexible weekly milestones with visible progress; keep earned rewards and lifetime achievements.
- **Referrals:** award only after a new customer's first qualifying transaction, with duplicate and self-referral checks.
- **Celebration:** brief point count-up and a reveal for an earned reward. Keep essential actions immediate and readable.

Use the anticipation and celebratory energy of pokies through colour, movement and clear payoff. Start with deterministic rewards. Random prizes would be a separate product decision with disclosed mechanics and a defined budget.

### Change the points reset rule

Recommendation: deduct the displayed reward price and retain the remainder. A customer with 47 points redeeming a 10-point coffee keeps 37. Maintain lifetime progress separately. Current code instead erases the full balance after tier redemption, which creates a reason to postpone small redemptions. This is a proposed product change, not an implemented migration.

Reward economics must be reconciled before launch: the dashboard currently expresses 100 points as $1, while demo rewards offer a coffee at 10 points. Choose a single explanation customers can trust. Start with merchant-approved inventory, caps and funding; calibrate earning and prices against actual redemption cost.

## Source review: the brief is stale

Reviewed the local source and SQL, not deployed Supabase policies or production behaviour. Existing uncommitted `CLAUDE.md` changes were left alone.

| Finding | Evidence | Consequence |
|---|---|---|
| Earlier appearance needed replacement | `app.html:20` palette/type tokens; `index.html:1073` describes a “shared economic layer” | Replace identity and lead with a concrete consumer benefit. |
| Demo rewards override the real entry point | `app.html:1801` enables DEMO_MODE; `renderTierProgressDemo()` hides the real rewards CTA | Separate demo and live flows before launching the redesign. |
| GPS bypass is enabled | `app.html:1326`, `DEV_MODE = true` | The handoff's claim of active proximity enforcement is inaccurate. |
| Returning customer access uses email lookup without verification | `app.html:896–906`; ID persisted in localStorage | Implement verified customer identity and server-side ownership checks. Actual exposure depends on deployed RLS. |
| Trader login is active and compares a fetched shared pilot code | `app.html:1017–1043`; nearby setup instructions allow anonymous config reads | Moving a shared code to an anonymously readable table does not make it a secure credential. |
| Admin magic-link code exists | `village-rewards-admin.html:531–590` | Verify deployed auth and database authorisation; do not rebuild from the assumption that auth is entirely absent. |
| Schema and RPC work already exists | `docs/schema-v2.sql` | Preserve useful reward/stamp logic. Verify migration state against Supabase before changing it. |
| Redemption reads are broad in the checked-in SQL | `docs/schema-v2.sql:394`, `USING (true)` | Scope redemption visibility to its customer or authorised merchant. |
| Customer RPCs trust a supplied customer ID | `redeem_reward()` is SECURITY DEFINER, accepts `p_customer_id`, and has no ownership check; grants include anon | Bind customer actions to a verified identity. |
| Tier validation locks the customer, but stamp validation lacks a shared lock before checking stamp progress | `validate_redemption()` | Concurrent pending stamp redemptions need a transaction test and appropriate locking. |
| Monthly cap counts validated claims at initiation | `redeem_reward()`; no matching cap check at validation | Multiple pending claims can exceed a cap. Reserve inventory atomically or enforce the cap when confirming. |
| Browser directly inserts earning transactions | `awardPurchasePoints()`, `awardCheckin()`, `doCheckin()` | Verify deployed policies/triggers; put earning rules, ownership and cooldown checks behind authorised server operations. |
| No manifest or icon assets found | Repository file inventory; `sw.js` references icons | Complete PWA assets and verify installation/offline behaviour. |

## Implementation order

1. Agree the consumer identity and points model using the clickable study.
2. Extract shared styles and split the large app script into customer, trader and data modules. Keep static hosting; a framework migration is not required to achieve the design.
3. Build Home, Rewards, code display and confirmation against a clearly isolated demo data adapter.
4. Reconcile deployed schema/RLS with source; secure customer/trader identity, earning and redemption. Test ownership, concurrent claims, caps and cooldowns.
5. Connect verified flows, remove mixed demo hooks, add install assets and test on real phones and at a trader counter.
6. Pilot one mission and one boost. Measure join-to-first-earn, time to first reward, second-shop visits, repeat visits, redemption completion and merchant cost per returning customer. Track support problems and reward availability alongside engagement.

The first release should make ordinary earning and redemption delightful. Expand the game mechanics after proving that customers understand the rules and traders can fulfil rewards quickly.

## Navigation follow-up

The September 30 revision keeps the bottom navigation for comparison and updates the palette to white and pastels. Navigation choice is still open.

NN/g’s [2016 hidden navigation study](https://www.nngroup.com/articles/hamburger-menus/) found poorer discoverability with hidden navigation. Its [2025 hamburger recognition research](https://www.nngroup.com/articles/hamburger-menu-icon-recognizability/) finds the icon more familiar, while noting that hidden navigation still has discoverability costs. This supports keeping frequent actions visible; it does not establish that bottom navigation is always best for this PWA.

Recommendation to test: a labelled Menu button for secondary destinations, while keeping Show my code and Browse rewards visible on Home. Compare this with a compact bottom bar through the tasks “earn at a shop”, “find an affordable reward” and “return home”.

An installed standalone PWA omits browser navigation UI; the browser version retains it. Both need phone testing. Use safe-area padding for fixed controls and account for the keyboard and changing viewport. See [web.dev PWA app design](https://web.dev/learn/pwa/app-design/). The design study’s bottom navigation is currently in document flow, not a tested fixed mobile bar.

The next revision replaces the bottom bar with a labelled hamburger disclosure in the header. Home retains Show my code and Browse rewards. Menu selection closes the disclosure; Escape closes it and returns focus to its trigger.

## Brand rollout — September 2026

The existing homepage, customer/trader app, admin and trader presentation now use the approved independent identity. Shared assets are in `assets/`; current rules are in [BRAND.md](BRAND.md). Footer links open the brand book. The legacy prototype redirects to the current app. Existing source flags and redemption rules remain intact. Public contact email is displayed as coming soon pending mailbox connection. Earlier line references above describe the pre-rollout source and may have moved.

### Local rollout verification

Checked the homepage at 390px and 1280px; all 11 app screens at 320px, 390px and 1280px; menu open/close and Escape behaviour; customer code focus; registration entry; demo reward selection; admin and presentation loading; and the legacy redirect. Browser checks used a mocked backend and did not validate live authentication or database operations. All app screens fit horizontally at the checked widths. Local-link, duplicate-ID, JavaScript syntax and old-brand reference scans passed. Changes remain local until committed and deployed.
