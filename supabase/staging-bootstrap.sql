-- NEW EMPTY STAGING PROJECT ONLY. Run before migrations/202610260001_stamp_pilot.sql.
-- The existing production shops table is deliberately not recreated by that migration.
BEGIN;
CREATE TABLE public.shops (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 name text NOT NULL,
 active boolean NOT NULL DEFAULT true
);
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.shops FROM PUBLIC,anon,authenticated;
COMMIT;
-- Add real, consented pilot shops using the SQL editor. Do not seed invented offers.
-- INSERT INTO public.shops(name) VALUES ('Your confirmed pilot shop');
