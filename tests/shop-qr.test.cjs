const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const html=fs.readFileSync('app.html','utf8');
const start=html.indexOf('// Shop QR intent');
const source=html.slice(start,html.indexOf('</script>',start));
function setup({params="?checkin=shop",customer=true,shop={id:'shop',name:'Local',active:true,lat:-37,lng:145},error=null,recent=[],dev=true,gps='near',success=true}={}) {
 const calls={awards:[],screens:[],toasts:[],location:0,joins:0};
 const location={href:'https://villagerewards.com.au/app.html'+params,search:params};
 const elements={};
 const ctx=vm.createContext({document:{getElementById:id=>elements[id]||(elements[id]={})},URL,URLSearchParams,location,history:{replaceState:(_,__,url)=>{calls.url=String(url)}},currentCustomer:customer?{id:'me'}:null,DEV_MODE:dev,CHECKIN_RADIUS_M:150,console,
 setLoading:()=>{},show:s=>calls.screens.push(s),showToast:s=>calls.toasts.push(s),goCustomer:()=>calls.joins++,haversineDistance:()=>gps==='far'?151:20,
 navigator:{geolocation:{getCurrentPosition:(ok,fail)=>{calls.location++;gps==='denied'?fail():ok({coords:{latitude:-37,longitude:145}})}}},
 doCheckin:async(...args)=>{calls.awards.push(args);return success},
 sb:{from(table){const q={};for(const k of ['select','eq','gte','limit'])q[k]=()=>q;q.maybeSingle=()=>q;q.then=(resolve,reject)=>Promise.resolve(table==='shops'?{data:shop,error}:{data:recent}).then(resolve,reject);return q}}
 });
 vm.runInContext(source,ctx);return {ctx,calls};
}
test('returning customer awards once in DEV_MODE and consumes QR URL',async()=>{
 const {ctx,calls}=setup();assert.equal(calls.joins,1);await ctx.resumeShopCheckin();await ctx.resumeShopCheckin();assert.equal(calls.awards.length,1);assert.equal(calls.awards[0][0],'shop');assert.equal(calls.location,0);assert.ok(!calls.url.includes('checkin'));
});
test('registration preserves intent until a customer is available',async()=>{
 const {ctx,calls}=setup({customer:false});await ctx.resumeShopCheckin();assert.equal(calls.awards.length,0);assert.equal(ctx.pendingCheckinShop,'shop');ctx.currentCustomer={id:'new'};await ctx.resumeShopCheckin();assert.equal(calls.awards.length,1);
});
test('unknown and malformed shops fall back without earning',async()=>{
 for(const error of [null,{code:'22P02'}]){const {ctx,calls}=setup({shop:null,error});await ctx.resumeShopCheckin();assert.equal(calls.awards.length,0);assert.deepEqual(calls.screens,['s-checkin']);}
});
test('cooldown, GPS denial, out of range and missing coordinates do not earn',async()=>{
 for(const options of [{recent:[{id:'tx'}]},{dev:false,gps:'denied'},{dev:false,gps:'far'},{dev:false,shop:{id:'shop',active:true,lat:null,lng:null}}]){const {ctx,calls}=setup(options);await ctx.resumeShopCheckin();assert.equal(calls.awards.length,0);assert.ok(calls.toasts.length);}
});
test('GPS within radius earns and failed insertion retains retry URL',async()=>{
 const {ctx,calls}=setup({dev:false});await ctx.resumeShopCheckin();assert.equal(calls.location,1);assert.equal(calls.awards[0][2],20);
 const failed=setup({success:false});await failed.ctx.resumeShopCheckin();assert.equal(failed.ctx.pendingCheckinShop,'shop');
});
test('repeated simultaneous processing does not duplicate awards',async()=>{
 const {ctx,calls}=setup();await Promise.all([ctx.resumeShopCheckin(),ctx.resumeShopCheckin()]);assert.equal(calls.awards.length,1);
});
test('acquisition links and all customer entry paths resume QR intent',()=>{
 const village=fs.readFileSync('montalbert/index.html','utf8');
 const links=village.match(/<a\b[^>]*>[^<]*(?:Join Village Rewards|Make local more rewarding)[^<]*<\/a>/g);
 assert.equal(links.length,4);links.forEach(a=>assert.ok(a.includes('app.html?join=1')));
 assert.equal((html.match(/await resumeShopIntent\(\);/g)||[]).length,3);
});

test('shop earn bypasses GPS, consumes URL, shows shopper success and rejects unknown shops',async()=>{
 const {ctx,calls}=setup({params:'?shop=shop',dev:false,gps:'denied'});await ctx.resumeShopIntent();
 assert.equal(calls.awards.length,1);assert.equal(calls.location,0);assert.ok(calls.screens.includes('s-shop-success'));assert.ok(!calls.url.includes('shop='));
 const missing=setup({params:'?shop=unknown',shop:null});await missing.ctx.resumeShopIntent();assert.equal(missing.calls.awards.length,0);assert.ok(missing.calls.toasts.some(t=>t.includes('not found')));
});
