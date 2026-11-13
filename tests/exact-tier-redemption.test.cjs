const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {PGlite}=require('@electric-sql/pglite');

test('tier collection spends its recorded cost once and leaves the surplus',async()=>{
  const db=new PGlite();
  try{
    await db.exec(`
      CREATE TABLE customers(id text PRIMARY KEY,name text,points int,total_points_redeemed int,total_redemptions int);
      CREATE TABLE shops(id uuid PRIMARY KEY,name text,login_code text,active bool);
      CREATE TABLE rewards(id uuid PRIMARY KEY,reward_title text,redemptions_total int);
      CREATE TABLE redemptions(id uuid PRIMARY KEY,redemption_code text,merchant_id uuid,
        customer_id text,reward_id uuid,reward_type text,status text,expires_at timestamptz,
        points_spent int,stamps_spent int,validated_at timestamptz,points_at_redemption int);
      CREATE TABLE transactions(customer_id text,shop_id uuid,shop_name text,type text,amount numeric,points int);
      CREATE FUNCTION update_balance() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN
        UPDATE customers SET points=points+NEW.points WHERE id=NEW.customer_id; RETURN NEW;
      END$$;
      CREATE TRIGGER balance AFTER INSERT ON transactions FOR EACH ROW EXECUTE FUNCTION update_balance();
      INSERT INTO customers VALUES ('member','Test member',120,0,0);
      INSERT INTO shops VALUES ('00000000-0000-0000-0000-000000000001','Test shop','PIN',true);
      INSERT INTO rewards VALUES ('00000000-0000-0000-0000-000000000002','Test consultation',0);
      INSERT INTO redemptions SELECT gen_random_uuid(), code, '00000000-0000-0000-0000-000000000001',
        'member','00000000-0000-0000-0000-000000000002','tier','pending',now()+interval '1 hour',
        cost,0,NULL,NULL FROM (VALUES ('FIRST',100),('SECOND',100),('NEGATIVE',-1),('NULLCOST',NULL)) AS claims(code,cost);
    `);
    await db.exec(fs.readFileSync('supabase/migrations/202611130001_exact_tier_redemption.sql','utf8'));
    const result=(await db.query("SELECT validate_redemption('FIRST','PIN') AS result")).rows[0].result;
    assert.equal(result.points_spent,100);
    assert.equal(result.points_remaining,20);
    assert.deepEqual((await db.query('SELECT points,total_points_redeemed,total_redemptions FROM customers')).rows,[{points:20,total_points_redeemed:100,total_redemptions:1}]);
    assert.deepEqual((await db.query('SELECT points FROM transactions')).rows,[{points:-100}]);
    assert.equal((await db.query("SELECT points_at_redemption FROM redemptions WHERE redemption_code='FIRST'")).rows[0].points_at_redemption,100);
    await assert.rejects(db.query("SELECT validate_redemption('FIRST','PIN')"),/already validated/);
    await assert.rejects(db.query("SELECT validate_redemption('SECOND','PIN')"),/no longer has enough/);
    await assert.rejects(db.query("SELECT validate_redemption('NEGATIVE','PIN')"),/Invalid tier stamp cost/);
    await assert.rejects(db.query("SELECT validate_redemption('NULLCOST','PIN')"),/Invalid tier stamp cost/);
    assert.equal((await db.query('SELECT count(*)::int AS n FROM transactions')).rows[0].n,1);
  }finally{await db.close();}
});
