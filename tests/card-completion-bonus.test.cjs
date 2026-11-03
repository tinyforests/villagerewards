const {test}=require('node:test');const assert=require('node:assert/strict');const {PGlite}=require('@electric-sql/pglite');const fs=require('node:fs');const {randomUUID}=require('node:crypto');
test('validated stamp-card redemption awards one village-only stamp exactly once; tier and pending do not',async()=>{
 const db=new PGlite();try{
 await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;
 CREATE TABLE customers(id text PRIMARY KEY,points int default 0);
 CREATE TABLE shops(id uuid PRIMARY KEY,login_code text,active boolean);
 CREATE TABLE rewards(id uuid PRIMARY KEY,merchant_id uuid,reward_type text,is_active boolean);
 CREATE TABLE redemptions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),customer_id text,reward_id uuid,redemption_code text,reward_type text,status text);
 CREATE TABLE transactions(customer_id text,shop_id uuid,shop_name text,type text,amount numeric,points int,note text,created_at timestamptz);
 CREATE FUNCTION balance_update() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN UPDATE customers SET points=points+NEW.points WHERE id=NEW.customer_id;RETURN NEW;END;$$;
 CREATE TRIGGER balance_update AFTER INSERT ON transactions FOR EACH ROW EXECUTE FUNCTION balance_update();
 CREATE FUNCTION redeem_reward(text,uuid) RETURNS json LANGUAGE plpgsql AS $$DECLARE c text:=gen_random_uuid()::text;BEGIN INSERT INTO redemptions(customer_id,reward_id,redemption_code,reward_type,status) VALUES($1,$2,c,'stamp','pending');RETURN json_build_object('redemption_code',c);END;$$;
 CREATE FUNCTION validate_redemption(text,text) RETURNS json LANGUAGE plpgsql AS $$BEGIN UPDATE redemptions SET status='validated' WHERE redemption_code=$1;RETURN '{"status":"validated"}'::json;END;$$;
 INSERT INTO customers VALUES('me',12);`);
 await db.exec(fs.readFileSync('supabase/migrations/202611030002_card_completion_bonus.sql','utf8'));
 const id=randomUUID();await db.query("INSERT INTO redemptions(id,customer_id,reward_type,status) VALUES($1,'me','stamp','pending')",[id]);
 assert.equal((await db.query("SELECT points FROM customers WHERE id='me'")).rows[0].points,12);
 await db.query("UPDATE redemptions SET status='validated' WHERE id=$1",[id]);
 await db.query("UPDATE redemptions SET status='validated' WHERE id=$1",[id]);
 await db.query("UPDATE redemptions SET status='pending' WHERE id=$1",[id]);await db.query("UPDATE redemptions SET status='validated' WHERE id=$1",[id]);
 assert.equal((await db.query("SELECT points FROM customers WHERE id='me'")).rows[0].points,13);
 const bonus=(await db.query('SELECT * FROM transactions')).rows;assert.equal(bonus.length,1);assert.equal(bonus[0].type,'bonus');assert.equal(bonus[0].shop_id,null);assert.equal(bonus[0].note,'shop_card_completion_bonus');
 const tier=randomUUID();await db.query("INSERT INTO redemptions(id,customer_id,reward_type,status) VALUES($1,'me','tier','pending')",[tier]);await db.query("UPDATE redemptions SET status='validated' WHERE id=$1",[tier]);assert.equal((await db.query('SELECT count(*)::int AS n FROM transactions')).rows[0].n,1);
 const shop=randomUUID(),reward=randomUUID();await db.query("INSERT INTO shops VALUES($1,'PRIVATE',true)",[shop]);await db.query("INSERT INTO rewards VALUES($1,$2,'stamp',true)",[reward,shop]);
 const response=(await db.query("SELECT redeem_shop_stamp('me',$1) AS result",[reward])).rows[0].result;assert.equal(response.status,'validated');assert.equal(response.completion_bonus_points,1);
 assert.equal((await db.query("SELECT points FROM customers WHERE id='me'")).rows[0].points,14);
 }finally{await db.close();}
});
