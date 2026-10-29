const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const html=fs.readFileSync('app.html','utf8');
const start=html.indexOf('// Shop QR intent');
const source=html.slice(start,html.indexOf('</script>',start));
function setup(stamps=6,error=null) {
 const els={};const calls=[];const cards=[{reward_id:'reward',merchant_id:'shop',shop_name:'Local',reward_title:'Coffee',current_stamps:stamps,stamp_goal:6}];
 const ctx=vm.createContext({URL,URLSearchParams,location:{href:'https://villagerewards.com.au/app.html?redeem=shop',search:'?redeem=shop'},history:{replaceState:()=>{}},console,
 document:{getElementById:id=>els[id]||(els[id]={})},currentCustomer:{id:'me'},goCustomer:()=>{},setLoading:()=>{},esc:s=>s,show:s=>calls.push(s),showToast:s=>calls.push(s),renderCustomerDashboard:async()=>{},
 sb:{from:()=>{const q={};for(const m of ['select','eq'])q[m]=()=>q;q.maybeSingle=async()=>({data:{id:'shop',name:'Local',active:true}});return q},rpc:async(name,args)=>{calls.push([name,args]);return name==='get_stamp_cards'?{data:cards}:{data:error?null:{status:'validated'},error}}}
 });vm.runInContext(source,ctx);return {ctx,calls,els};
}
test('shop redemption shows progress, does not earn, and requires explicit confirmation',async()=>{
 const {ctx,calls,els}=setup();await ctx.resumeShopIntent();assert.match(els['shop-reward-cards'].innerHTML,/Confirm redemption/);assert.match(els['shop-reward-cards'].innerHTML,/6 of 6 stamps at Local/);assert.equal(calls.filter(c=>Array.isArray(c)&&c[0]==='redeem_shop_stamp').length,0);
 await ctx.confirmShopReward(0);assert.ok(calls.includes('s-shop-success'));assert.equal(ctx.pendingRedeemShop,null);
});
test('insufficient progress has no confirmation and cannot call redemption',async()=>{
 const {ctx,calls,els}=setup(2);await ctx.resumeShopIntent();assert.match(els['shop-reward-cards'].innerHTML,/2 of 6/);assert.doesNotMatch(els['shop-reward-cards'].innerHTML,/Confirm redemption/);await ctx.confirmShopReward(0);assert.equal(calls.filter(c=>Array.isArray(c)&&c[0]==='redeem_shop_stamp').length,0);
});
test('server failure retains redemption intent and never reports success',async()=>{
 const {ctx,calls}=setup(6,{message:'Not enough stamps yet'});await ctx.resumeShopIntent();await ctx.confirmShopReward(0);assert.equal(ctx.pendingRedeemShop,'shop');assert.ok(!calls.includes('s-shop-success'));assert.ok(calls.includes('Not enough stamps yet'));
});
