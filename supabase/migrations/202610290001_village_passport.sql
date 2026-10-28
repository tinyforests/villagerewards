-- ============================================================================
-- Village Rewards — Layer 2: Village Passport
-- Schema patch. Run manually in the Supabase SQL Editor AFTER review.
-- Idempotent where practical. REVIEW BEFORE RUNNING.
--
-- Depends on:
--   * V1 base: customers(id text pk, points int, ...), shops(id uuid pk, name,
--     active, ...), transactions(..., type, amount, points, created_at) and the
--     AFTER INSERT trigger that maintains customers.points += NEW.points.
--   * docs/schema-v2.sql (Layer 1: rewards/redemptions/tiers + RPCs) deployed.
--
-- Model:
--   Layer 1 (per-trader stamp cards) = schema-v2 rewards(reward_type='stamp').
--     customers.points stays the under-the-hood balance; UI relabels to "stamps".
--   Layer 2 (this file) = a separate "passport" stamp for visiting DIFFERENT
--     traders during a fixed campaign period. Association/council funded.
--
-- Rules (locked in):
--   * One passport stamp per customer per trader per day (UNIQUE constraint).
--   * Qualifying visit = a 'purchase' transaction of >= campaign.min_spend ($10).
--   * Fresh passport each round: progress is scoped to campaign_id, so a new
--     campaign starts everyone at zero.
--   * Only shops with passport_active = true count toward a campaign.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. shops — participation flag for the current passport campaign.
-- ----------------------------------------------------------------------------
ALTER TABLE shops ADD COLUMN IF NOT EXISTS passport_active boolean DEFAULT false;

-- ----------------------------------------------------------------------------
-- 2. passport_campaigns — one row per fixed-period round.
--    (min_spend + period folded in from the requested ALTERs.)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS passport_campaigns (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  village            varchar(100) NOT NULL,
  name               varchar(200) NOT NULL,
  required_shops     integer NOT NULL,                 -- e.g. 6 traders to qualify
  reward_description text,                              -- prize, per campaign
  funded_by          varchar(200),                     -- e.g. 'Auburn Village Association'
  period             text CHECK (period IN ('monthly', 'quarterly')),
  min_spend          numeric(10,2) DEFAULT 10,          -- min $ per visit to earn a stamp
  start_date         date NOT NULL,
  end_date           date NOT NULL,
  is_active          boolean DEFAULT true,
  created_at         timestamptz DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- 3. passport_stamps — one stamp per customer per trader per day per campaign.
--    visit_date is DATE (not timestamp) so the UNIQUE constraint enforces the
--    one-per-trader-per-day rule.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS passport_stamps (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id  varchar(6) REFERENCES customers(id),
  shop_id      uuid REFERENCES shops(id),
  campaign_id  uuid REFERENCES passport_campaigns(id) ON DELETE CASCADE,
  visit_date   date NOT NULL,
  spend_amount numeric(10,2),
  created_at   timestamptz DEFAULT now(),
  CONSTRAINT passport_one_per_trader_per_day
    UNIQUE (customer_id, shop_id, campaign_id, visit_date)
);

CREATE INDEX IF NOT EXISTS idx_passport_stamps_progress
  ON passport_stamps (campaign_id, customer_id);

-- ----------------------------------------------------------------------------
-- 4. Global default min spend (fallback when a campaign leaves min_spend null).
--    pilot_config is the existing key/value table (same one holding
--    trader_pilot_code).
-- ----------------------------------------------------------------------------
INSERT INTO pilot_config (key, value) VALUES ('passport_min_spend', '10')
ON CONFLICT (key) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 5. passport_progress — per customer, per campaign rollup for the widget/draw.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW passport_progress AS
SELECT
  ps.customer_id,
  ps.campaign_id,
  count(DISTINCT ps.shop_id)::integer                              AS unique_traders_visited,
  c.required_shops,
  (count(DISTINCT ps.shop_id) >= c.required_shops)                 AS qualifies,
  GREATEST(c.required_shops - count(DISTINCT ps.shop_id), 0)::integer AS shops_remaining
FROM passport_stamps ps
JOIN passport_campaigns c ON c.id = ps.campaign_id
GROUP BY ps.customer_id, ps.campaign_id, c.required_shops;

-- ----------------------------------------------------------------------------
-- 6. Earning — award a passport stamp on a qualifying purchase.
--    AFTER INSERT on transactions. SECURITY DEFINER so it runs with owner
--    rights (anon inserts the purchase; this writes the locked passport table).
--    The UNIQUE constraint + ON CONFLICT DO NOTHING make repeat visits same-day
--    a graceful no-op.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION award_passport_stamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_campaign   passport_campaigns%ROWTYPE;
  v_min        numeric;
  v_today      date := (now() AT TIME ZONE 'Australia/Melbourne')::date;
BEGIN
  -- Only purchases earn passport stamps.
  IF NEW.type <> 'purchase' THEN RETURN NEW; END IF;

  -- Shop must be opted into the passport.
  IF NOT EXISTS (SELECT 1 FROM shops WHERE id = NEW.shop_id AND passport_active) THEN
    RETURN NEW;
  END IF;

  -- The campaign whose fixed period covers today.
  SELECT * INTO v_campaign
    FROM passport_campaigns
   WHERE is_active AND v_today BETWEEN start_date AND end_date
   ORDER BY start_date DESC
   LIMIT 1;
  IF NOT FOUND THEN RETURN NEW; END IF;

  -- Min spend: campaign value, else global pilot_config default, else 10.
  v_min := COALESCE(
    v_campaign.min_spend,
    (SELECT value::numeric FROM pilot_config WHERE key = 'passport_min_spend'),
    10
  );
  IF NEW.amount IS NULL OR NEW.amount < v_min THEN RETURN NEW; END IF;

  INSERT INTO passport_stamps (customer_id, shop_id, campaign_id, visit_date, spend_amount)
  VALUES (NEW.customer_id, NEW.shop_id, v_campaign.id, v_today, NEW.amount)
  ON CONFLICT (customer_id, shop_id, campaign_id, visit_date) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS award_passport_stamp ON transactions;
CREATE TRIGGER award_passport_stamp
  AFTER INSERT ON transactions
  FOR EACH ROW EXECUTE FUNCTION award_passport_stamp();

-- ----------------------------------------------------------------------------
-- 7. RLS — lock the new tables; public SELECT so the customer app can read the
--    active campaign + its own progress. All writes go through the SECURITY
--    DEFINER trigger (passport_stamps) or admin (campaigns); no anon writes.
-- ----------------------------------------------------------------------------
ALTER TABLE passport_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE passport_stamps    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS passport_campaigns_read ON passport_campaigns;
CREATE POLICY passport_campaigns_read ON passport_campaigns FOR SELECT USING (true);

DROP POLICY IF EXISTS passport_stamps_read ON passport_stamps;
CREATE POLICY passport_stamps_read ON passport_stamps FOR SELECT USING (true);

GRANT SELECT ON passport_progress TO anon, authenticated;

COMMIT;

-- ============================================================================
-- Seed example (EDIT then run separately once shops/codes are set):
--
--   -- Flag participating traders:
--   UPDATE shops SET passport_active = true WHERE active;  -- or a named subset
--
--   -- Launch campaign:
--   INSERT INTO passport_campaigns
--     (village, name, required_shops, reward_description, funded_by, period,
--      min_spend, start_date, end_date)
--   VALUES
--     ('Auburn Village', 'Auburn Spring Passport', 6,
--      'Win an iPhone', 'Auburn Village Association', 'monthly',
--      10, date_trunc('month', now())::date,
--      (date_trunc('month', now()) + interval '1 month - 1 day')::date);
--
--   -- Sanity:
--   SELECT * FROM passport_progress WHERE campaign_id = '...';
-- ============================================================================
