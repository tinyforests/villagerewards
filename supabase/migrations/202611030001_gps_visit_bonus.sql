BEGIN;
-- New GPS visits only. Historical/staff check-ins and QR purchases are not counted.
CREATE TABLE IF NOT EXISTS public.gps_visit_progress (
  customer_id text PRIMARY KEY REFERENCES public.customers(id) ON DELETE CASCADE,
  visits integer NOT NULL DEFAULT 0 CHECK (visits BETWEEN 0 AND 5),
  bonuses integer NOT NULL DEFAULT 0 CHECK (bonuses >= 0)
);
ALTER TABLE public.gps_visit_progress ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.gps_visit_progress FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_gps_visit_progress(p_customer_id text)
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT json_build_object('visits',COALESCE((SELECT visits FROM gps_visit_progress WHERE customer_id=p_customer_id),0),'goal',6);
$$;

CREATE OR REPLACE FUNCTION public.record_gps_visit(
  p_customer_id text, p_shop_id uuid,
  p_lat double precision DEFAULT NULL, p_lng double precision DEFAULT NULL,
  p_distance double precision DEFAULT NULL
) RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_shop text;
  v_visits integer;
  v_awarded boolean := false;
BEGIN
  PERFORM 1 FROM customers WHERE id=p_customer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;
  SELECT name INTO v_shop FROM shops WHERE id=p_shop_id AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active shop not found'; END IF;
  -- GPS/DEV_MODE eligibility is unchanged. Supplied distances must be in range.
  IF p_distance IS NOT NULL AND (p_distance < 0 OR p_distance > 150 OR p_distance='NaN'::float8) THEN
    RAISE EXCEPTION 'Move within 150m of the shop';
  END IF;
  INSERT INTO gps_visit_progress(customer_id) VALUES(p_customer_id) ON CONFLICT DO NOTHING;
  -- Lock one counter across tabs/shops; recording, bonus and counter commit together.
  SELECT visits INTO v_visits FROM gps_visit_progress WHERE customer_id=p_customer_id FOR UPDATE;
  IF EXISTS(SELECT 1 FROM transactions WHERE customer_id=p_customer_id AND shop_id=p_shop_id
    AND type='checkin' AND created_at >= now()-interval '4 hours') THEN
    RETURN json_build_object('duplicate',true,'awarded',false,'visits',v_visits,'goal',6);
  END IF;
  INSERT INTO transactions(customer_id,shop_id,shop_name,type,amount,points,note,customer_lat,customer_lng,distance_m)
    VALUES(p_customer_id,p_shop_id,v_shop,'checkin',NULL,0,'gps_visit',p_lat,p_lng,p_distance);
  v_visits := v_visits+1;
  IF v_visits=6 THEN
    INSERT INTO transactions(customer_id,shop_id,shop_name,type,amount,points,note,created_at)
      VALUES(p_customer_id,NULL,'Village Rewards','bonus',NULL,1,'gps_checkin_bonus',clock_timestamp());
    v_visits := 0;
    v_awarded := true;
  END IF;
  UPDATE gps_visit_progress SET visits=v_visits,bonuses=bonuses+CASE WHEN v_awarded THEN 1 ELSE 0 END
    WHERE customer_id=p_customer_id;
  RETURN json_build_object('duplicate',false,'awarded',v_awarded,'visits',v_visits,'goal',6);
END;
$$;
REVOKE ALL ON FUNCTION public.get_gps_visit_progress(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_gps_visit(text,uuid,double precision,double precision,double precision) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_gps_visit_progress(text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_gps_visit(text,uuid,double precision,double precision,double precision) TO anon,authenticated;
COMMIT;
