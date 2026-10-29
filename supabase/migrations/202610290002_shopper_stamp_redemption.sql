-- Shop card progress now counts shopper QR stamps as well as qualifying purchases.
CREATE OR REPLACE FUNCTION public.stamp_progress(p_customer_id text, p_reward_id uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::integer
  FROM transactions t JOIN rewards r ON r.id = p_reward_id
  WHERE t.customer_id = p_customer_id AND t.shop_id = r.merchant_id
    AND t.type IN ('purchase', 'checkin')
    AND (t.type = 'checkin' OR r.stamp_min_amount IS NULL OR t.amount >= r.stamp_min_amount)
    AND t.created_at > COALESCE(
      (SELECT max(rd.validated_at) FROM redemptions rd
       WHERE rd.customer_id = p_customer_id AND rd.reward_id = p_reward_id AND rd.status = 'validated'),
      '-infinity'::timestamptz);
$$;

-- Shopper scans a shop redemption QR and explicitly confirms an eligible card.
-- Reuse the existing reward limit, stamp count, history and reset logic.
CREATE OR REPLACE FUNCTION public.redeem_shop_stamp(p_customer_id text, p_reward_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_login text;
  v_pending json;
BEGIN
  -- Serialize shopper confirmations; a second request rechecks the reset card.
  PERFORM 1 FROM customers WHERE id = p_customer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;
  SELECT s.login_code INTO v_login FROM rewards r JOIN shops s ON s.id = r.merchant_id
    WHERE r.id = p_reward_id AND r.reward_type = 'stamp' AND r.is_active AND s.active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active stamp reward not found'; END IF;
  IF v_login IS NULL THEN RAISE EXCEPTION 'Shop redemption is not configured'; END IF;
  v_pending := redeem_reward(p_customer_id, p_reward_id);
  -- The PIN remains server-side. Both steps commit or roll back together.
  RETURN validate_redemption(v_pending->>'redemption_code', v_login);
END;
$$;
REVOKE ALL ON FUNCTION public.redeem_shop_stamp(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.redeem_shop_stamp(text, uuid) TO anon, authenticated;
