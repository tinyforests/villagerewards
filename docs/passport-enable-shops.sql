-- Supabase SQL Editor → New snippet
-- Run manually against the intended Village Rewards project.
-- This enables every active shop in this database, so use the selective option
-- instead if the database includes other villages or unconfirmed participants.

-- Turn on passport for all active Mont Albert shops
UPDATE shops
SET passport_active = true
WHERE active = true;

-- Verify
SELECT name, passport_active, active
FROM shops
ORDER BY name;

-- SELECTIVE ALTERNATIVE: replace the UPDATE above with this, do not run both.
-- Use exact names from the verification query (these example names may differ).
-- UPDATE shops
-- SET passport_active = true
-- WHERE active = true AND name IN (
--   'Hamiltons',
--   'Village Bakehouse',
--   'Dumpling 38',
--   'Village Grocer',
--   'Mont Albert Florist',
--   'Gardener & Son'
-- );
