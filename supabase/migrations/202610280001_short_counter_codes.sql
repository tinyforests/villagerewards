-- Short counter codes. Retain old codes so existing QR images still work.
BEGIN;
ALTER TABLE public.vr_members ADD COLUMN legacy_code text UNIQUE;
ALTER TABLE public.vr_claims ADD COLUMN legacy_code text UNIQUE;
CREATE FUNCTION public.vr_short_code() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE candidate text; alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; bytes bytea; i integer;
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(826401);
 LOOP
  bytes:=pg_catalog.uuid_send(gen_random_uuid());
  candidate:=CASE WHEN TG_TABLE_NAME='vr_members' THEN 'C' ELSE 'R' END;
  FOREACH i IN ARRAY ARRAY[0,1,2,3,4,5,9,10] LOOP
   candidate:=candidate||substr(alphabet,1+(get_byte(bytes,i)%length(alphabet)),1);
  END LOOP;
  EXIT WHEN NOT EXISTS(SELECT 1 FROM public.vr_members WHERE code=candidate) AND NOT EXISTS(SELECT 1 FROM public.vr_claims WHERE code=candidate);
 END LOOP;
 NEW.code:=candidate;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.vr_short_code() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER vr_member_short_code BEFORE INSERT OR UPDATE OF code ON public.vr_members FOR EACH ROW EXECUTE FUNCTION public.vr_short_code();
CREATE TRIGGER vr_claim_short_code BEFORE INSERT OR UPDATE OF code ON public.vr_claims FOR EACH ROW EXECUTE FUNCTION public.vr_short_code();
UPDATE public.vr_members SET legacy_code=code,code=code;
UPDATE public.vr_claims SET legacy_code=code,code=code;
CREATE OR REPLACE FUNCTION public.vr_award(p_shop uuid,p_code text,p_reference text,p_request uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=public.vr_require_user(); u uuid; previous public.vr_events%ROWTYPE; e public.vr_events%ROWTYPE; ref text:=upper(btrim(p_reference));
BEGIN
 PERFORM public.vr_require_staff(p_shop); PERFORM public.vr_lock();
 IF p_request IS NULL OR ref IS NULL OR length(ref) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Enter a receipt reference (up to 100 characters).'; END IF;
 SELECT user_id INTO u FROM public.vr_members WHERE (code=upper(regexp_replace(p_code,'[[:space:]-]','','g')) OR legacy_code=upper(btrim(p_code)));
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
CREATE OR REPLACE FUNCTION public.vr_collect(p_shop uuid,p_code text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.vr_claims%ROWTYPE;
BEGIN
 PERFORM public.vr_require_user(); PERFORM public.vr_require_staff(p_shop); PERFORM public.vr_lock();
 SELECT * INTO c FROM public.vr_claims WHERE (code=upper(regexp_replace(p_code,'[[:space:]-]','','g')) OR legacy_code=upper(btrim(p_code))) AND shop_id=p_shop;
 IF NOT FOUND THEN RAISE EXCEPTION 'Reward code not found for this shop.'; END IF;
 IF c.state='fulfilled' THEN RETURN jsonb_build_object('title',c.title,'duplicate',true); END IF;
 IF c.state<>'pending' OR c.expires_at<=now() THEN RAISE EXCEPTION 'This reward code is no longer valid. Ask the customer to refresh.'; END IF;
 UPDATE public.vr_claims SET state='fulfilled',fulfilled_at=now(),fulfilled_by=auth.uid() WHERE id=c.id;
 RETURN jsonb_build_object('title',c.title,'duplicate',false);
END $$;
CREATE OR REPLACE FUNCTION public.vr_inspect_claim(p_shop uuid,p_code text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.vr_claims%ROWTYPE;
BEGIN
 PERFORM public.vr_require_user(); PERFORM public.vr_require_staff(p_shop);
 SELECT * INTO c FROM public.vr_claims WHERE shop_id=p_shop AND (code=upper(regexp_replace(p_code,'[[:space:]-]','','g')) OR legacy_code=upper(btrim(p_code))) AND state='pending' AND expires_at>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'No pending reward found for this code and shop.'; END IF;
 RETURN jsonb_build_object('title',c.title,'conditions',c.conditions,'cost',c.cost,'expires_at',c.expires_at);
END $$;
COMMIT;
