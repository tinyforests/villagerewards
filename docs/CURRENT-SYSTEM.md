# Village Rewards - Current System Documentation

**Status:** Prototype MVP (Functional, Auth Disabled)  
**Version:** Pre-tiered system  
**Last Updated:** May 2026

---

## Overview

This document describes **how the current Village Rewards prototype works**, not how it will work after the tiered redemption system is implemented.

For the future system, see `docs/TIERED-SYSTEM.md`.

---

## Current Points Model

### Earning Points

**Purchase:**
- $1 spent = 1 point earned
- Rounding: `Math.round(amount)` in JavaScript
- Example: $15.49 → 15 points, $15.50 → 16 points

**Check-in:**
- GPS-verified visit within 150m of shop location
- 8 points per check-in
- Cooldown: 4 hours per shop (prevents spam)
- GPS enforcement: Active (`DEV_MODE = false`)

**Bonus:**
- Manual admin adjustment
- Used for promotions, corrections, events

### Spending Points

**Valuation:**
- 100 points = $1 value
- Example: 50 points ≈ $0.50 value

**Redemption (Simplified):**
- Customer "redeems points" (no structured tiers yet)
- Points deducted via negative transaction (`type = 'redeem'`)
- No validation of what reward was actually given
- Prototype behavior only

---

## User Flows (Current)

### Customer Registration

**URL:** villagerewards.com.au/app.html

**Flow:**
1. Customer lands on app.html
2. Clicks "Join Village Rewards"
3. Fills form:
   - Name
   - Email
   - Postcode (optional)
   - Birth year (optional)
4. System generates 6-character ID (e.g., `A7F3K9`)
5. Customer record inserted into Supabase
6. Customer redirected to points dashboard

**Data:**
```sql
INSERT INTO customers (id, name, email, postcode, birth_year)
VALUES (random_6_char(), ?, ?, ?, ?);
```

### Customer Views Points

**Dashboard shows:**
- Current point balance (large number)
- Recent transactions (list)
- Participating shops (map or list)

**No tier visualization** - this is added in tiered system.

### Trader Issues Points (Purchase)

**Currently DISABLED** (hardcoded PIN removed)

**How it worked:**
1. Trader logs in with PIN (`MONT` - now removed)
2. Selects their shop from dropdown
3. Customer shows QR code
4. Trader scans QR with phone camera
5. Trader enters transaction amount: $15.50
6. System calculates points: `Math.round(15.50) = 16`
7. Transaction inserted:
   ```sql
   INSERT INTO transactions (
     customer_id, shop_id, shop_name,
     type, amount, points
   ) VALUES (?, ?, ?, 'purchase', 15.50, 16);
   ```
8. Database trigger updates customer points:
   ```sql
   UPDATE customers SET points = points + 16 WHERE id = ?;
   ```

### Trader Issues Points (Check-in)

**Currently DISABLED** (hardcoded PIN removed)

**How it worked:**
1. Customer requests check-in at shop
2. Trader initiates check-in in app
3. JavaScript checks GPS distance:
   ```javascript
   const distance = haversineDistance(
     customer_lat, customer_lng,
     shop_lat, shop_lng
   );
   if (distance > 150 && DEV_MODE === false) {
     return "Too far from shop";
   }
   ```
4. Check 4-hour cooldown:
   ```sql
   SELECT * FROM transactions
   WHERE customer_id = ?
     AND shop_id = ?
     AND type = 'checkin'
     AND created_at > NOW() - INTERVAL '4 hours';
   ```
5. If valid, insert check-in transaction:
   ```sql
   INSERT INTO transactions (
     customer_id, shop_id, shop_name,
     type, points
   ) VALUES (?, ?, ?, 'checkin', 8);
   ```

### Customer Redeems Points (Simplified)

**Prototype behavior only - no structured tiers:**

1. Customer says "I want to use my points"
2. Trader manually applies discount
3. Trader logs redemption:
   ```sql
   INSERT INTO transactions (
     customer_id, shop_id, shop_name,
     type, points
   ) VALUES (?, ?, ?, 'redeem', -50);  -- Negative points
   ```
4. Customer balance decreases:
   ```sql
   UPDATE customers SET points = points - 50 WHERE id = ?;
   ```

**Problem with this model:**
- No record of what reward was given
- No validation that merchant actually gave anything
- No merchant control over volume
- No customer visibility into available rewards

**This is replaced entirely by tiered redemption system.**

---

## Admin Dashboard

**URL:** villagerewards.com.au/village-rewards-admin.html

**Currently DISABLED** (hardcoded password removed)

### Features (When Active)

**Realtime Activity Feed:**
- Live stream of all transactions
- Subscribes to `transactions` table via Supabase Realtime
- Shows: customer name, shop name, type, amount, points, timestamp
- Updates in real-time as transactions occur

**D3 Network Graph:**
- Force-directed graph showing cross-shop customer journeys
- Nodes: Shops
- Edges: Customer journeys between shops
- Edge thickness: Number of shared customers
- Data source: `cross_pollination` view

**Cross-Pollination Matrix:**
- Heatmap showing customer overlap between shops
- Rows: Shop A
- Columns: Shop B
- Cell value: Count of customers who visited both

**Heatmap (Activity by Hour/Day):**
- 7×24 grid (7 days × 24 hours)
- Cell color intensity: Transaction count
- Shows peak activity times

**Badge System:**
- Early Adopter (first 100 customers)
- Cross-Shopper (visited 3+ shops)
- High Roller (1000+ points earned)
- Frequent Visitor (20+ transactions)
- Check-in Champion (10+ check-ins)
- Village Loyalist (active for 30+ days)

**Customer Table:**
- Sortable list of all customers
- Columns: Name, email, points, shops visited, transactions, joined date
- Click to view customer detail

**Transaction Table:**
- Sortable list of all transactions
- Columns: Customer, shop, type, amount, points, date
- Filter by type (purchase/checkin/redeem/bonus)

---

## Database Views (Current)

See `docs/SCHEMA.md` for full schema documentation.

### `village_stats`

Top-level aggregate for entire village:
- Total customers
- Total points in circulation
- Total spend (sum of purchase amounts)
- Total check-ins
- Active customers (purchased in last 30 days)

**Usage:** Admin dashboard header stats

### `customer_stats`

Per-customer rollup:
- `customer_id`
- `unique_shops` (count of distinct shops visited)
- `total_spend` (sum of purchase amounts)
- `total_transactions` (count)
- `total_points_earned` (cumulative)

**Usage:** Customer detail view in admin

### `shop_stats`

Per-shop aggregates:
- `shop_id`, `shop_name`
- `total_transactions`
- `unique_customers`
- `total_points_issued`
- `total_revenue` (sum of purchase amounts)

**Usage:** Shop performance in admin dashboard

### `cross_pollination`

Cross-shop customer journey mapping:
- `from_shop_id`, `to_shop_id`
- `from_shop_name`, `to_shop_name`
- `journey_count` (customers who visited both)

**Usage:** D3 network graph + cross-pollination matrix

### `checkins_detail`

Full check-in records:
- `customer_id`, `shop_id`, `shop_name`
- `points` (always 8)
- `created_at`
- `lat`, `lng` (shop location)

**Usage:** Check-in leaderboard, shop check-in summary

---

## QR Code System (Current)

### Customer QR Code (Earning Points)

**Generated in:** app.html customer dashboard

**Contains:**
```json
{
  "customer_id": "A7F3K9",
  "type": "earning"
}
```

**Format:** Plain text JSON encoded as QR via qrcodejs library

**Usage:**
1. Customer shows QR to trader
2. Trader scans with phone camera (opens app.html scanner page)
3. JavaScript parses QR data
4. Trader enters transaction amount
5. System adds points

**Refresh:** QR regenerates every page load (no expiry)

### Redemption QR (Prototype - Not Implemented)

**Not yet implemented in current system.**

In tiered system, will generate separate redemption QR with:
```json
{
  "type": "redemption",
  "redemption_code": "VR-A7F3K9",
  "customer_id": "A7F3K9",
  "reward_id": "uuid",
  "expires_at": "2026-05-23T10:40:00Z"
}
```

---

## Known Limitations (Current System)

### Authentication

- ❌ No admin authentication (disabled)
- ❌ No trader authentication (disabled)
- ❌ Customer registration open (no password)

### Redemption Model

- ❌ No structured reward tiers
- ❌ No merchant reward donations
- ❌ No customer visibility into available rewards
- ❌ No merchant control over redemption volume
- ❌ No validation that reward was actually given

### Data Model

- ❌ No tier structure
- ❌ No reward catalog
- ❌ No redemption records (just negative transactions)
- ❌ No merchant categories
- ❌ No village multi-tenancy

### Business Logic

- ❌ Point calculations happen in client-side JS (not validated server-side)
- ❌ No atomic redemption validation (concurrent redemptions could double-spend)
- ❌ No rate limiting
- ❌ No fraud detection

### UX

- ❌ No tier progress visualization
- ❌ No reward browsing
- ❌ No merchant reward management dashboard
- ❌ No redemption QR with expiry
- ❌ Android PWA install broken (no manifest)

---

## What Works Well (Keep in Tiered System)

### Point Accumulation
✅ $1 = 1 point is clear and fair  
✅ GPS check-in validation works (when enabled)  
✅ 4-hour cooldown prevents spam  
✅ Database trigger for point updates is elegant  

### Admin Dashboard
✅ D3 network graph is impressive and useful  
✅ Realtime feed creates sense of activity  
✅ Cross-pollination matrix shows village connectivity  
✅ Badge system is engaging  

### Design
✅ G&S brand identity is consistent  
✅ Abril Fatface + IBM Plex Sans typography works  
✅ Beige/green palette feels warm and local  

### Architecture
✅ Zero-build deployment is fast for prototyping  
✅ Supabase backend is flexible  
✅ Service worker provides offline support  

---

## Migration Path to Tiered System

See `docs/TIERED-SYSTEM.md` for full migration plan.

**Key changes:**

1. **Add tier structure** (10/20/30/50/100 points)
2. **Add reward catalog** (merchant-donated rewards per tier)
3. **Add redemption records** (track which reward was given)
4. **Points reset after redemption** (not just deducted)
5. **Merchant reward management UI**
6. **Customer tier browser UI**
7. **Redemption QR with validation flow**

**What stays:**
- Point earning ($1 = 1 point, check-ins = 8 points)
- Database triggers for point updates
- Admin dashboard (extended with tier analytics)
- GPS check-in validation
- D3 network graph visualization

---

## Testing the Current System

**⚠️ Note:** Admin and trader logins are currently disabled.

### Test Customer Registration

1. Go to villagerewards.com.au/app.html
2. Click "Join Village Rewards"
3. Fill in name, email (use test data)
4. Check Supabase: customer record should exist

### Test Customer Dashboard

1. Use same URL as registration
2. Should see points balance (0 for new customer)
3. Should see QR code
4. Should see empty transaction history

### Test Trader Flow (When Re-enabled)

1. Re-enable trader PIN (for testing only)
2. Log in as trader
3. Select shop
4. Scan test customer QR
5. Enter transaction amount
6. Verify points added in customer dashboard

### Test Admin Dashboard (When Re-enabled)

1. Re-enable admin password (for testing only)
2. Log in to admin dashboard
3. Verify realtime feed shows transactions
4. Verify D3 graph renders
5. Verify customer/transaction tables populate

---

## Troubleshooting

### Customer can't see points

**Check:**
- Is customer_id valid in URL?
- Does customer record exist in Supabase?
- Are there transactions for this customer?

**Debug:**
```sql
SELECT * FROM customers WHERE id = 'A7F3K9';
SELECT * FROM transactions WHERE customer_id = 'A7F3K9';
```

### Trader can't issue points

**Current:** Trader login is disabled (hardcoded PIN removed)

**To re-enable (testing only):**
1. Add back `var TRADER_PIN = 'test123';` in app.html
2. Update login function to check PIN
3. ⚠️ Do not commit this - use Supabase Auth instead

### Check-in fails "too far from shop"

**Check:**
- Is `DEV_MODE = false`? (should be)
- Is GPS location accurate on customer device?
- Is shop lat/lng correct in database?
- Is customer within 150m radius?

**Debug:**
```javascript
// Add to check-in function
console.log('Customer:', customer_lat, customer_lng);
console.log('Shop:', shop_lat, shop_lng);
console.log('Distance:', distance, 'meters');
```

### Points not updating after transaction

**Check:**
- Does database trigger exist?
- Is trigger enabled?
- Are there errors in Supabase logs?

**Verify trigger:**
```sql
-- Check if trigger fires
SELECT * FROM customers WHERE id = 'A7F3K9';
-- Insert test transaction
INSERT INTO transactions (...) VALUES (...);
-- Check if points updated
SELECT * FROM customers WHERE id = 'A7F3K9';
```

---

## Contact & Support

**Built by:** Gardener & Son  
**Primary contact:** Tyson (co-founder)  
**Repository:** github.com/tinyforests/villagerewards

**For current system bugs:** Check `docs/ARCHITECTURE.md` and `docs/SECURITY.md`  
**For future system questions:** Check `docs/TIERED-SYSTEM.md`  
**For database questions:** Check `docs/SCHEMA.md`
