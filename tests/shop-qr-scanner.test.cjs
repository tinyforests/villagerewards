const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const s=fs.readFileSync('assets/qr-scanner.js','utf8');
const ctx=vm.createContext({URL});vm.runInContext(s.slice(s.indexOf('function shopQrDestination'),s.indexOf('  function accept')),ctx);
test('scanner permits only Village Rewards shop earn/redeem links',()=>{
 for(const mode of ['shop','redeem'])assert.equal(ctx.shopQrDestination('https://villagerewards.com.au/app.html?'+mode+'=my-shop'),'https://villagerewards.com.au/app.html?'+mode+'=my-shop');
 for(const text of ['javascript:alert(1)','https://example.com/app.html?shop=abc','https://villagerewards.com.au/admin?shop=abc','https://villagerewards.com.au/app.html?shop=','https://villagerewards.com.au/app.html?shop=a&redeem=b','ABC123'])assert.equal(ctx.shopQrDestination(text),null);
});
