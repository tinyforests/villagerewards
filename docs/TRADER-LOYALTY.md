# Optional trader loyalty programs

Product direction agreed 1 October 2026. Planned integration; not enabled by this UI change.

Village points are shared across participating shops. Individual traders can also opt into their own loyalty offer, such as “buy 10 coffees, get one free”. Customers should see the two balances clearly: village points and named shop cards.

## Intended experience

- Traders choose whether to offer a shop card and define the qualifying item, stamp goal, reward and conditions.
- A coffee card counts eligible paid coffees at that trader. A visit alone does not earn a coffee stamp.
- Show progress plainly: “7 of 10 coffees · 3 to your free coffee”.
- Keep the customer's village points when redeeming a shop-card reward. Consume only the required stamps; retain extra eligible stamps.
- Staff confirm eligible purchases and reward collection. A customer QR identifies the customer; scanning alone does not issue stamps or redeem a reward.
- Keep staff-assisted check-in under More options → Record a visit. Main business actions remain awarding points and redeeming points/rewards.

## Existing code and required work

`app.html` contains shop-card display, redemption and validation branches behind `REWARDS_V2 = false`. `docs/schema-v2.sql` proposes stamp rewards and supporting RPCs. These files are a starting point, not evidence that the live database is configured.

The proposed SQL counts qualifying purchase transactions, optionally by minimum spend. It does not establish how many coffees were purchased. Before enabling an item-based offer, add explicit eligible-item quantities or a staff-confirmed stamp ledger with server-side validation. Decide how refunds, corrections and multiple coffees in one purchase affect progress. Review the existing reset-marker approach so redemption does not discard surplus stamps.

Add authenticated trader program management, shop-scoped permissions, an auditable stamp ledger and atomic, idempotent issuance/redemption. Verify customer isolation, duplicate scans, concurrent redemption, reward conditions, and unchanged village balances. Do not turn on the V2 flag until the backend and end-to-end flows are verified.
