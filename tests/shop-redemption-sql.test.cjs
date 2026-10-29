const {test}=require('node:test');
const assert=require('node:assert/strict');
const {PGlite}=require('@electric-sql/pglite');
const fs=require('node:fs');
test('shopper redemption wrapper validates type, serializes customer, and rolls back failed validation',async()=>{
 const db=new PGlite();
 try {
 await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;
 CREATE TABLE customers(id text PRIMARY KEY);
 CREATE TABLE shops(id uuid PRIMARY KEY,login_code text,active boolean);
 CREATE TABLE rewards(id uuid PRIMARY KEY,merchant_id uuid,reward_type text,is_active boolean,stamp_min_amount numeric);
 CREATE TABLE transactions(customer_id text,shop_id uuid,type text,amount numeric,created_at timestamptz);
 CREATE TABLE redemptions(customer_id text,reward_id uuid,status text,validated_at timestamptz);
 CREATE TABLE test_pending(code text);
 INSERT INTO customers VALUES ('me');
 INSERT INTO shops VALUES ('11111111-1111-1111-1111-111111111111','PRIVATE',true);
 INSERT INTO rewards VALUES ('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111','stamp',true,10);
 CREATE FUNCTION redeem_reward(text,uuid) RETURNS json LANGUAGE plpgsql AS $$BEGIN INSERT INTO test_pending VALUES ('TEST'); RETURN '{"redemption_code":"TEST"}'::json; END;$$;
 CREATE FUNCTION validate_redemption(text,text) RETURNS json LANGUAGE plpgsql AS $$BEGIN IF $2 <> 'PRIVATE' THEN RAISE EXCEPTION 'invalid';END IF; RETURN '{"status":"validated"}'::json; END;$$;`);
 await db.exec(fs.readFileSync('supabase/migrations/202610290002_shopper_stamp_redemption.sql','utf8'));
 await db.exec(`INSERT INTO transactions VALUES
 ('me','11111111-1111-1111-1111-111111111111','checkin',NULL,now()),
 ('me','11111111-1111-1111-1111-111111111111','purchase',20,now()),
 ('me','11111111-1111-1111-1111-111111111111','purchase',2,now()),
 ('other','11111111-1111-1111-1111-111111111111','checkin',NULL,now());`);
 assert.equal((await db.query("SELECT stamp_progress('me','22222222-2222-2222-2222-222222222222') AS n")).rows[0].n,2);
 await db.exec("INSERT INTO redemptions VALUES ('me','22222222-2222-2222-2222-222222222222','validated',now()+interval '1 second')");
 assert.equal((await db.query("SELECT stamp_progress('me','22222222-2222-2222-2222-222222222222') AS n")).rows[0].n,0);
 const call=()=>db.query("SELECT redeem_shop_stamp('me','22222222-2222-2222-2222-222222222222') AS result");
 assert.equal((await call()).rows[0].result.status,'validated');
 await db.exec("UPDATE rewards SET reward_type='tier'");await assert.rejects(call(),/Active stamp reward not found/);
 await db.exec("UPDATE rewards SET reward_type='stamp';DELETE FROM test_pending;CREATE OR REPLACE FUNCTION validate_redemption(text,text) RETURNS json LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'Not enough stamps yet';END;$$;");
 await assert.rejects(call(),/Not enough stamps/);assert.equal((await db.query('SELECT count(*)::int AS n FROM test_pending')).rows[0].n,0);
 } finally {await db.close();}
});
