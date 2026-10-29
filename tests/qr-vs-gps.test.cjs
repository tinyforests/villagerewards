const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const vm=require('node:vm');const {PGlite}=require('@electric-sql/pglite');
test('only QR and qualifying purchase rows earn passport/shop-card progress; GPS does not',async()=>{
 const db=new PGlite();try{
 await db.exec(`CREATE TABLE shops(id text,passport_active boolean);CREATE TABLE passport_campaigns(id text,is_active boolean,start_date date,end_date date,min_spend numeric);CREATE TABLE pilot_config(key text,value text);
 CREATE TABLE rewards(id uuid,merchant_id text,stamp_min_amount numeric);
 CREATE TABLE redemptions(customer_id text,reward_id uuid,status text,validated_at timestamptz);
 CREATE TABLE transactions(customer_id text,shop_id text,type text,amount numeric,points int,note text,created_at timestamptz default now());
 CREATE TABLE passport_stamps(customer_id text,shop_id text,campaign_id text,visit_date date,spend_amount numeric,UNIQUE(customer_id,shop_id,campaign_id,visit_date));
 INSERT INTO shops VALUES('shop',true);INSERT INTO rewards VALUES('11111111-1111-1111-1111-111111111111','shop',10);
 INSERT INTO passport_campaigns VALUES('campaign',true,current_date-1,current_date+1,10);`);
 await db.exec(fs.readFileSync('supabase/migrations/202610290004_distinguish_qr_and_gps.sql','utf8'));
 await db.exec(`INSERT INTO transactions VALUES
 ('gps','shop','checkin',NULL,0,NULL,now()),
 ('qr','shop','purchase',0,1,'qr_scan',now()),
 ('small','shop','purchase',0,1,NULL,now()),
 ('buyer','shop','purchase',10,1,NULL,now());`);
 assert.deepEqual((await db.query('SELECT customer_id FROM passport_stamps ORDER BY customer_id')).rows.map(r=>r.customer_id),['buyer','qr']);
 for(const [cid,n] of [['gps',0],['qr',1],['small',0],['buyer',1]])assert.equal((await db.query("SELECT stamp_progress($1,'11111111-1111-1111-1111-111111111111') AS n",[cid])).rows[0].n,n);
 await db.exec("INSERT INTO transactions(customer_id,shop_id,type,amount,points,note) VALUES('qr','shop','purchase',0,1,'qr_scan')");assert.equal((await db.query("SELECT count(*)::int AS n FROM passport_stamps WHERE customer_id='qr'")).rows[0].n,1);
 }finally{await db.close();}
});
test('transaction writer distinguishes QR earning from GPS recording',async()=>{
 const html=fs.readFileSync('app.html','utf8');const start=html.indexOf('async function doCheckin(');const source=html.slice(start,html.indexOf('/* ═══ BADGES',start));
 const writes=[];const ctx=vm.createContext({localStorage:{getItem:()=> 'me'},setLoading:()=>{},showToast:()=>{},setTimeout:()=>{},console,renderCustomerDashboard:()=>{},sb:{from(table){return table==='transactions'?{insert:async row=>{writes.push(row);return {}}}:{select(){return this},eq(){return this},single:async()=>({data:null})}}}});vm.runInContext(source,ctx);
 await ctx.doCheckin('shop','Local',null,null,null,true,true);await ctx.doCheckin('shop','Local',5,1,2,false,false);
 assert.equal(writes[0].type,'purchase');assert.equal(writes[0].note,'qr_scan');assert.equal(writes[0].points,1);assert.equal(writes[0].amount,0);
 assert.equal(writes[1].type,'checkin');assert.equal(writes[1].points,0);assert.equal(writes[1].note,null);
});
