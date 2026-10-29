BEGIN;

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
  -- Purchases and shopper QR check-ins are valid passport visits.
  IF NEW.type NOT IN ('purchase', 'checkin') THEN RETURN NEW; END IF;

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

  -- Purchases retain minimum spend; QR check-ins have no spend requirement.
  IF NEW.type = 'purchase' THEN
    v_min := COALESCE(
      v_campaign.min_spend,
      (SELECT value::numeric FROM pilot_config WHERE key = 'passport_min_spend'),
      10
    );
    IF NEW.amount IS NULL OR NEW.amount < v_min THEN RETURN NEW; END IF;
  END IF;

  INSERT INTO passport_stamps (customer_id, shop_id, campaign_id, visit_date, spend_amount)
  VALUES (NEW.customer_id, NEW.shop_id, v_campaign.id, v_today, CASE WHEN NEW.type = 'purchase' THEN NEW.amount ELSE NULL END)
  ON CONFLICT (customer_id, shop_id, campaign_id, visit_date) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS award_passport_stamp ON transactions;
CREATE TRIGGER award_passport_stamp
  AFTER INSERT ON transactions
  FOR EACH ROW EXECUTE FUNCTION award_passport_stamp();

COMMIT;
