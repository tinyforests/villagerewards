BEGIN;
-- Preserve surplus village stamps when collecting a tier reward.
CREATE OR REPLACE FUNCTION public.validate_redemption(p_redemption_code text, p_login_code text)
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
    -- Serialize spending and recheck the balance at collection.
    SELECT points INTO v_balance FROM customers WHERE id = v_red.customer_id FOR UPDATE;
    IF v_red.points_spent IS NULL OR v_red.points_spent <= 0 THEN
      RAISE EXCEPTION 'Invalid tier stamp cost';
    END IF;
    IF v_balance IS NULL OR v_balance < v_red.points_spent THEN
      RAISE EXCEPTION 'Customer no longer has enough points';
    END IF;

    -- Deduct only the confirmed reward cost through the balance trigger.
    INSERT INTO transactions (customer_id, shop_id, shop_name, type, amount, points)
    VALUES (v_red.customer_id, v_shop_id, v_shop_name, 'redeem', NULL, -v_red.points_spent);

    UPDATE redemptions
       SET status = 'validated', validated_at = now(), points_at_redemption = v_red.points_spent
     WHERE id = v_red.id;

    UPDATE customers
       SET total_points_redeemed = COALESCE(total_points_redeemed, 0) + v_red.points_spent,
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
    'points_spent', CASE WHEN v_red.reward_type = 'tier' THEN v_red.points_spent ELSE 0 END,
    'points_remaining', CASE WHEN v_red.reward_type = 'tier' THEN v_balance - v_red.points_spent ELSE NULL END,
    'tier',              v_red.points_spent,
    'stamps',            v_red.stamps_spent
  );
END;
$$;
COMMIT;
