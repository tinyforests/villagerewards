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
  -- GPS check-ins record visits only; purchases and QR purchases qualify.
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

  -- Only QR purchases are exempt from minimum spend.
  IF NEW.note IS DISTINCT FROM 'qr_scan' THEN
    v_min := COALESCE(
      v_campaign.min_spend,
      (SELECT value::numeric FROM pilot_config WHERE key = 'passport_min_spend'),
      10
    );
    IF NEW.amount IS NULL OR NEW.amount < v_min THEN RETURN NEW; END IF;
  END IF;

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

-- Shop cards count QR purchases and qualifying purchases; GPS visits do not count.
CREATE OR REPLACE FUNCTION public.stamp_progress(p_customer_id text, p_reward_id uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::integer
  FROM transactions t JOIN rewards r ON r.id = p_reward_id
  WHERE t.customer_id = p_customer_id AND t.shop_id = r.merchant_id
    AND t.type = 'purchase'
    AND (t.note = 'qr_scan' OR r.stamp_min_amount IS NULL OR t.amount >= r.stamp_min_amount)
    AND t.created_at > COALESCE(
      (SELECT max(rd.validated_at) FROM redemptions rd
       WHERE rd.customer_id = p_customer_id AND rd.reward_id = p_reward_id AND rd.status = 'validated'),
      '-infinity'::timestamptz);
$$;

COMMIT;
