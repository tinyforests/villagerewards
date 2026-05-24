# Village Rewards - Tiered Redemption System Specification

**Status:** In Development  
**Full Specification:** See `/mnt/user-data/outputs/village-rewards-dev-specification.md`  
**This Document:** High-level overview + migration strategy

---

## Overview

The **tiered redemption marketplace** replaces the current simplified points model with a strategic merchant reward donation system.

**Core Innovation:** Merchants aren't subsidizing each other's revenue - they're competing strategically for village-loyal customers through voluntary reward donations at specific point tiers.

---

## Core Mechanics

### Current Model (Prototype)

**How it works now:**
- Customer earns points ($1 = 1 point)
- Customer accumulates points across all merchants
- Customer redeems points for... *something* (system is vague)
- Points deducted from balance

**Problems:**
- No clear reward structure
- No merchant control over exposure
- No tier strategy
- Simple deduction model (not compelling)

### New Model (Tiered Marketplace)

**How it will work:**

1. **Fixed Tiers:** 10, 20, 30, 50, 100 points
2. **Merchant Donations:** Each merchant donates specific rewards at specific tiers
3. **Customer Choice:** Customer sees all available rewards at unlocked tier, chooses one
4. **Points Reset:** After redemption, points reset to 0 (customer starts accumulating again)
5. **Strategic Placement:** Merchants compete by placing rewards at tiers that match their business model

**Example:**

| Tier | Café Strategy | Restaurant Strategy | Salon Strategy |
|------|---------------|---------------------|----------------|
| 10 | Free coffee ($4) | - | - |
| 20 | Coffee + muffin ($8) | Free spring rolls ($12) | - |
| 30 | $10 off breakfast | - | 10% off haircut ($15) |
| 50 | - | 20% off meal ($20) | 15% off cut ($25) |
| 100 | - | Free meal ($40) | Free treatment ($40) |

**Strategy:**
- **High-frequency businesses** (cafés) dominate tier 10-30 for repeat visits
- **Destination businesses** (restaurants) focus tier 50-100 to capture high-value customers
- **New businesses** donate across all tiers for maximum visibility

---

## Key Principles

### 1. No Cross-Subsidy

Each merchant only pays when **their own reward** is redeemed.

**Wrong model (discount pooling):**
```
Café puts $100 into shared pool
→ Customer redeems $20 restaurant discount
→ Café just subsidized the restaurant's revenue
❌ Unfair
```

**Right model (tiered marketplace):**
```
Café donates "free coffee" at tier 10
Restaurant donates "free meal" at tier 100
→ Customer redeems café's coffee
→ Café pays $4 cost, restaurant pays $0
✓ Fair
```

### 2. Points Reset After Redemption

**Current model:** Points deducted (customer at 50 → redeems 20 → now at 30)

**New model:** Points reset to 0 (customer at 50 → redeems tier 50 → back to 0)

**Why:** Creates a clear cycle - earn, unlock, redeem, start again. Tier 100 becomes a major milestone, not just "save up 100 and spend 20 at a time."

### 3. Merchants Control Exposure

**Monthly Redemption Caps:**
```
Café: "Free coffee at tier 10, max 30 per month"
→ After 30 redemptions, reward disappears until next month
→ Café's max exposure: 30 × $4 = $120/month
```

**Pause/Unpause:**
```
Restaurant running low on stock
→ Pauses "free meal" reward temporarily
→ No new redemptions, existing redemptions honoured
```

### 4. Customer Journey

**Without tiers:**
"I have 47 points... I guess I can redeem something?"

**With tiers:**
"I'm at 47 points, 3 more unlocks tier 50. I want that Thai restaurant free meal. Let me buy something to hit 50."

**Result:** Intentional spending to reach tier milestones, not passive accumulation.

---

## Database Schema Changes

See `docs/SCHEMA.md` for full SQL.

### New Tables Required

**tiers** (static configuration):
```sql
CREATE TABLE tiers (
  id UUID PRIMARY KEY,
  tier_level INTEGER UNIQUE NOT NULL,     -- 10, 20, 30, 50, 100
  points_required INTEGER NOT NULL,
  suggested_value_min DECIMAL(10,2),      -- Guide for merchants
  suggested_value_max DECIMAL(10,2),
  display_order INTEGER
);
```

**rewards** (merchant-donated rewards):
```sql
CREATE TABLE rewards (
  id UUID PRIMARY KEY,
  merchant_id UUID REFERENCES shops(id),
  tier_id UUID REFERENCES tiers(id),
  reward_title VARCHAR(200) NOT NULL,     -- "Free coffee"
  reward_description TEXT,                -- "Any regular coffee"
  estimated_value DECIMAL(10,2),          -- $4.00
  is_active BOOLEAN DEFAULT true,
  monthly_redemption_cap INTEGER,         -- 30
  redemptions_this_month INTEGER DEFAULT 0,
  redemptions_total INTEGER DEFAULT 0
);
```

**redemptions** (redemption events):
```sql
CREATE TABLE redemptions (
  id UUID PRIMARY KEY,
  customer_id VARCHAR(6) REFERENCES customers(id),
  merchant_id UUID REFERENCES shops(id),  -- Where redeemed
  reward_id UUID REFERENCES rewards(id),  -- Specific reward
  tier_id UUID REFERENCES tiers(id),      -- Which tier
  points_spent INTEGER NOT NULL,          -- Tier level (10, 20, etc.)
  redemption_code VARCHAR(100) UNIQUE,    -- QR validation code
  status VARCHAR(20) DEFAULT 'pending',   -- pending/validated/cancelled/expired
  created_at TIMESTAMP DEFAULT NOW(),
  validated_at TIMESTAMP,
  expires_at TIMESTAMP                    -- 10 minutes after creation
);
```

### Table Extensions Needed

**customers table:**
```sql
ALTER TABLE customers ADD COLUMN total_points_earned INTEGER DEFAULT 0;
ALTER TABLE customers ADD COLUMN total_points_redeemed INTEGER DEFAULT 0;
ALTER TABLE customers ADD COLUMN total_redemptions INTEGER DEFAULT 0;
ALTER TABLE customers ADD COLUMN village_id UUID REFERENCES villages(id);
```

**shops table:**
```sql
ALTER TABLE shops ADD COLUMN village_id UUID REFERENCES villages(id);
ALTER TABLE shops ADD COLUMN category VARCHAR(100);
ALTER TABLE shops ADD COLUMN subscription_status VARCHAR(20);
ALTER TABLE shops ADD COLUMN monthly_fee DECIMAL(10,2) DEFAULT 30.00;
```

---

## User Flows

### Flow 1: Merchant Creates Reward

**Merchant Dashboard → Rewards → Create New Reward**

1. Select tier: [10] [20] [30] [50] [100]
2. Reward title: "Free coffee"
3. Reward description: "Any regular coffee, excludes specialty drinks"
4. Estimated value: $4.00
5. Monthly cap: 30 (optional)
6. [Save Reward]

**Result:**
- Reward appears in tier 10 reward pool
- Customers with 10+ points can see it
- Merchant dashboard shows "0/30 redeemed this month"

### Flow 2: Customer Earns Points & Unlocks Tier

**Customer App → Home Screen**

```
Your Points: 8

Progress to Next Tier:
✓ Tier 10 (Unlocked!) - 8 available rewards
  Tier 20 - Need 12 more points
  Tier 30 - Need 22 more points
  Tier 50 - Need 42 more points
  Tier 100 - Need 92 more points

[Browse Tier 10 Rewards]
```

### Flow 3: Customer Browses Tier Rewards

**Customer App → Tier 10 → Reward List**

```
Tier 10 Rewards (Choose 1)

┌─────────────────────────────────────┐
│ Blue Stone Café                     │
│ Free coffee                         │
│ Any regular coffee                  │
│ Worth: ~$4                          │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ Village Bakery                      │
│ 2 free croissants                   │
│ Any flavour, fresh baked            │
│ Worth: ~$8                          │
└─────────────────────────────────────┘

[... 6 more rewards]
```

### Flow 4: Customer Redeems Reward

**Customer selects "Free coffee" → Confirmation Screen**

```
Redeem This Reward?

Blue Stone Café
Free coffee

This will reset your points to 0.
You'll start earning again immediately.

[Cancel] [Redeem Now]
```

**Customer taps "Redeem Now" → Redemption QR Generated**

```
┌─────────────────┐
│                 │
│   [QR CODE]     │
│                 │
└─────────────────┘

Blue Stone Café
Free coffee

Show this code to the merchant
Expires in 9:45

[Cancel Redemption]
```

### Flow 5: Merchant Validates Redemption

**Merchant scans customer's redemption QR → Validation Screen**

```
Redemption Request

Customer: Sarah
Reward: Free coffee
Tier: 10 points
Points being spent: 10

[Cancel] [Validate Redemption]
```

**Merchant taps "Validate Redemption"**

**System:**
1. Checks redemption status (must be 'pending')
2. Checks expiry (must be <10 minutes old)
3. Checks merchant match (must be Blue Stone Café)
4. Updates redemption status → 'validated'
5. Resets customer points to 0
6. Increments reward redemption counter
7. Shows success confirmation

---

## Migration Strategy

### Phase 1: Schema Extension (Week 1)

- [ ] Create `tiers` table with 5 standard tiers
- [ ] Create `rewards` table
- [ ] Create `redemptions` table
- [ ] Extend `customers` table (new columns)
- [ ] Extend `shops` table (new columns)
- [ ] Backfill existing data where possible

### Phase 2: Merchant Dashboard (Week 2-3)

- [ ] Reward creation UI (tier selection, title, description, cap)
- [ ] Reward management UI (list, edit, pause, delete)
- [ ] Reward analytics (redemptions this month, most popular tier)

### Phase 3: Customer App (Week 4-5)

- [ ] Tier progress display (home screen)
- [ ] Tier browser (show available rewards per tier)
- [ ] Reward detail modal
- [ ] Redemption QR generation (with expiry countdown)
- [ ] Redemption confirmation flow

### Phase 4: Validation Flow (Week 6)

- [ ] Merchant redemption scanner
- [ ] Redemption validation screen
- [ ] QR expiry enforcement (10 minutes)
- [ ] Points reset logic (customer.points = 0 after validation)

### Phase 5: Analytics & Reporting (Week 7-8)

- [ ] Merchant tier performance dashboard
- [ ] Council village-wide tier redemption stats
- [ ] Cross-tier customer journey analysis
- [ ] Monthly redemption cap auto-reset (cron job)

### Phase 6: Testing & Launch (Week 9-10)

- [ ] End-to-end flow testing
- [ ] Concurrent redemption testing
- [ ] Load testing (100+ concurrent users)
- [ ] Mont Albert trader training
- [ ] Soft launch with 5 traders
- [ ] Full launch with 15-20 traders

---

## Business Logic Changes

### Points Reset After Redemption

**Old logic:**
```javascript
// Deduct points
customer.points -= tier.points_required;
```

**New logic:**
```javascript
// Reset to zero
customer.points = 0;
customer.total_points_redeemed += tier.points_required;
customer.total_redemptions += 1;
```

### Tier Unlocking

**Check which tiers customer can access:**
```javascript
const unlockedTiers = [10, 20, 30, 50, 100].filter(
  tier => customer.current_points >= tier
);
```

**Example:**
- Customer at 47 points → unlocked tiers: [10, 20, 30]
- Customer can redeem from tier 10, 20, or 30
- Customer can save for tier 50 (needs 3 more points)

### Redemption Validation

**Check redemption is valid:**
```javascript
if (redemption.status !== 'pending') {
  return "This redemption has already been used";
}
if (redemption.expires_at < NOW()) {
  return "This redemption code has expired";
}
if (redemption.merchant_id !== current_merchant.id) {
  return "This reward is for a different merchant";
}
// All checks pass → allow validation
```

### Monthly Cap Enforcement

**Check if reward is available:**
```sql
SELECT 
  CASE 
    WHEN monthly_redemption_cap IS NULL THEN true
    WHEN monthly_redemption_cap = 0 THEN true
    WHEN redemptions_this_month < monthly_redemption_cap THEN true
    ELSE false
  END as is_available
FROM rewards
WHERE id = ?;
```

**Auto-reset on 1st of month (cron job):**
```sql
UPDATE rewards 
SET redemptions_this_month = 0
WHERE redemptions_this_month > 0;
```

---

## Open Questions

### Product

- Should customers be able to skip tiers? (e.g., save 50 points, redeem tier 50, ignore tier 10/20/30)
  - **Answer:** Yes - creates intentional tier targeting

- Should tier 100 be special? (e.g., badge, celebration animation)
  - **Answer:** Yes - tier 100 is a major milestone

- Should there be a tier 200 or tier 500?
  - **Answer:** Start with 10/20/30/50/100, evaluate after 3 months

### Technical

- Should redemption QR codes be single-use or multi-use?
  - **Answer:** Single-use (status='validated' prevents reuse)

- How do we handle merchant deleting a reward with pending redemptions?
  - **Answer:** Block deletion if pending redemptions exist, allow pause instead

- Should customers see which rewards are close to hitting monthly cap?
  - **Answer:** Not in MVP, maybe Phase 2 ("Only 3 left this month!")

### Business

- Should merchants be able to donate multiple rewards to the same tier?
  - **Answer:** Yes - café can offer both "free coffee" and "2 pastries" at tier 10

- Should there be a minimum reward value per tier?
  - **Answer:** Suggested ranges only, not enforced (merchant autonomy)

- Should new merchants get a discount for donating across all tiers?
  - **Answer:** Pricing question for Commercial Mind, not technical

---

## Success Metrics

**Before tiered system:**
- Customer doesn't know what rewards exist until they ask
- Merchant can't control volume
- No strategic tier placement

**After tiered system:**
- Customer sees tier progression as a game (unlock tiers, choose rewards)
- Merchant controls exposure (caps, pause, tier strategy)
- Village loyalty increases (customer saving for tier 100 stays in village)

**Measure:**
- Average points before redemption (should increase - customers saving for higher tiers)
- Redemptions per tier (should distribute - not all tier 10)
- Merchant tier coverage (should increase - merchants competing across tiers)
- Customer return rate after redemption (should increase - points reset, cycle continues)

---

## Full Development Specification

**This document is a high-level overview.**

For complete technical specification including:
- Full SQL schema
- All API endpoints
- QR code formats
- Error handling
- Edge cases
- Testing checklist
- Security requirements

See: `/mnt/user-data/outputs/village-rewards-dev-specification.md`
