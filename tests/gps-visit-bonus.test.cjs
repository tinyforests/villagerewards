const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const {PGlite}=require('@electric-sql/pglite');const {randomUUID}=require('node:crypto');
test('six new GPS visits award exactly one village stamp; retries and cooldown cannot duplicate it',async()=>{
 const db=new PGlite();try {
 await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE TABLE customers(id text PRIMARY KEY,points int default 0);CREATE TABLE shops(id uuid PRIMARY KEY,name text,active boolean);
 CREATE TABLE transactions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),customer_id text,shop_id uuid,shop_name text,type text,amount numeric,points int,note text,customer_lat numeric,customer_lng numeric,distance_m int,created_at timestamptz DEFAULT now());
 CREATE FUNCTION balance_update() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN UPDATE customers SET points=points+NEW.points WHERE id=NEW.customer_id;RETURN NEW;END;$$;
 CREATE TRIGGER balance_update AFTER INSERT ON transactions FOR EACH ROW EXECUTE FUNCTION balance_update();
 INSERT INTO customers VALUES('me',0),('other',0);`);
 await db.exec(fs.readFileSync('supabase/migrations/202611030001_gps_visit_bonus.sql','utf8'));
 const shops=Array.from({length:6},()=>randomUUID());for(const id of shops)await db.query("INSERT INTO shops VALUES($1,'Local',true)",[id]);
 const visit=async(id=shops[0],cid='me')=>(await db.query('SELECT record_gps_visit($1,$2,NULL,NULL,20) AS result',[cid,id])).rows[0].result;
 for(let i=0;i<5;i++){const r=await visit(shops[i]);assert.equal(r.awarded,false);assert.equal(r.visits,i+1);}
 assert.equal((await db.query("SELECT points FROM customers WHERE id='me'")).rows[0].points,0);
 const sixth=await visit(shops[5]);assert.equal(sixth.awarded,true);assert.equal(sixth.visits,0);
 assert.equal((await db.query("SELECT points FROM customers WHERE id='me'")).rows[0].points,1);
 assert.equal((await visit(shops[5])).duplicate,true);
 const bonus=(await db.query("SELECT type,points,note,shop_id FROM transactions WHERE type='bonus'")).rows;assert.equal(bonus.length,1);assert.equal(bonus[0].shop_id,null);assert.equal(bonus[0].points,1);assert.equal(bonus[0].note,'gps_checkin_bonus');
 await db.exec("UPDATE transactions SET created_at=now()-interval '5 hours' WHERE type='checkin'");
 const next=await visit();assert.equal(next.visits,1);assert.equal(next.awarded,false);
 assert.equal((await db.query("SELECT get_gps_visit_progress('other') AS p")).rows[0].p.visits,0);
 await assert.rejects(db.query('SELECT record_gps_visit($1,$2,NULL,NULL,151)',['me',shops[1]]),/150m/);
 await assert.rejects(visit(randomUUID()),/shop not found/);
 await assert.rejects(visit(shops[0],'missing'),/Customer not found/);
 // Old GPS/staff records and QR purchases never increment the new counter.
 await db.query("INSERT INTO transactions(customer_id,shop_id,type,points,note) VALUES('me',$1,'purchase',1,'qr_scan'),('me',$1,'checkin',0,NULL)",[shops[1]]);
 assert.equal((await db.query("SELECT get_gps_visit_progress('me') AS p")).rows[0].p.visits,1);
 }finally{await db.close();}
});
