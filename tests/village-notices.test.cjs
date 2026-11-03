const {test}=require('node:test');const assert=require('node:assert/strict');const vm=require('node:vm');const fs=require('node:fs');
const html=fs.readFileSync('app.html','utf8');const a=html.indexOf('var villageNoticeQueue');const source=html.slice(a,html.indexOf('/* ═════════',a));
test('notices queue confirmed events, use plain text and dismiss in order',()=>{
 const els={};const el=id=>els[id]||(els[id]={textContent:'',hidden:true,className:''});let timer;
 const ctx=vm.createContext({document:{getElementById:el,addEventListener:()=>{}},setTimeout:fn=>{timer=fn;return 1},clearTimeout:()=>{}});vm.runInContext(source,ctx);
 ctx.showVillageNotice('Six visits! +1 village stamp.','Village balance only.','reward');ctx.showVillageNotice('Card completed! +1 village stamp.','A coffee on us','reward');
 assert.equal(el('notice-title').textContent,'Six visits! +1 village stamp.');assert.equal(ctx.villageNoticeQueue.length,1);assert.equal(el('toast').hidden,false);
 ctx.dismissVillageNotice();assert.equal(el('notice-title').textContent,'Card completed! +1 village stamp.');
 timer();assert.equal(el('toast').hidden,true);
 ctx.showToast('<img src=x onerror=alert(1)>',true);assert.equal(el('notice-title').textContent,'<img src=x onerror=alert(1)>');assert.match(el('toast').className,/error/);
});
