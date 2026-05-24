# Village Rewards - Database Schema Documentation

**Supabase Project:** `hwtwfhvaeczofqktychc.supabase.co`  
**Last Schema Audit:** May 2026  
**Status:** Production schema (current prototype model)

---

## ⚠️ Critical Note

**This schema documentation was reverse-engineered from application queries.** The actual schema definitions live only in Supabase. If the Supabase project is lost, this documentation is the only record of the data model.

**Action Required:** Export full schema from Supabase and version-control it in this repo.

---

## Schema Overview

The current schema supports the **prototype redemption model**. When the **tiered redemption system** is implemented (see `/docs/TIERED-SYSTEM.md`), this schema will be extended with additional tables (`tiers`, `rewards`, `redemptions`, `merchant_users`).

---

## Core Tables

### `customers`

Registered customers who earn points across village merchants.

```sql
CREATE TABLE customers (
  id VARCHAR(6) PRIMARY KEY,              -- 6-character alphanumeric ID
  name VARCHAR(200),
  email VARCHAR(200),
  points INTEGER DEFAULT 0,                -- Current point balance
  postcode VARCHAR(10),
  birth_year INTEGER,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_customers_points ON customers(points);
```

**Current Logic:**
- ID is 6-character alphanumeric (e.g., `A7F3K9`)
- Points = current accumulated balance
- No `total_points_earned` or `total_points_redeemed` tracking yet

**Missing Fields (needed for tiered system):**
- `total_points_earned` INTEGER
- `total_points_redeemed` INTEGER  
- `total_redemptions` INTEGER
- `village_id` UUID (for multi-village support)
- `last_transaction_date` TIMESTAMP

---

### `shops`

Participating merchant locations.

```sql
CREATE TABLE shops (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(200) NOT NULL,
  active BOOLEAN DEFAULT true,
  lat DECIMAL(9,6),                       -- Latitude for GPS check-in
  lng DECIMAL(9,6),                       -- Longitude for GPS check-in
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_shops_active ON shops(active);
```

**Current Implementation:**
- Single village (Mont Albert) hardcoded throughout app
- GPS coordinates used for 150m radius check-in validation
- No `category`, `contact_info`, or `logo_url` fields yet

**Missing Fields (needed for scale):**
- `village_id` UUID
- `category` VARCHAR(100) - e.g., 'cafe', 'restaurant', 'salon'
- `subscription_status` VARCHAR(20)
- `contact_email` VARCHAR(200)
- `logo_url` TEXT

---

### `transactions`

All point-earning and redemption events.

```sql
CREATE TABLE transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id VARCHAR(6) REFERENCES customers(id),
  shop_id UUID REFERENCES shops(id),
  shop_name VARCHAR(200),                 -- Denormalized for reporting
  type VARCHAR(20) NOT NULL,              -- 'purchase', 'checkin', 'redeem', 'bonus'
  amount DECIMAL(10,2),                   -- Transaction amount (for purchases)
  points INTEGER NOT NULL,                -- Points earned or spent
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_transactions_customer ON transactions(customer_id, created_at DESC);
CREATE INDEX idx_transactions_shop ON transactions(shop_id, created_at DESC);
CREATE INDEX idx_transactions_type ON transactions(type);
```

**Transaction Types:**

| Type | Description | Amount | Points |
|------|-------------|--------|--------|
| `purchase` | Customer purchase | Dollar amount | `amount * 1` |
| `checkin` | GPS-verified visit | NULL | 8 |
| `redeem` | Reward redemption | NULL | Negative (deducted) |
| `bonus` | Manual adjustment | NULL | Variable |

**Current Points Logic:**
- `purchase`: 1 point per $1 spent
- `checkin`: 8 points per GPS-verified visit (4-hour cooldown per shop)
- `redeem`: Points deducted when reward claimed
- `bonus`: Manual admin adjustment

---

## Database Views

These views aggregate transaction data for dashboards. **Definitions exist only in Supabase - not documented in SQL here.**

### `village_stats`

Top-level village-wide aggregates.

**Columns (inferred from queries):**
- Total customers
- Total points in circulation
- Total spend
- Total check-ins
- Active customers (purchased in last 30 days)

**Query Used:**
```sql
SELECT * FROM village_stats;
```

### `customer_stats`

Per-customer rollup statistics.

**Columns (inferred):**
- `customer_id`
- `unique_shops` - count of distinct shops visited
- `total_spend` - sum of all purchase amounts
- `total_transactions` - count of all transactions
- `total_points_earned` - cumulative points (all time)
- `last_transaction_date`

**Query Used:**
```sql
SELECT * FROM customer_stats WHERE customer_id = ?;
```

### `shop_stats`

Per-shop aggregates.

**Columns (inferred):**
- `shop_id`
- `shop_name`
- `total_transactions`
- `unique_customers`
- `total_points_issued`
- `total_revenue` (sum of purchase amounts)

**Query Used:**
```sql
SELECT * FROM shop_stats WHERE shop_id = ?;
```

### `cross_pollination`

Cross-shop customer journey mapping.

**Columns (inferred):**
- `from_shop_id`
- `to_shop_id`
- `from_shop_name`
- `to_shop_name`
- `journey_count` - number of customers who visited both

**Usage:** Powers the D3 force-directed network graph in admin dashboard.

**Query Used:**
```sql
SELECT * FROM cross_pollination;
```

### `checkins_detail`

Full check-in records with shop information.

**Columns (inferred):**
- `customer_id`
- `shop_id`
- `shop_name`
- `points` (always 8)
- `created_at`
- `lat`, `lng` (shop location)

**Query Used:**
```sql
SELECT * FROM checkins_detail WHERE created_at > ?;
```

### `shop_checkin_summary`

Per-shop check-in aggregates.

**Columns (inferred):**
- `shop_id`
- `shop_name`
- `total_checkins`
- `unique_customers`
- `total_points_issued`

---

## Row-Level Security (RLS) Policies

**⚠️ Critical Security Gap:** RLS policies are configured in Supabase but **not documented anywhere in this repo.**

### Required Policies (Inferred)

**customers table:**
- Customers can read their own record only
- Customers can update their own `points` (via trigger)
- Admin can read all customers
- Public can INSERT (registration)

**shops table:**
- Public can read active shops
- Admin can read/write all

**transactions table:**
- Customers can read their own transactions
- Customers can INSERT (when spending points)
- Shops can INSERT (when issuing points)
- Admin can read all

**Action Required:** Export RLS policies from Supabase and document here.

---

## Database Triggers

**⚠️ Another Critical Gap:** The application depends on Supabase triggers to update `customers.points`, but these triggers are **not documented or version-controlled.**

### Inferred Triggers

**update_customer_points (AFTER INSERT on transactions):**
```sql
-- Pseudo-code - actual trigger exists only in Supabase
CREATE TRIGGER update_customer_points
AFTER INSERT ON transactions
FOR EACH ROW
EXECUTE FUNCTION adjust_customer_balance();
```

**Behavior:**
- When `type = 'purchase'` or `type = 'checkin'` or `type = 'bonus'`: add `points` to `customers.points`
- When `type = 'redeem'`: subtract `points` from `customers.points`

**Action Required:** Export trigger definitions from Supabase and version-control them.

---

## Points System Rules

### Earning Points

**Purchase:**
- $1 spent = 1 point earned
- Rounding: `Math.round(amount)` in JavaScript
- Example: $15.49 → 15 points, $15.50 → 16 points

**Check-in:**
- GPS-verified visit within 150m of shop location
- 8 points per check-in
- Cooldown: 4 hours per shop (prevents spam)
- `DEV_MODE = false` enforces GPS check (was bypassed in early development)

**Bonus:**
- Manual admin adjustment
- Used for promotions, corrections, events

### Spending Points

**Valuation:**
- 100 points = $1 value
- Example: 50-point reward ≈ $0.50 value

**Redemption:**
- Current model: simplified (to be replaced by tiered system)
- Points deducted via negative transaction (`type = 'redeem'`)
- No validation of available rewards (prototype behavior)

---

## Schema for Tiered Redemption System

**See `/docs/TIERED-SYSTEM.md` for full specification.**

### New Tables Required

**tiers:**
```sql
CREATE TABLE tiers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tier_level INTEGER UNIQUE NOT NULL,     -- 10, 20, 30, 50, 100
  points_required INTEGER NOT NULL,
  suggested_value_min DECIMAL(10,2),
  suggested_value_max DECIMAL(10,2),
  display_order INTEGER,
  created_at TIMESTAMP DEFAULT NOW()
);
```

**rewards:**
```sql
CREATE TABLE rewards (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  merchant_id UUID REFERENCES shops(id) ON DELETE CASCADE,
  tier_id UUID REFERENCES tiers(id),
  reward_title VARCHAR(200) NOT NULL,
  reward_description TEXT,
  estimated_value DECIMAL(10,2),
  is_active BOOLEAN DEFAULT true,
  monthly_redemption_cap INTEGER,
  redemptions_this_month INTEGER DEFAULT 0,
  redemptions_total INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

**redemptions:**
```sql
CREATE TABLE redemptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id VARCHAR(6) REFERENCES customers(id),
  merchant_id UUID REFERENCES shops(id),
  reward_id UUID REFERENCES rewards(id),
  tier_id UUID REFERENCES tiers(id),
  points_spent INTEGER NOT NULL,
  redemption_code VARCHAR(100) UNIQUE,
  status VARCHAR(20) DEFAULT 'pending',   -- 'pending', 'validated', 'cancelled', 'expired'
  created_at TIMESTAMP DEFAULT NOW(),
  validated_at TIMESTAMP,
  expires_at TIMESTAMP,                   -- 10 minutes after creation
  notes TEXT
);
```

---

## Data Migration Path

When implementing tiered redemption system:

1. **Create new tables** (`tiers`, `rewards`, `redemptions`)
2. **Extend customers table** (add `total_points_earned`, `total_redemptions`, etc.)
3. **Extend shops table** (add `category`, `subscription_status`, etc.)
4. **Keep existing `transactions` table** for backward compatibility
5. **Add new transaction types** if needed (or use `redemptions` table exclusively)
6. **Backfill data** from existing transactions to populate new fields

---

## Schema Maintenance Checklist

- [ ] Export full schema from Supabase as SQL
- [ ] Document all RLS policies
- [ ] Document all triggers and functions
- [ ] Version-control schema in this repo
- [ ] Set up schema migration system (e.g., Supabase migrations)
- [ ] Add seed data for development
- [ ] Add test data fixtures
- [ ] Document foreign key relationships
- [ ] Create entity-relationship diagram (ERD)

---

## Known Data Issues

1. **No schema version control** - schema changes are made directly in Supabase UI
2. **No migration history** - no record of when tables/columns were added
3. **Views not documented** - definitions exist only in Supabase
4. **Triggers not documented** - critical business logic invisible in codebase
5. **No test data** - development relies on production Supabase instance
6. **No backups documented** - unclear if/how/when Supabase backups occur
7. **Generic git messages** - no commit history explaining schema changes

---

## Action Items

**Immediate:**
1. Export complete schema from Supabase (tables, views, triggers, RLS)
2. Document RLS policies in this file
3. Add schema.sql to repo root for disaster recovery

**Before Tiered System Build:**
1. Set up Supabase migrations workflow
2. Create development/staging Supabase instance
3. Add seed data and test fixtures
4. Document all business logic currently in triggers

**Long-term:**
1. Create ERD diagram
2. Set up automated schema documentation
3. Add foreign key constraints documentation
4. Document performance indexes
