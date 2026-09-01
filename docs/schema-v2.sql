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
-- 4. rewards — merchant reward, one of two types:
--      'tier'  — gated on village-wide points (customer.points >= tier).
--                Redeeming resets the customer's village points to zero.
--      'stamp' — gated on N qualifying PURCHASES at that shop (e.g. buy 10
--                coffees, get one free). Self-funding; redeeming resets only
--                that card's stamps, NOT the customer's village points.
--    Cap is enforced by LIVE COUNT of validated redemptions this month
--    (see redeem_reward), so there is no monthly counter to reset.
--    redemptions_total is a lifetime convenience stat only.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rewards (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id            uuid NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  reward_type            varchar(20) NOT NULL DEFAULT 'tier',  -- 'tier' | 'stamp'
  tier_id                uuid REFERENCES tiers(id),            -- required when type='tier'
  stamp_goal             integer,                              -- required when type='stamp' (e.g. 10)
  stamp_min_amount       numeric(10,2),                        -- min $ purchase to earn a stamp; NULL = any purchase
  reward_title           varchar(200) NOT NULL,
  reward_description     text,
  estimated_value        numeric(10,2),
  is_active              boolean DEFAULT true,        -- pause == false
  monthly_redemption_cap integer,                     -- NULL / 0 == unlimited
  redemptions_total      integer DEFAULT 0,
  created_at             timestamptz DEFAULT now(),
  updated_at             timestamptz DEFAULT now(),
  CONSTRAINT rewards_type_ck CHECK (
    (reward_type = 'tier'  AND tier_id IS NOT NULL) OR
    (reward_type = 'stamp' AND stamp_goal IS NOT NULL AND stamp_goal > 0)
  )
);

CREATE INDEX IF NOT EXISTS idx_rewards_tier     ON rewards (tier_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_rewards_merchant ON rewards (merchant_id);
CREATE INDEX IF NOT EXISTS idx_rewards_stamp    ON rewards (merchant_id) WHERE reward_type = 'stamp' AND is_active;

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
  reward_type          varchar(20) NOT NULL DEFAULT 'tier',  -- 'tier' | 'stamp'
  tier_id              uuid REFERENCES tiers(id),
  points_spent         integer,                        -- tier gate (tier redemptions)
  points_at_redemption integer,                        -- balance zeroed on validate (tier)
  stamps_spent         integer,                        -- stamps consumed (stamp redemptions)
  redemption_code      varchar(100) UNIQUE NOT NULL,
  status               varchar(20) DEFAULT 'pending',  -- pending/validated/cancelled/expired
  created_at           timestamptz DEFAULT now(),
  validated_at         timestamptz,                    -- also the reset marker for stamp cards
  expires_at           timestamptz NOT NULL,           -- created_at + 10 min
  notes                text
);

CREATE INDEX IF NOT EXISTS idx_redemptions_code     ON redemptions (redemption_code);
CREATE INDEX IF NOT EXISTS idx_redemptions_customer ON redemptions (customer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_redemptions_cap      ON redemptions (reward_id, status, validated_at);
-- Supports "stamps since last redemption of this card" lookups.
CREATE INDEX IF NOT EXISTS idx_redemptions_stampreset
  ON redemptions (customer_id, reward_id, status, validated_at DESC);

-- ============================================================================
-- 6. RPCs — the only trusted surface. SECURITY DEFINER so they run with the
--    owner's rights and bypass RLS; tables below stay locked to anon.
-- ============================================================================

-- stamp_progress: how many qualifying purchases a customer has made at a stamp
-- reward's shop SINCE their last validated redemption of that card. Single
-- source of truth, reused by redeem_reward, validate_redemption, get_stamp_cards.
CREATE OR REPLACE FUNCTION stamp_progress(p_customer_id text, p_reward_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::integer
  FROM transactions t
  JOIN rewards r ON r.id = p_reward_id
  WHERE t.customer_id = p_customer_id
    AND t.shop_id = r.merchant_id
    AND t.type = 'purchase'
    AND (r.stamp_min_amount IS NULL OR t.amount >= r.stamp_min_amount)
    AND t.created_at > COALESCE(
          (SELECT max(rd.validated_at) FROM redemptions rd
            WHERE rd.customer_id = p_customer_id
              AND rd.reward_id = p_reward_id
              AND rd.status = 'validated'),
          '-infinity'::timestamptz);
$$;

-- redeem_reward: customer initiates. Branches on reward type; validates the gate
-- ('tier' -> village points, 'stamp' -> qualifying purchases at the shop) plus
-- the monthly cap, then creates a pending redemption with a 10-minute expiry.
-- Never changes points or stamps — the reset happens on merchant validation.
CREATE OR REPLACE FUNCTION redeem_reward(p_customer_id text, p_reward_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reward       rewards%ROWTYPE;
  v_tier         tiers%ROWTYPE;
  v_balance      integer;
  v_used         integer;
  v_stamps       integer;
  v_points_spent integer;
  v_stamps_spent integer;
  v_tier_id      uuid;
  v_code         text;
  v_expires      timestamptz;
BEGIN
  SELECT * INTO v_reward FROM rewards WHERE id = p_reward_id;
  IF NOT FOUND              THEN RAISE EXCEPTION 'Reward not found'; END IF;
  IF NOT v_reward.is_active THEN RAISE EXCEPTION 'Reward is not available'; END IF;

  PERFORM 1 FROM customers WHERE id = p_customer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;

  -- Monthly cap (both types): live-count validated redemptions this month.
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

  IF v_reward.reward_type = 'tier' THEN
    SELECT * INTO v_tier FROM tiers WHERE id = v_reward.tier_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reward tier missing'; END IF;
    SELECT points INTO v_balance FROM customers WHERE id = p_customer_id;
    IF v_balance < v_tier.points_required THEN
      RAISE EXCEPTION 'Not enough points for this tier';
    END IF;
    v_points_spent := v_tier.points_required;
    v_tier_id      := v_tier.id;
  ELSE  -- 'stamp'
    v_stamps := stamp_progress(p_customer_id, v_reward.id);
    IF v_stamps < v_reward.stamp_goal THEN
      RAISE EXCEPTION 'Not enough stamps yet';
    END IF;
    v_stamps_spent := v_reward.stamp_goal;
  END IF;

  v_code    := upper(substring(replace(gen_random_uuid()::text, '-', '') for 12));
  v_expires := now() + interval '10 minutes';

  INSERT INTO redemptions (customer_id, merchant_id, reward_id, reward_type, tier_id,
                           points_spent, stamps_spent, redemption_code, status, expires_at)
  VALUES (p_customer_id, v_reward.merchant_id, v_reward.id, v_reward.reward_type, v_tier_id,
          v_points_spent, v_stamps_spent, v_code, 'pending', v_expires);

  RETURN json_build_object(
    'redemption_code', v_code,
    'expires_at',      v_expires,
    'reward_title',    v_reward.reward_title,
    'reward_type',     v_reward.reward_type,
    'points_required', v_points_spent,
    'stamps_required', v_stamps_spent
  );
END;
$$;

-- validate_redemption: merchant confirms. Atomic. Trader proves identity by
-- passing their shop login_code (not a client-supplied shop_id), so a merchant
-- can only validate redemptions for a shop whose PIN they know. Branches on
-- reward type: 'tier' zeroes the customer's village points; 'stamp' resets only
-- that card (village points untouched) and logs a 0-point 'reward' history row.
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
  v_stamps        integer;
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

  SELECT reward_title INTO v_reward_title FROM rewards    WHERE id = v_red.reward_id;
  SELECT name         INTO v_customer_name FROM customers WHERE id = v_red.customer_id;

  IF v_red.reward_type = 'tier' THEN
    -- Lock customer; re-check balance to block the double-pending exploit
    -- (two pending tier redemptions off one balance; first zeroes it).
    SELECT points INTO v_balance FROM customers WHERE id = v_red.customer_id FOR UPDATE;
    IF v_balance < v_red.points_spent THEN
      RAISE EXCEPTION 'Customer no longer has enough points';
    END IF;

    -- Reset village points to zero via the existing transactions trigger.
    INSERT INTO transactions (customer_id, shop_id, shop_name, type, amount, points)
    VALUES (v_red.customer_id, v_shop_id, v_shop_name, 'redeem', NULL, -v_balance);

    UPDATE redemptions
       SET status = 'validated', validated_at = now(), points_at_redemption = v_balance
     WHERE id = v_red.id;

    UPDATE customers
       SET total_points_redeemed = COALESCE(total_points_redeemed, 0) + v_balance,
           total_redemptions     = COALESCE(total_redemptions, 0) + 1
     WHERE id = v_red.customer_id;
  ELSE  -- 'stamp'
    -- Re-check stamps still meet the goal (blocks double-pending stamp cards).
    v_stamps := stamp_progress(v_red.customer_id, v_red.reward_id);
    IF v_stamps < v_red.stamps_spent THEN
      RAISE EXCEPTION 'Customer no longer has enough stamps';
    END IF;

    -- Log the free item in history WITHOUT touching village points (0-point
    -- 'reward' row). validated_at below is the reset marker for this card, so
    -- future stamps count from now.  NOTE: if transactions.type has a CHECK
    -- constraint, ensure it permits 'reward' (see the note under section 8).
    INSERT INTO transactions (customer_id, shop_id, shop_name, type, amount, points)
    VALUES (v_red.customer_id, v_shop_id, v_shop_name, 'reward', NULL, 0);

    UPDATE redemptions
       SET status = 'validated', validated_at = now()
     WHERE id = v_red.id;

    UPDATE customers
       SET total_redemptions = COALESCE(total_redemptions, 0) + 1
     WHERE id = v_red.customer_id;
  END IF;

  UPDATE rewards SET redemptions_total = redemptions_total + 1 WHERE id = v_red.reward_id;

  RETURN json_build_object(
    'status',            'validated',
    'reward_type',       v_red.reward_type,
    'customer_name',     v_customer_name,
    'reward_title',      v_reward_title,
    'points_reset_from', COALESCE(v_balance, 0),
    'tier',              v_red.points_spent,
    'stamps',            v_red.stamps_spent
  );
END;
$$;

-- get_stamp_cards: everything the customer app needs to render shop cards in one
-- call — current stamps (since last redemption) and whether each is ready.
CREATE OR REPLACE FUNCTION get_stamp_cards(p_customer_id text)
RETURNS TABLE (
  reward_id          uuid,
  merchant_id        uuid,
  shop_name          text,
  reward_title       varchar,
  reward_description text,
  stamp_goal         integer,
  current_stamps     integer,
  ready              boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT r.id, r.merchant_id, s.name::text, r.reward_title, r.reward_description,
         r.stamp_goal,
         stamp_progress(p_customer_id, r.id) AS current_stamps,
         (stamp_progress(p_customer_id, r.id) >= r.stamp_goal) AS ready
  FROM rewards r
  JOIN shops s ON s.id = r.merchant_id
  WHERE r.reward_type = 'stamp' AND r.is_active
  ORDER BY s.name, r.reward_title;
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
-- 8. Grants — expose only the customer/trader-facing RPCs. stamp_progress is
--    internal (called by the definer functions), so it is NOT granted to anon.
-- ============================================================================
GRANT EXECUTE ON FUNCTION redeem_reward(text, uuid)       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION validate_redemption(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_stamp_cards(text)           TO anon, authenticated;

-- Allow the 'reward' transaction type.
-- validate_redemption logs stamp-card claims as a 0-point 'reward' row so they
-- show in history without changing the balance. This project's transactions
-- table HAS a CHECK on `type` (transactions_type_check), so rebuild it to allow
-- every type already present in the data PLUS 'reward'. Safe against existing
-- rows; no manual list to edit. (If your table has no such constraint, this is
-- a harmless no-op on the DROP and just adds the constraint.)
DO $$
DECLARE allowed text;
BEGIN
  SELECT string_agg(quote_literal(t), ', ') INTO allowed
  FROM (
    SELECT 'purchase' AS t UNION SELECT 'checkin' UNION SELECT 'redeem'
    UNION SELECT 'bonus' UNION SELECT 'reward'
    UNION SELECT type FROM transactions WHERE type IS NOT NULL
  ) s;
  EXECUTE 'ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_type_check';
  EXECUTE 'ALTER TABLE transactions ADD CONSTRAINT transactions_type_check CHECK (type IN (' || allowed || '))';
END $$;

COMMIT;

-- Verify the rebuilt constraint now includes 'reward':
--   SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='transactions_type_check';

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

-- Stamp card (self-funding): buy N qualifying purchases at ONE shop, get a
-- free reward. reward_type='stamp', no tier. stamp_min_amount is optional — set
-- it to require ~a coffee's price so a $2 cookie doesn't earn a stamp.
INSERT INTO rewards (merchant_id, reward_type, stamp_goal, stamp_min_amount,
                     reward_title, reward_description, estimated_value, monthly_redemption_cap)
SELECT s.id, 'stamp', 10, 4.00, 'Free coffee', 'Buy 10 coffees, get one free', 4.00, NULL
FROM shops s WHERE s.name = 'Blue Stone Café';

-- Verify what got seeded:
-- Tier rewards:
--   SELECT r.reward_title, t.tier_level, s.name
--     FROM rewards r JOIN tiers t ON t.id=r.tier_id JOIN shops s ON s.id=r.merchant_id
--    WHERE r.reward_type='tier' ORDER BY t.tier_level;
-- Stamp cards:
--   SELECT r.reward_title, r.stamp_goal, r.stamp_min_amount, s.name
--     FROM rewards r JOIN shops s ON s.id=r.merchant_id
--    WHERE r.reward_type='stamp' ORDER BY s.name;
