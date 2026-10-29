const assert = require('node:assert/strict');
const format = require('../assets/customer-activity.js');
const now = Date.parse('2026-10-01T10:00:00Z');
const tx = {created_at:'2026-10-01T09:59:00Z',shop_name:'Example café',points:8,type:'checkin'};
assert.equal(format(tx,now).title,'You just checked in at Example café!');
assert.match(format(tx,now).message,/Visit recorded/);
assert.equal(format({...tx,type:'redeem',points:-10,reward_title:'a coffee'},now).message,'Enjoy the cuppa!');
assert.match(format({...tx,type:'redeem',points:-10,reward_title:'a coffee'},now).title,/10 stamps for a coffee/);
assert.equal(format({...tx,type:'redeem',points:-47},now).message,'Enjoy your little treat!');
assert.doesNotMatch(format({...tx,created_at:'2026-09-30T09:59:00Z'},now).title,/just/);
assert.equal(format({...tx,type:'reward',points:0},now).title,'You just claimed your shop reward at Example café.');
assert.match(format({...tx,type:'purchase',points:15},now).title,/earned 1 stamp\b/);
assert.match(format({...tx,type:'purchase',points:1},now).title,/earned 1 stamp\b/);
assert.match(format(null,now).title,/next little win/);
assert.equal(format({...tx,type:'adjustment',points:-4},now).title,'Your stamps have been updated.');
console.log('PASS: check-in, purchase, redemption, coffee copy, stamp reward, old activity, empty profile and adjustments.');

for (const points of [300,250,8,0,null]) {
  assert.match(format({...tx,type:'purchase',points},now).title,/earned 1 stamp\b/);
  assert.doesNotMatch(format({...tx,type:'checkin',points},now).message,/\+1/);
}

assert.equal(format({...tx,type:'purchase',note:'qr_scan',points:1,amount:0},now).title,'Stamp at Example café');
