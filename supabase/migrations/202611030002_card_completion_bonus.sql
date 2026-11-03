BEGIN;
-- Award once when a shop stamp-card redemption is actually completed.
ALTER TABLE public.redemptions ADD COLUMN IF NOT EXISTS completion_bonus_points integer NOT NULL DEFAULT 0;
CREATE TABLE IF NOT EXISTS public.card_completion_bonuses (
  redemption_id uuid PRIMARY KEY REFERENCES public.redemptions(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.card_completion_bonuses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.card_completion_bonuses FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.award_card_completion_bonus()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM 'validated' OR OLD.status='validated' OR NEW.reward_type IS DISTINCT FROM 'stamp' THEN RETURN NEW; END IF;
  INSERT INTO card_completion_bonuses(redemption_id) VALUES(NEW.id)
    ON CONFLICT DO NOTHING RETURNING redemption_id INTO v_id;
  IF v_id IS NOT NULL THEN
    INSERT INTO transactions(customer_id,shop_id,shop_name,type,amount,points,note,created_at)
      VALUES(NEW.customer_id,NULL,'Village Rewards','bonus',NULL,1,'shop_card_completion_bonus',clock_timestamp());
    NEW.completion_bonus_points := 1;
  END IF;
  RETURN NEW;
END;
$$;
CREATE OR REPLACE TRIGGER award_card_completion_bonus BEFORE UPDATE OF status ON public.redemptions
  FOR EACH ROW EXECUTE FUNCTION public.award_card_completion_bonus();
-- Include confirmed bonus metadata for the shopper QR flow.
CREATE OR REPLACE FUNCTION public.redeem_shop_stamp(p_customer_id text,p_reward_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_login text; v_pending json; v_result json;
BEGIN
  PERFORM 1 FROM customers WHERE id=p_customer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;
  SELECT s.login_code INTO v_login FROM rewards r JOIN shops s ON s.id=r.merchant_id
    WHERE r.id=p_reward_id AND r.reward_type='stamp' AND r.is_active AND s.active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active stamp reward not found'; END IF;
  IF v_login IS NULL THEN RAISE EXCEPTION 'Shop redemption is not configured'; END IF;
  v_pending := redeem_reward(p_customer_id,p_reward_id);
  v_result := validate_redemption(v_pending->>'redemption_code',v_login);
  RETURN (v_result::jsonb || jsonb_build_object('completion_bonus_points',
    (SELECT completion_bonus_points FROM redemptions WHERE redemption_code=v_pending->>'redemption_code')))::json;
END;
$$;
COMMIT;
