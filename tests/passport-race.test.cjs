const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const app = fs.readFileSync('app.html', 'utf8');
const admin = fs.readFileSync('village-rewards-admin.html', 'utf8');
const render = app.slice(app.indexOf('async function renderPassport('), app.indexOf('/* ═════════', app.indexOf('async function renderPassport(')));
async function widget({ visits = 1, total = 4, participants = 2, ahead = 1, rankError = false } = {}) {
  const el = { style: {}, innerHTML: '' };
  const calls = [];
  const sb = { from(table) {
    const q = { table, filters: [] };
    for (const method of ['select', 'eq', 'gt', 'lte', 'gte', 'order', 'limit']) q[method] = (...args) => { q.filters.push([method, ...args]); return q; };
    q.maybeSingle = () => q;
    q.then = (resolve, reject) => {
      calls.push(q);
      let result;
      if (table === 'passport_campaigns') result = { data: { id: 'campaign', name: 'Race', period: 'monthly', required_shops: 1, end_date: '2026-10-31' } };
      else if (table === 'shops') result = { data: Array.from({length: total}, (_, i) => ({id: String(i), name: 'Trader '+i})) };
      else if (table === 'passport_stamps') result = { data: [] };
      else if (q.filters.some(f => f[0] === 'eq' && f[1] === 'customer_id')) result = { data: visits ? { unique_traders_visited: visits } : null };
      else {
        const isAhead = calls.filter(c => c.table === 'passport_progress' && c.filters.some(f => f[0] === 'gt')).length > 1;
        result = rankError ? { error: { message: 'unavailable' }, count: null } : { count: isAhead ? ahead : participants };
      }
      return Promise.resolve(result).then(resolve, reject);
    };
    return q;
  }};
  const ctx = vm.createContext({ sb, document: {getElementById: () => el}, console, esc: s => String(s) });
  vm.runInContext(render, ctx);
  await ctx.renderPassport('me');
  return { html: el.innerHTML, calls };
}
test('race uses all participating shops rather than required_shops=1', async () => {
  const {html,calls} = await widget();
  assert.match(html, /You’ve visited 1 of 4 traders this month/);
  assert.match(html, /max="4" value="1"/);
  assert.match(html, /Visit more traders to move up the leaderboard/);
  assert.match(html, /2nd place/);
  assert.doesNotMatch(html, /draw|more to go/);
  const counts = calls.filter(c => c.filters.some(f => f[0] === 'gt'));
  assert.equal(counts.length, 2);
  counts.forEach(c => { assert.ok(c.filters.some(f => f[0] === 'eq' && f[1] === 'campaign_id' && f[2] === 'campaign')); assert.ok(c.filters.some(f => f[0] === 'select' && f[2].head === true)); });
});
test('completion and empty shop list do not confuse participation with winning', async () => {
  assert.match((await widget({visits:4})).html, /You’ve visited every trader! 🏆/);
  assert.doesNotMatch((await widget({total:0,visits:0})).html, /every trader/);
});
test('position is optional and hidden with fewer than two stamped customers', async () => {
  assert.doesNotMatch((await widget({participants:1})).html, /currently in/);
  const {html} = await widget({rankError:true});
  assert.doesNotMatch(html, /currently in/);
  assert.match(html, /visited 1 of 4/);
});
test('competition ranking handles ties and ordinal suffixes', async () => {
  for (const [ahead, ordinal] of [[0,'1st'],[2,'3rd'],[3,'4th'],[10,'11th'],[11,'12th'],[12,'13th'],[20,'21st'],[21,'22nd']]) {
    assert.ok((await widget({ahead})).html.includes(ordinal+' place'));
  }
});
test('admin sorts descending and highlights joint leaders without marking zero as a leader', () => {
  const body = {innerHTML:''};
  const start = admin.indexOf('function renderPassportTable()');
  const source = admin.slice(start, admin.indexOf('/* ── Overview', start));
  const ctx = vm.createContext({document:{getElementById:()=>body}, passportSortDir:-1, passportRows:[{name:'Low',traders:1},{name:'Leader A',traders:4},{name:'Leader B',traders:4}], esc:s=>s, fmtD:()=>''});
  vm.runInContext(source,ctx);
  ctx.renderPassportTable();
  assert.ok(body.innerHTML.indexOf('Leader A') < body.innerHTML.indexOf('Low'));
  assert.equal((body.innerHTML.match(/Current leader/g)||[]).length,2);
  ctx.togglePassportSort();
  assert.ok(body.innerHTML.indexOf('Low') < body.innerHTML.indexOf('Leader A'));
  ctx.passportRows=[{name:'Empty',traders:0}]; ctx.renderPassportTable();
  assert.doesNotMatch(body.innerHTML,/Current leader/);
});
