-- Additive staging migration. Does not convert, delete or relabel legacy points.
-- Requires existing public.shops(id uuid, name text, active boolean) and Supabase Auth.
BEGIN;
CREATE TABLE public.vr_members (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id),
 code text NOT NULL UNIQUE DEFAULT upper(replace(gen_random_uuid()::text,'-','')),
 balance integer NOT NULL DEFAULT 0 CHECK (balance >= 0),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.vr_staff (
 user_id uuid REFERENCES auth.users(id), shop_id uuid REFERENCES public.shops(id),
 PRIMARY KEY (user_id,shop_id)
);
CREATE TABLE public.vr_offers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), shop_id uuid NOT NULL REFERENCES public.shops(id),
 title text NOT NULL CHECK (length(title) BETWEEN 1 AND 160),
 conditions text NOT NULL CHECK (length(conditions) BETWEEN 1 AND 2000),
 cost integer NOT NULL CHECK (cost BETWEEN 1 AND 100000),
 stock integer NOT NULL CHECK (stock >= 0), active boolean NOT NULL DEFAULT true,
 created_by uuid NOT NULL REFERENCES auth.users(id), request_id uuid NOT NULL, UNIQUE(created_by,request_id),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.vr_claims (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES public.vr_members(user_id),
 offer_id uuid NOT NULL REFERENCES public.vr_offers(id), shop_id uuid NOT NULL REFERENCES public.shops(id),
 title text NOT NULL, conditions text NOT NULL, cost integer NOT NULL CHECK(cost>0),
 code text NOT NULL UNIQUE DEFAULT upper(replace(gen_random_uuid()::text,'-','')),
 request_id uuid NOT NULL, state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','fulfilled','cancelled','expired')),
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL DEFAULT now()+interval '15 minutes',
 fulfilled_at timestamptz, fulfilled_by uuid REFERENCES auth.users(id), UNIQUE(user_id,request_id)
);
CREATE TABLE public.vr_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES public.vr_members(user_id),
 shop_id uuid NOT NULL REFERENCES public.shops(id), actor_id uuid NOT NULL REFERENCES auth.users(id),
 kind text NOT NULL CHECK(kind IN ('purchase','reserve','release','refund')),
 delta integer NOT NULL CHECK(delta<>0), reference text, request_id uuid NOT NULL,
 claim_id uuid REFERENCES public.vr_claims(id), reverses uuid UNIQUE REFERENCES public.vr_events(id),
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(actor_id,request_id)
);
CREATE UNIQUE INDEX vr_purchase_reference ON public.vr_events(shop_id,reference) WHERE kind='purchase';
CREATE INDEX vr_events_member ON public.vr_events(user_id,created_at DESC);
CREATE INDEX vr_claims_pending ON public.vr_claims(user_id,state,expires_at);
ALTER TABLE public.vr_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vr_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vr_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vr_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vr_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.vr_members,public.vr_staff,public.vr_offers,public.vr_claims,public.vr_events FROM PUBLIC,anon,authenticated;
-- All access is through these scoped RPCs. No browser table writes or shared pilot codes.
CREATE FUNCTION public.vr_require_user() RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Please sign in.'; END IF;
 RETURN auth.uid();
END $$;
CREATE FUNCTION public.vr_require_staff(p_shop uuid) RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.vr_staff m JOIN public.shops s ON s.id=m.shop_id WHERE m.user_id=auth.uid() AND m.shop_id=p_shop AND s.active) THEN
  RAISE EXCEPTION 'You are not authorised for this shop.';
 END IF;
END $$;
-- Serialise pilot mutations using a single lock row, including cross-customer stock changes.
-- This intentionally favours correctness at pilot scale; load-test before expansion.
CREATE TABLE public.vr_write_lock(id integer PRIMARY KEY CHECK(id=1));
INSERT INTO public.vr_write_lock VALUES(1);
ALTER TABLE public.vr_write_lock ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.vr_write_lock FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.vr_lock() RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT id FROM public.vr_write_lock WHERE id=1 FOR UPDATE;
$$;
CREATE FUNCTION public.vr_release_expired() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.vr_claims%ROWTYPE;
BEGIN
 -- Caller must take vr_lock first. Also runnable only by owner, not browser roles.
 FOR c IN SELECT * FROM public.vr_claims WHERE state='pending' AND expires_at<=now() LOOP
  UPDATE public.vr_members SET balance=balance+c.cost WHERE user_id=c.user_id;
  UPDATE public.vr_offers SET stock=stock+1 WHERE id=c.offer_id;
  UPDATE public.vr_claims SET state='expired' WHERE id=c.id;
  INSERT INTO public.vr_events(user_id,shop_id,actor_id,kind,delta,request_id,claim_id)
   VALUES(c.user_id,c.shop_id,c.user_id,'release',c.cost,gen_random_uuid(),c.id);
 END LOOP;
END $$;
CREATE FUNCTION public.vr_dashboard() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=public.vr_require_user(); result jsonb;
BEGIN
 PERFORM public.vr_lock(); PERFORM public.vr_release_expired();
 INSERT INTO public.vr_members(user_id) VALUES(u) ON CONFLICT DO NOTHING;
 SELECT jsonb_build_object(
  'member',to_jsonb(m),
  'shops',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) ORDER BY s.name) FROM public.shops s WHERE s.active),'[]'::jsonb),
  'staff_shops',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'name',s.name)) FROM public.vr_staff x JOIN public.shops s ON s.id=x.shop_id WHERE x.user_id=u AND s.active),'[]'::jsonb),
  'offers',COALESCE((SELECT jsonb_agg(to_jsonb(o)||jsonb_build_object('shop_name',s.name) ORDER BY o.cost) FROM public.vr_offers o JOIN public.shops s ON s.id=o.shop_id WHERE o.active AND s.active AND o.stock>0),'[]'::jsonb),
  'claims',COALESCE((SELECT jsonb_agg(to_jsonb(c)||jsonb_build_object('shop_name',s.name) ORDER BY c.created_at DESC) FROM public.vr_claims c JOIN public.shops s ON s.id=c.shop_id WHERE c.user_id=u AND c.state='pending'),'[]'::jsonb),
  'activity',COALESCE((SELECT jsonb_agg(to_jsonb(e)) FROM (SELECT x.id,x.kind,x.delta,x.created_at,s.name AS shop_name FROM public.vr_events x JOIN public.shops s ON s.id=x.shop_id WHERE x.user_id=u ORDER BY x.created_at DESC LIMIT 20) e),'[]'::jsonb),
  'unique_shops',(SELECT count(DISTINCT e.shop_id) FROM public.vr_events e WHERE e.user_id=u AND e.kind='purchase' AND NOT EXISTS(SELECT 1 FROM public.vr_events rev WHERE rev.reverses=e.id))
 ) INTO result FROM public.vr_members m WHERE m.user_id=u;
 RETURN result;
END $$;
CREATE FUNCTION public.vr_award(p_shop uuid,p_code text,p_reference text,p_request uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=public.vr_require_user(); u uuid; previous public.vr_events%ROWTYPE; e public.vr_events%ROWTYPE; ref text:=upper(btrim(p_reference));
BEGIN
 PERFORM public.vr_require_staff(p_shop); PERFORM public.vr_lock();
 IF p_request IS NULL OR ref IS NULL OR length(ref) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Enter a receipt reference (up to 100 characters).'; END IF;
 SELECT user_id INTO u FROM public.vr_members WHERE code=upper(btrim(p_code));
 IF u IS NULL THEN RAISE EXCEPTION 'Customer code not found.'; END IF;
 SELECT * INTO previous FROM public.vr_events WHERE (actor_id=actor AND request_id=p_request) OR (shop_id=p_shop AND reference=ref AND kind='purchase') LIMIT 1;
 IF FOUND THEN
  IF previous.kind<>'purchase' OR previous.user_id<>u OR previous.shop_id<>p_shop OR previous.reference<>ref THEN RAISE EXCEPTION 'This reference or request belongs to another purchase.'; END IF;
  RETURN jsonb_build_object('id',previous.id,'duplicate',true);
 END IF;
 UPDATE public.vr_members SET balance=balance+1 WHERE user_id=u;
 INSERT INTO public.vr_events(user_id,shop_id,actor_id,kind,delta,reference,request_id) VALUES(u,p_shop,actor,'purchase',1,ref,p_request) RETURNING * INTO e;
 RETURN jsonb_build_object('id',e.id,'duplicate',false);
END $$;
CREATE FUNCTION public.vr_claim(p_offer uuid,p_request uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=public.vr_require_user(); o public.vr_offers%ROWTYPE; c public.vr_claims%ROWTYPE;
BEGIN
 PERFORM public.vr_lock(); PERFORM public.vr_release_expired();
 IF p_request IS NULL THEN RAISE EXCEPTION 'Missing request identifier.'; END IF;
 SELECT * INTO c FROM public.vr_claims WHERE user_id=u AND request_id=p_request;
 IF FOUND THEN
  IF c.offer_id<>p_offer THEN RAISE EXCEPTION 'Request already used for another reward.'; END IF;
  RETURN to_jsonb(c);
 END IF;
 SELECT o1.* INTO o FROM public.vr_offers o1 JOIN public.shops s ON s.id=o1.shop_id WHERE o1.id=p_offer AND o1.active AND s.active AND o1.stock>0;
 IF NOT FOUND THEN RAISE EXCEPTION 'This reward is no longer available.'; END IF;
 UPDATE public.vr_members SET balance=balance-o.cost WHERE user_id=u AND balance>=o.cost;
 IF NOT FOUND THEN RAISE EXCEPTION 'You need more available stamps for this reward.'; END IF;
 UPDATE public.vr_offers SET stock=stock-1 WHERE id=o.id;
 INSERT INTO public.vr_claims(user_id,offer_id,shop_id,title,conditions,cost,request_id) VALUES(u,o.id,o.shop_id,o.title,o.conditions,o.cost,p_request) RETURNING * INTO c;
 INSERT INTO public.vr_events(user_id,shop_id,actor_id,kind,delta,request_id,claim_id) VALUES(u,o.shop_id,u,'reserve',-o.cost,p_request,c.id);
 RETURN to_jsonb(c);
END $$;
CREATE FUNCTION public.vr_cancel(p_claim uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=public.vr_require_user(); c public.vr_claims%ROWTYPE;
BEGIN
 PERFORM public.vr_lock(); PERFORM public.vr_release_expired();
 SELECT * INTO c FROM public.vr_claims WHERE id=p_claim AND user_id=u;
 IF NOT FOUND THEN RAISE EXCEPTION 'Claim not found.'; END IF;
 IF c.state IN ('cancelled','expired') THEN RETURN; END IF;
 IF c.state<>'pending' THEN RAISE EXCEPTION 'This reward has already been collected.'; END IF;
 UPDATE public.vr_claims SET state='cancelled' WHERE id=c.id;
 UPDATE public.vr_members SET balance=balance+c.cost WHERE user_id=u;
 UPDATE public.vr_offers SET stock=stock+1 WHERE id=c.offer_id;
 INSERT INTO public.vr_events(user_id,shop_id,actor_id,kind,delta,request_id,claim_id) VALUES(u,c.shop_id,u,'release',c.cost,gen_random_uuid(),c.id);
END $$;
CREATE FUNCTION public.vr_collect(p_shop uuid,p_code text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.vr_claims%ROWTYPE;
BEGIN
 PERFORM public.vr_require_user(); PERFORM public.vr_require_staff(p_shop); PERFORM public.vr_lock();
 SELECT * INTO c FROM public.vr_claims WHERE code=upper(btrim(p_code)) AND shop_id=p_shop;
 IF NOT FOUND THEN RAISE EXCEPTION 'Reward code not found for this shop.'; END IF;
 IF c.state='fulfilled' THEN RETURN jsonb_build_object('title',c.title,'duplicate',true); END IF;
 IF c.state<>'pending' OR c.expires_at<=now() THEN RAISE EXCEPTION 'This reward code is no longer valid. Ask the customer to refresh.'; END IF;
 UPDATE public.vr_claims SET state='fulfilled',fulfilled_at=now(),fulfilled_by=auth.uid() WHERE id=c.id;
 RETURN jsonb_build_object('title',c.title,'duplicate',false);
END $$;
CREATE FUNCTION public.vr_shop(p_shop uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.vr_require_user(); PERFORM public.vr_require_staff(p_shop); PERFORM public.vr_lock(); PERFORM public.vr_release_expired();
 RETURN jsonb_build_object('offers',COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at DESC) FROM public.vr_offers o WHERE shop_id=p_shop),'[]'::jsonb),
 'purchases',COALESCE((SELECT jsonb_agg(to_jsonb(e)) FROM (SELECT x.id,x.reference,x.created_at,EXISTS(SELECT 1 FROM public.vr_events rev WHERE rev.reverses=x.id) AS reversed FROM public.vr_events x WHERE x.shop_id=p_shop AND x.kind='purchase' ORDER BY x.created_at DESC LIMIT 30) e),'[]'::jsonb));
END $$;
CREATE FUNCTION public.vr_save_offer(p_shop uuid,p_title text,p_conditions text,p_cost integer,p_stock integer,p_request uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE oid uuid; existing public.vr_offers%ROWTYPE;
BEGIN
 PERFORM public.vr_require_user(); PERFORM public.vr_require_staff(p_shop); PERFORM public.vr_lock();
 SELECT * INTO existing FROM public.vr_offers WHERE created_by=auth.uid() AND request_id=p_request;
 IF FOUND THEN
  IF existing.shop_id<>p_shop OR existing.title<>btrim(p_title) OR existing.conditions<>btrim(p_conditions) OR existing.cost<>p_cost THEN RAISE EXCEPTION 'Request already used for another offer.'; END IF;
  RETURN existing.id;
 END IF;
 INSERT INTO public.vr_offers(shop_id,title,conditions,cost,stock,created_by,request_id) VALUES(p_shop,btrim(p_title),btrim(p_conditions),p_cost,p_stock,auth.uid(),p_request) RETURNING id INTO oid;
 RETURN oid;
END $$;
CREATE FUNCTION public.vr_set_offer_active(p_offer uuid,p_active boolean) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s uuid;
BEGIN
 PERFORM public.vr_require_user(); PERFORM public.vr_lock();
 SELECT shop_id INTO s FROM public.vr_offers WHERE id=p_offer;
 PERFORM public.vr_require_staff(s);
 UPDATE public.vr_offers SET active=p_active WHERE id=p_offer;
END $$;
-- Conservative staging policy: refuse a reversal that would make a spendable balance negative.
-- Resolve already-spent awards through support; final refund policy is a rollout decision.
CREATE FUNCTION public.vr_reverse_purchase(p_event uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.vr_events%ROWTYPE; u uuid:=public.vr_require_user();
BEGIN
 PERFORM public.vr_lock(); PERFORM public.vr_release_expired();
 SELECT * INTO e FROM public.vr_events WHERE id=p_event AND kind='purchase';
 IF NOT FOUND THEN RAISE EXCEPTION 'Purchase not found.'; END IF;
 PERFORM public.vr_require_staff(e.shop_id);
 IF EXISTS(SELECT 1 FROM public.vr_events WHERE reverses=e.id) THEN RETURN; END IF;
 UPDATE public.vr_members SET balance=balance-1 WHERE user_id=e.user_id AND balance>=1;
 IF NOT FOUND THEN RAISE EXCEPTION 'The stamp has already been used. Ask support to resolve this refund.'; END IF;
 INSERT INTO public.vr_events(user_id,shop_id,actor_id,kind,delta,request_id,reverses) VALUES(e.user_id,e.shop_id,u,'refund',-1,gen_random_uuid(),e.id);
END $$;
-- No anonymous RPC access; internal helpers are never callable by browser roles.
REVOKE ALL ON FUNCTION public.vr_require_user(),public.vr_require_staff(uuid),public.vr_lock(),public.vr_release_expired(),public.vr_dashboard(),public.vr_award(uuid,text,text,uuid),public.vr_claim(uuid,uuid),public.vr_cancel(uuid),public.vr_collect(uuid,text),public.vr_shop(uuid),public.vr_save_offer(uuid,text,text,integer,integer,uuid),public.vr_set_offer_active(uuid,boolean),public.vr_reverse_purchase(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.vr_dashboard(),public.vr_award(uuid,text,text,uuid),public.vr_claim(uuid,uuid),public.vr_cancel(uuid),public.vr_collect(uuid,text),public.vr_shop(uuid),public.vr_save_offer(uuid,text,text,integer,integer,uuid),public.vr_set_offer_active(uuid,boolean),public.vr_reverse_purchase(uuid) TO authenticated;
CREATE FUNCTION public.vr_inspect_claim(p_shop uuid,p_code text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.vr_claims%ROWTYPE;
BEGIN
 PERFORM public.vr_require_user(); PERFORM public.vr_require_staff(p_shop);
 SELECT * INTO c FROM public.vr_claims WHERE shop_id=p_shop AND code=upper(btrim(p_code)) AND state='pending' AND expires_at>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'No pending reward found for this code and shop.'; END IF;
 RETURN jsonb_build_object('title',c.title,'conditions',c.conditions,'cost',c.cost,'expires_at',c.expires_at);
END $$;
REVOKE ALL ON FUNCTION public.vr_inspect_claim(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.vr_inspect_claim(uuid,text) TO authenticated;
COMMIT;
