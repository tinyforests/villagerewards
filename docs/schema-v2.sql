-- ============================================================================
-- Village Rewards V2 — Tiered Reward Marketplace
-- Schema patch. Run manually in the Supabase SQL Editor AFTER review.
-- Nothing here is executed automatically. Idempotent where practical.
-- ============================================================================
--
-- Depends on the existing V1 schema:
--   customers(id text pk, name, email, points int, postcode, birth_year, created_at)
--   shops(id uuid pk, name, active, lat, lng, created_at)
--   transactions(id uuid pk, customer_id, shop_id, shop_name, type, amount,
--                points int, created_at)
--   + an AFTER INSERT trigger on transactions that maintains customers.points
--     as  customers.points := customers.points + NEW.points
--     (purchase/checkin/bonus carry positive points, redeem carries negative).
--
-- >>> BEFORE RUNNING: confirm that trigger actually does `+= NEW.points`.
--     The points-reset logic below inserts a redeem row of -(full balance)
--     and relies on the trigger to zero the balance. If the trigger instead
--     *subtracts* NEW.points for redeem rows, flip the sign in
--     validate_redemption() or the balance will double.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. shops — per-shop trader login + marketplace metadata
--    login_code replaces the single shared pilot PIN. Trader logs in with
--    shop name + code; we resolve the shop by matching login_code.
-- ----------------------------------------------------------------------------
ALTER TABLE shops ADD COLUMN IF NOT EXISTS login_code          varchar(20);
ALTER TABLE shops ADD COLUMN IF NOT EXISTS category            varchar(100);
ALTER TABLE shops ADD COLUMN IF NOT EXISTS subscription_status varchar(20) DEFAULT 'active';
ALTER TABLE shops ADD COLUMN IF NOT EXISTS monthly_fee         numeric(10,2) DEFAULT 30.00;

-- login_code must be unique so a code resolves to exactly one shop.
CREATE UNIQUE INDEX IF NOT EXISTS idx_shops_login_code
  ON shops (login_code) WHERE login_code IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 2. customers — lifetime redemption stats.
--    NOTE: the live balance stays in customers.points, owned by the trigger.
--    These columns are analytics only, maintained by validate_redemption().
-- ----------------------------------------------------------------------------
ALTER TABLE customers ADD COLUMN IF NOT EXISTS total_points_redeemed integer DEFAULT 0;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS total_redemptions     integer DEFAULT 0;

-- ----------------------------------------------------------------------------
-- 3. tiers — static config. Fixed at 10/20/30/50/100.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tiers (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tier_level          integer UNIQUE NOT NULL,       -- 10, 20, 30, 50, 100
  points_required     integer NOT NULL,              -- == tier_level
  suggested_value_min numeric(10,2),
  suggested_value_max numeric(10,2),
  display_order       integer,
  created_at          timestamptz DEFAULT now()
);

INSERT INTO tiers (tier_level, points_required, suggested_value_min, suggested_value_max, display_order)
VALUES
  (10,  10,  3.00,   8.00,  10),
  (20,  20,  8.00,   15.00, 20),
  (30,  30,  10.00,  20.00, 30),
  (50,  50,  20.00,  35.00, 50),
  (100, 100, 35.00,  60.00, 100)
ON CONFLICT (tier_level) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 4. rewards — merchant-donated rewards at a tier.
--    Cap is enforced by LIVE COUNT of validated redemptions this month
--    (see redeem_reward), so there is no monthly counter to reset.
--    redemptions_total is a lifetime convenience stat only.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rewards (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id            uuid NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  tier_id                uuid NOT NULL REFERENCES tiers(id),
  reward_title           varchar(200) NOT NULL,
  reward_description     text,
  estimated_value        numeric(10,2),
  is_active              boolean DEFAULT true,        -- pause == false
  monthly_redemption_cap integer,                     -- NULL / 0 == unlimited
  redemptions_total      integer DEFAULT 0,
  created_at             timestamptz DEFAULT now(),
  updated_at             timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rewards_tier     ON rewards (tier_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_rewards_merchant ON rewards (merchant_id);

-- ----------------------------------------------------------------------------
-- 5. redemptions — one row per redemption attempt.
--    points_spent      = tier level that gated the redemption (10/20/…)
--    points_at_redemption = actual balance zeroed on validation (for the
--                           "avg points before redemption" success metric)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS redemptions (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id          varchar(6) REFERENCES customers(id),
  merchant_id          uuid REFERENCES shops(id),
  reward_id            uuid REFERENCES rewards(id),
  tier_id              uuid REFERENCES tiers(id),
  points_spent         integer NOT NULL,              -- tier gate
  points_at_redemption integer,                        -- balance zeroed on validate
  redemption_code      varchar(100) UNIQUE NOT NULL,
  status               varchar(20) DEFAULT 'pending',  -- pending/validated/cancelled/expired
  created_at           timestamptz DEFAULT now(),
  validated_at         timestamptz,
  expires_at           timestamptz NOT NULL,           -- created_at + 10 min
  notes                text
);

CREATE INDEX IF NOT EXISTS idx_redemptions_code     ON redemptions (redemption_code);
CREATE INDEX IF NOT EXISTS idx_redemptions_customer ON redemptions (customer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_redemptions_cap      ON redemptions (reward_id, status, validated_at);

-- ============================================================================
-- 6. RPCs — the only trusted surface. SECURITY DEFINER so they run with the
--    owner's rights and bypass RLS; tables below stay locked to anon.
-- ============================================================================

-- redeem_reward: customer initiates. Validates balance + monthly cap, then
-- creates a pending redemption with a 10-minute expiry. Does NOT touch points
-- (points are only reset on merchant validation).
CREATE OR REPLACE FUNCTION redeem_reward(p_customer_id text, p_reward_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reward  rewards%ROWTYPE;
  v_tier    tiers%ROWTYPE;
  v_balance integer;
  v_used    integer;
  v_code    text;
  v_expires timestamptz;
BEGIN
  SELECT * INTO v_reward FROM rewards WHERE id = p_reward_id;
  IF NOT FOUND         THEN RAISE EXCEPTION 'Reward not found'; END IF;
  IF NOT v_reward.is_active THEN RAISE EXCEPTION 'Reward is not available'; END IF;

  SELECT * INTO v_tier FROM tiers WHERE id = v_reward.tier_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Reward tier missing'; END IF;

  SELECT points INTO v_balance FROM customers WHERE id = p_customer_id;
  IF v_balance IS NULL THEN RAISE EXCEPTION 'Customer not found'; END IF;
  IF v_balance < v_tier.points_required THEN
    RAISE EXCEPTION 'Not enough points for this tier';
  END IF;

  -- Live-count the monthly cap: validated redemptions in the current month.
  IF v_reward.monthly_redemption_cap IS NOT NULL AND v_reward.monthly_redemption_cap > 0 THEN
    SELECT count(*) INTO v_used
      FROM redemptions
     WHERE reward_id = v_reward.id
       AND status = 'validated'
       AND validated_at >= date_trunc('month', now());
    IF v_used >= v_reward.monthly_redemption_cap THEN
      RAISE EXCEPTION 'Reward has reached its monthly limit';
    END IF;
  END IF;

  v_code    := upper(substring(replace(gen_random_uuid()::text, '-', '') for 12));
  v_expires := now() + interval '10 minutes';

  INSERT INTO redemptions (customer_id, merchant_id, reward_id, tier_id,
                           points_spent, redemption_code, status, expires_at)
  VALUES (p_customer_id, v_reward.merchant_id, v_reward.id, v_reward.tier_id,
          v_tier.points_required, v_code, 'pending', v_expires);

  RETURN json_build_object(
    'redemption_code', v_code,
    'expires_at',      v_expires,
    'reward_title',    v_reward.reward_title,
    'points_required', v_tier.points_required
  );
END;
$$;

-- validate_redemption: merchant confirms. Atomic. Trader proves identity by
-- passing their shop login_code (not a client-supplied shop_id), so a merchant
-- can only validate redemptions for a shop whose PIN they know.
CREATE OR REPLACE FUNCTION validate_redemption(p_redemption_code text, p_login_code text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shop_id       uuid;
  v_shop_name     text;
  v_red           redemptions%ROWTYPE;
  v_balance       integer;
  v_reward_title  text;
  v_customer_name text;
BEGIN
  -- Resolve + authenticate the trader by their shop login code.
  SELECT id, name INTO v_shop_id, v_shop_name
    FROM shops WHERE login_code = upper(p_login_code) AND active;
  IF v_shop_id IS NULL THEN RAISE EXCEPTION 'Invalid trader login'; END IF;

  SELECT * INTO v_red FROM redemptions
   WHERE redemption_code = upper(p_redemption_code)
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Redemption code not found'; END IF;

  -- Guard rails, in order.
  IF v_red.status <> 'pending' THEN
    RAISE EXCEPTION 'Redemption already %', v_red.status;
  END IF;
  IF v_red.expires_at < now() THEN
    UPDATE redemptions SET status = 'expired' WHERE id = v_red.id;
    RAISE EXCEPTION 'Redemption code has expired';
  END IF;
  IF v_red.merchant_id <> v_shop_id THEN
    RAISE EXCEPTION 'This reward belongs to a different shop';
  END IF;

  -- Re-check balance to block the double-pending exploit (two pending
  -- redemptions off one balance; first zeroes it, second must fail).
  SELECT points INTO v_balance FROM customers WHERE id = v_red.customer_id FOR UPDATE;
  IF v_balance < v_red.points_spent THEN
    RAISE EXCEPTION 'Customer no longer has enough points';
  END IF;

  -- Reset points to zero via the existing transactions trigger.
  INSERT INTO transactions (customer_id, shop_id, shop_name, type, amount, points)
  VALUES (v_red.customer_id, v_shop_id, v_shop_name, 'redeem', NULL, -v_balance);

  UPDATE redemptions
     SET status = 'validated', validated_at = now(), points_at_redemption = v_balance
   WHERE id = v_red.id;

  UPDATE rewards SET redemptions_total = redemptions_total + 1 WHERE id = v_red.reward_id;

  UPDATE customers
     SET total_points_redeemed = COALESCE(total_points_redeemed, 0) + v_balance,
         total_redemptions     = COALESCE(total_redemptions, 0) + 1
   WHERE id = v_red.customer_id;

  SELECT reward_title INTO v_reward_title FROM rewards    WHERE id = v_red.reward_id;
  SELECT name         INTO v_customer_name FROM customers WHERE id = v_red.customer_id;

  RETURN json_build_object(
    'status',            'validated',
    'customer_name',     v_customer_name,
    'reward_title',      v_reward_title,
    'points_reset_from', v_balance,
    'tier',              v_red.points_spent
  );
END;
$$;

-- ============================================================================
-- 7. RLS — lock the new tables. Reads that customers need are public;
--    all writes go through the SECURITY DEFINER RPCs above.
-- ============================================================================
ALTER TABLE tiers       ENABLE ROW LEVEL SECURITY;
ALTER TABLE rewards     ENABLE ROW LEVEL SECURITY;
ALTER TABLE redemptions ENABLE ROW LEVEL SECURITY;

-- tiers: public read.
DROP POLICY IF EXISTS tiers_read ON tiers;
CREATE POLICY tiers_read ON tiers FOR SELECT USING (true);

-- rewards: public read of active rewards (customer browser). No anon writes —
-- merchant CRUD will be added as login_code-gated RPCs in Phase 3.
DROP POLICY IF EXISTS rewards_read ON rewards;
CREATE POLICY rewards_read ON rewards FOR SELECT USING (is_active);

-- redemptions: read allowed so the customer app can poll its QR status.
-- (Codes are single-use and merchant-scoped, so read exposure is low-risk.)
-- No anon writes — only the RPCs touch this table.
DROP POLICY IF EXISTS redemptions_read ON redemptions;
CREATE POLICY redemptions_read ON redemptions FOR SELECT USING (true);

-- ============================================================================
-- 8. Grants — expose only the two RPCs to the anon/authenticated roles.
-- ============================================================================
GRANT EXECUTE ON FUNCTION redeem_reward(text, uuid)          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION validate_redemption(text, text)    TO anon, authenticated;

COMMIT;

-- ============================================================================
-- 9. Per-shop login codes — set these to real values before trader testing.
--    Each trader validates redemptions with their own code.
--    Edit shop names + codes to match your shops, then run:
--
--    UPDATE shops SET login_code = 'HAMIL24' WHERE name = 'Blue Stone Café';
--    UPDATE shops SET login_code = 'DUMP38'  WHERE name = 'Village Bakery';
--
--    Sanity check — every active shop should have a code:
--    SELECT name, login_code FROM shops WHERE active ORDER BY name;
-- ============================================================================

-- ============================================================================
-- 10. Seed rewards — because the merchant reward-creation UI is V2.1, seed a
--     few rewards here so the customer + validate loop works end to end.
--     These join by shop name to tier level, so no hard-coded UUIDs.
--     EDIT the shop names / titles / tiers to match your real shops.
-- ============================================================================
INSERT INTO rewards (merchant_id, tier_id, reward_title, reward_description, estimated_value, monthly_redemption_cap)
SELECT s.id, t.id, 'Free coffee', 'Any regular coffee, dine-in or takeaway', 4.00, 30
FROM shops s, tiers t WHERE s.name = 'Blue Stone Café' AND t.tier_level = 10;

INSERT INTO rewards (merchant_id, tier_id, reward_title, reward_description, estimated_value, monthly_redemption_cap)
SELECT s.id, t.id, '$10 off breakfast', 'Minimum $25 spend', 10.00, 20
FROM shops s, tiers t WHERE s.name = 'Blue Stone Café' AND t.tier_level = 30;

INSERT INTO rewards (merchant_id, tier_id, reward_title, reward_description, estimated_value, monthly_redemption_cap)
SELECT s.id, t.id, '2 free croissants', 'Any flavour, freshly baked', 8.00, NULL
FROM shops s, tiers t WHERE s.name = 'Village Bakery' AND t.tier_level = 20;

INSERT INTO rewards (merchant_id, tier_id, reward_title, reward_description, estimated_value, monthly_redemption_cap)
SELECT s.id, t.id, 'Free meal', 'Any main from the à la carte menu', 40.00, 10
FROM shops s, tiers t WHERE s.name = 'Village Bakery' AND t.tier_level = 100;

-- Verify what got seeded (should show the rows above):
-- SELECT r.reward_title, t.tier_level, s.name
--   FROM rewards r JOIN tiers t ON t.id=r.tier_id JOIN shops s ON s.id=r.merchant_id
--  ORDER BY t.tier_level;
