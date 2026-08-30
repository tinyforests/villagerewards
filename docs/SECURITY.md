# Village Rewards - Security Documentation

**Last Updated:** May 2026  
**Current Security Status:** Hardcoded auth removed, pending Supabase Auth implementation

---

## Current Security Posture

### ✅ Fixed Security Issues (May 2026)

**Commit `c89dca0`** - "Security: Remove hardcoded credentials, enable GPS enforcement"

1. **Admin password removed**
   - Previously: `ADMIN_PW = 'GSADMIN2026'` hardcoded in `village-rewards-admin.html` line 431
   - Now: Variable removed, login function disabled with clear message
   - Impact: Admin dashboard inaccessible (intentionally)

2. **Trader PIN removed**
   - Previously: `TRADER_PIN = 'MONT'` hardcoded in `app.html` line 622
   - Now: Variable removed, login function disabled with clear message
   - Impact: Trader flow inaccessible (intentionally)

3. **GPS enforcement enabled**
   - Previously: `DEV_MODE = true` bypassed 150m radius check globally
   - Now: `DEV_MODE = false` enforces GPS proximity for check-ins
   - Impact: Check-ins now require actual proximity to shop location

### 🔴 Critical Outstanding Issues

1. **No authentication system**
   - Admin dashboard: Completely disabled
   - Trader login: Completely disabled
   - Customer registration: Open (no password required)

2. **RLS policies undocumented**
   - Supabase anon key exposed in client-side JS (intentional for public key)
   - Security depends entirely on Row-Level Security policies
   - **Problem:** RLS policies configured in Supabase but not documented in repo

3. **Client-side business logic**
   - Point calculations happen in JavaScript
   - Redemption validation happens in JavaScript
   - No server-side enforcement of business rules

4. **No rate limiting**
   - No protection against spam registrations
   - No protection against point farming
   - No protection against concurrent redemptions

---

## Authentication Roadmap

### Phase 1: Supabase Auth Implementation (Required Before Re-launch)

#### Admin Authentication

**Recommended approach:** Email magic link

```javascript
// Replace client-side password check with:
const { data, error } = await supabase.auth.signInWithOtp({
  email: adminEmail,
  options: {
    emailRedirectTo: 'https://villagerewards.com.au/village-rewards-admin.html'
  }
});
```

**Alternative:** OAuth (Google/GitHub SSO for G&S team members)

**RLS Policy:**
```sql
-- Create admin_users table
CREATE TABLE admin_users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email VARCHAR(200) UNIQUE NOT NULL,
  role VARCHAR(20) DEFAULT 'admin',
  created_at TIMESTAMP DEFAULT NOW()
);

-- Only allow authenticated admins
CREATE POLICY admin_dashboard_access ON admin_users
  FOR SELECT
  USING (auth.uid() = id);
```

#### Trader Authentication

**Recommended approach:** Email + password with shop assignment

```javascript
// Trader sign-up
const { data, error } = await supabase.auth.signUp({
  email: traderEmail,
  password: traderPassword,
  options: {
    data: {
      shop_id: selectedShopId,
      role: 'trader'
    }
  }
});

// Trader login
const { data, error } = await supabase.auth.signInWithPassword({
  email: traderEmail,
  password: traderPassword
});
```

**Schema extension needed:**
```sql
-- Extend shops table
ALTER TABLE shops ADD COLUMN owner_user_id UUID REFERENCES auth.users(id);

-- Create merchant_users junction table for multi-user shops
CREATE TABLE merchant_users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  shop_id UUID REFERENCES shops(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id),
  role VARCHAR(20) DEFAULT 'staff',  -- 'owner', 'manager', 'staff'
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW()
);
```

**RLS Policies:**
```sql
-- Traders can only issue points for their own shop
CREATE POLICY traders_own_shop_only ON transactions
  FOR INSERT
  WITH CHECK (
    shop_id IN (
      SELECT shop_id FROM merchant_users 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

-- Traders can only read their own shop stats
CREATE POLICY traders_own_stats ON shop_stats
  FOR SELECT
  USING (
    shop_id IN (
      SELECT shop_id FROM merchant_users 
      WHERE user_id = auth.uid()
    )
  );
```

#### Current Pilot: Trader PIN via `pilot_config`

**Status:** In use now (interim, until the Supabase Auth flow above ships).

The trader PIN is **not** hardcoded in `app.html`. At startup `loadPilotConfig()`
reads it from the Supabase `pilot_config` table (`key = 'trader_pilot_code'`) and
compares it — uppercased — against what the trader types. This keeps the secret
out of the public GitHub Pages source.

**Read the current PIN** (Supabase → SQL Editor, or any anon client — the row is
anon-readable by design):
```sql
SELECT value FROM pilot_config WHERE key = 'trader_pilot_code';
```

**Reset / rotate the PIN** (Supabase → SQL Editor only — anon cannot write).
Idempotent; also creates the table + read policy if they don't exist yet:
```sql
CREATE TABLE IF NOT EXISTS pilot_config (
  key   varchar(100) PRIMARY KEY,
  value text NOT NULL
);
ALTER TABLE pilot_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pilot_config_anon_read ON pilot_config;
CREATE POLICY pilot_config_anon_read ON pilot_config FOR SELECT USING (true);

-- Change 'MONT2026' to the new PIN
INSERT INTO pilot_config (key, value) VALUES ('trader_pilot_code', 'MONT2026')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

SELECT * FROM pilot_config WHERE key = 'trader_pilot_code';
```

**Gotchas:**
- **Store the value UPPERCASE.** `traderLogin()` uppercases input before comparing,
  so a lowercase stored value can never match.
- The PIN is a **single shared pilot secret** — anyone with anon read access can see
  it. Acceptable for a trusted trader pilot; it is replaced by per-user Supabase Auth
  (the `merchant_users` model above) before wider launch.
- Empty result from the read query = the row doesn't exist, so trader login shows
  "System not ready"; run the reset block to create it.

#### Customer Authentication

**Current:** Email-only registration (no password)

**Recommendation:** Keep passwordless for low friction

```javascript
// Customer registration (current - keep this)
INSERT INTO customers (id, name, email) VALUES (?, ?, ?);

// Future: Add magic link for customer login (optional)
const { data, error } = await supabase.auth.signInWithOtp({
  email: customerEmail
});
```

---

## Row-Level Security (RLS) Policies

**⚠️ Critical:** These policies are configured in Supabase but **not documented or tested in this repo.**

### Required RLS Policies

#### `customers` table

```sql
-- Customers can read only their own data
CREATE POLICY customers_read_own ON customers
  FOR SELECT
  USING (id = current_customer_id());  -- Need to define this function

-- Public can register (INSERT)
CREATE POLICY customers_public_register ON customers
  FOR INSERT
  WITH CHECK (true);

-- Customers cannot update their own points directly
CREATE POLICY customers_no_direct_point_update ON customers
  FOR UPDATE
  USING (false);  -- Points only updated via triggers

-- Admins can read all customers
CREATE POLICY admins_read_all_customers ON customers
  FOR SELECT
  USING (is_admin());  -- Need to define this function
```

#### `shops` table

```sql
-- Public can read active shops
CREATE POLICY public_read_active_shops ON shops
  FOR SELECT
  USING (active = true);

-- Only admins can modify shops
CREATE POLICY admins_modify_shops ON shops
  FOR ALL
  USING (is_admin());
```

#### `transactions` table

```sql
-- Customers can read their own transactions
CREATE POLICY customers_read_own_transactions ON transactions
  FOR SELECT
  USING (customer_id = current_customer_id());

-- Traders can insert transactions for their shop
CREATE POLICY traders_insert_for_own_shop ON transactions
  FOR INSERT
  WITH CHECK (
    shop_id IN (
      SELECT shop_id FROM merchant_users 
      WHERE user_id = auth.uid()
    )
  );

-- Admins can read all transactions
CREATE POLICY admins_read_all_transactions ON transactions
  FOR SELECT
  USING (is_admin());
```

### Helper Functions Needed

```sql
-- Get current customer ID from session
CREATE OR REPLACE FUNCTION current_customer_id()
RETURNS VARCHAR(6) AS $$
BEGIN
  -- Extract customer_id from auth.jwt() or session
  -- Implementation depends on how customer sessions are managed
  RETURN (current_setting('request.jwt.claims', true)::json->>'customer_id')::VARCHAR(6);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if current user is admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM admin_users 
    WHERE id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## Data Validation & Business Rules

### Server-Side Validation Required

**Current problem:** All validation happens in client-side JavaScript

**Solution:** Move critical validations to Supabase Edge Functions or database triggers

#### Point Issuance Validation

```sql
-- Trigger to validate point transactions
CREATE OR REPLACE FUNCTION validate_point_transaction()
RETURNS TRIGGER AS $$
BEGIN
  -- Validate purchase amount
  IF NEW.type = 'purchase' AND NEW.amount <= 0 THEN
    RAISE EXCEPTION 'Purchase amount must be positive';
  END IF;
  
  -- Validate check-in cooldown (4 hours per shop)
  IF NEW.type = 'checkin' THEN
    IF EXISTS (
      SELECT 1 FROM transactions
      WHERE customer_id = NEW.customer_id
        AND shop_id = NEW.shop_id
        AND type = 'checkin'
        AND created_at > NOW() - INTERVAL '4 hours'
    ) THEN
      RAISE EXCEPTION 'Check-in cooldown not elapsed';
    END IF;
  END IF;
  
  -- Validate redemption has sufficient balance
  IF NEW.type = 'redeem' AND NEW.points > 0 THEN
    DECLARE
      customer_balance INTEGER;
    BEGIN
      SELECT points INTO customer_balance 
      FROM customers 
      WHERE id = NEW.customer_id;
      
      IF customer_balance < NEW.points THEN
        RAISE EXCEPTION 'Insufficient points';
      END IF;
    END;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_transaction_before_insert
BEFORE INSERT ON transactions
FOR EACH ROW
EXECUTE FUNCTION validate_point_transaction();
```

#### Concurrent Redemption Protection

```sql
-- Use database transactions with row locking
BEGIN;
  -- Lock the customer row
  SELECT points FROM customers WHERE id = ? FOR UPDATE;
  
  -- Check balance
  IF points >= required_points THEN
    -- Insert redemption transaction
    INSERT INTO transactions (...) VALUES (...);
    
    -- Update customer balance (via trigger)
    COMMIT;
  ELSE
    ROLLBACK;
    RAISE EXCEPTION 'Insufficient points';
  END IF;
END;
```

---

## Rate Limiting

### Recommended Approach

Use Supabase Edge Functions with rate limiting middleware:

```typescript
// edge-functions/issue-points.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from '@supabase/supabase-js';

const rateLimit = new Map(); // Simple in-memory rate limiter

serve(async (req) => {
  const customerId = req.headers.get('x-customer-id');
  
  // Check rate limit (max 10 transactions per minute)
  const now = Date.now();
  const recentRequests = rateLimit.get(customerId) || [];
  const validRequests = recentRequests.filter(t => now - t < 60000);
  
  if (validRequests.length >= 10) {
    return new Response('Rate limit exceeded', { status: 429 });
  }
  
  validRequests.push(now);
  rateLimit.set(customerId, validRequests);
  
  // Process transaction...
});
```

---

## Security Checklist

### Before Re-enabling Authentication

- [ ] Implement Supabase Auth for admin (magic link or OAuth)
- [ ] Implement Supabase Auth for traders (email + password)
- [ ] Document all RLS policies in this file
- [ ] Test RLS policies (customers can't see other customers' data)
- [ ] Create `admin_users` table
- [ ] Create `merchant_users` table
- [ ] Add `owner_user_id` to `shops` table

### Before Tiered Redemption Launch

- [ ] Move point validation to server-side (triggers or Edge Functions)
- [ ] Implement concurrent redemption protection (row locking)
- [ ] Add rate limiting for point issuance
- [ ] Add rate limiting for redemptions
- [ ] Test check-in cooldown enforcement
- [ ] Implement fraud detection (unusual point patterns)

### Data Protection

- [ ] Export and version-control RLS policies
- [ ] Set up regular Supabase backups
- [ ] Document data retention policy
- [ ] Add customer data export feature (GDPR compliance)
- [ ] Add customer data deletion feature (right to be forgotten)
- [ ] Implement audit logging for admin actions

### Monitoring & Alerts

- [ ] Set up Supabase monitoring dashboard
- [ ] Alert on failed RLS policy checks
- [ ] Alert on unusual point issuance patterns
- [ ] Alert on concurrent redemption attempts
- [ ] Monitor API rate limits

---

## Known Security Gaps

1. **Supabase anon key is public** - this is intentional, but means all security depends on RLS
2. **No server-side validation** - business logic is client-side only
3. **No audit trail** - no logging of who did what when
4. **No fraud detection** - no alerts for suspicious patterns
5. **No encryption at rest** - customer data not encrypted (Supabase default)
6. **No 2FA** - admin and trader accounts have no two-factor option
7. **No IP whitelisting** - admin dashboard accessible from anywhere
8. **No CORS restrictions** - API calls possible from any origin

---

## Incident Response Plan

**If credentials are compromised:**

1. Rotate Supabase anon key immediately
2. Invalidate all active sessions
3. Force password reset for all traders/admins
4. Audit transaction log for suspicious activity
5. Notify affected customers if data exposed

**If database is compromised:**

1. Restore from most recent backup
2. Audit all transactions since backup
3. Contact Supabase support
4. Notify customers per GDPR requirements

**Contact:** Tyson at Gardener & Son (primary security contact)

---

## Future Security Enhancements

- Add two-factor authentication for admin/traders
- Implement anomaly detection for point farming
- Add geofencing validation for check-ins (verify GPS coordinates server-side)
- Implement session timeout for traders
- Add IP whitelisting for admin dashboard
- Set up automated security scans (Dependabot, etc.)
- Add penetration testing before multi-village expansion
