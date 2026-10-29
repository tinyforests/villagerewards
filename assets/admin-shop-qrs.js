var qrShops = [];
function shopQrUrl(id, mode) {
  var url = new URL('https://villagerewards.com.au/app.html');
  url.searchParams.set(mode, id);
  return url.href;
}
async function loadShopQrs() {
  var list = document.getElementById('shop-qr-list');
  var print = document.getElementById('print-shop-qrs');
  print.disabled = true;
  list.textContent = 'Loading active shops…';
  try {
    if (typeof QRCode === 'undefined') throw new Error('QR library did not load. Please refresh.');
    var res = await sb.from('shops').select('id,name').eq('active',true).order('name');
    if (res.error) throw res.error;
    qrShops = res.data || [];
    list.innerHTML = '';
    if (!qrShops.length) {list.textContent='No active shops.';return;}
    qrShops.forEach(function(shop) {
      var card = document.createElement('article');card.className='shop-qr-card';
      var title = document.createElement('h2');title.textContent=shop.name;card.appendChild(title);
      var pair=document.createElement('div');pair.className='shop-qr-pair';card.appendChild(pair);
      ['shop','redeem'].forEach(function(mode) {
        var panel=document.createElement('div');panel.className='shop-qr-panel';
        var label=document.createElement('h3');label.textContent=mode==='shop'?'Earn 1 stamp':'Redeem a reward';panel.appendChild(label);
        var qr=document.createElement('div');qr.className='shop-qr-image';panel.appendChild(qr);
        var link=document.createElement('a');link.href=shopQrUrl(shop.id,mode);link.textContent=link.href;panel.appendChild(link);
        pair.appendChild(panel);
        new QRCode(qr,{text:link.href,width:180,height:180,colorDark:'#29332f',colorLight:'#ffffff',correctLevel:QRCode.CorrectLevel.M});
      });
      list.appendChild(card);
    });
    print.disabled=false;
  } catch(error) {list.textContent=error.message||'Could not load shop QR codes.';}
}
function printShopQrs() {
  var cards=document.querySelectorAll('.shop-qr-card');
  if(!cards.length)return;
  var popup=window.open('','_blank');
  if(!popup){alert('Allow pop-ups to open the print-ready cards.');return;}
  popup.document.title='Village Rewards · A5 shop counter cards';
  var style=popup.document.createElement('style');
  style.textContent='@page{size:A5 portrait;margin:0}*{box-sizing:border-box}body{margin:0;font:15px Arial,sans-serif;color:#29332f}.counter-card{width:148mm;min-height:210mm;padding:15mm 10mm;break-after:page;text-align:center;display:flex;flex-direction:column;justify-content:center}.counter-card:last-child{break-after:auto}h1{font-size:30px;margin:0 0 8mm}h2{font-size:24px;margin:0 0 10mm}.pair{display:flex;gap:6mm;justify-content:center}.panel{width:58mm}img{width:54mm;height:54mm;background:white;padding:2mm}h3{font-size:17px}p{line-height:1.5}.url{font-size:9px;overflow-wrap:anywhere}.print{margin:20px;padding:12px}@media print{.print{display:none}}';
  popup.document.head.appendChild(style);
  var button=popup.document.createElement('button');button.className='print';button.textContent='Print A5 counter cards';button.onclick=function(){popup.print();};popup.document.body.appendChild(button);
  cards.forEach(function(card){
    var sheet=popup.document.createElement('article');sheet.className='counter-card';
    var brand=popup.document.createElement('h1');brand.textContent='Village Rewards ✦';sheet.appendChild(brand);
    var heading=popup.document.createElement('h2');heading.textContent=card.querySelector('h2').textContent;sheet.appendChild(heading);
    var pair=popup.document.createElement('div');pair.className='pair';sheet.appendChild(pair);
    card.querySelectorAll('.shop-qr-panel').forEach(function(panel){
      var col=popup.document.createElement('div');col.className='panel';
      var label=popup.document.createElement('h3');label.textContent=panel.querySelector('h3').textContent;col.appendChild(label);
      var image=popup.document.createElement('img');var canvas=panel.querySelector('canvas');image.src=canvas?canvas.toDataURL():panel.querySelector('img').src;image.alt=label.textContent;col.appendChild(image);
      var url=popup.document.createElement('p');url.className='url';url.textContent=panel.querySelector('a').href;col.appendChild(url);pair.appendChild(col);
    });
    var info=popup.document.createElement('p');info.textContent='Shop local. Score more. Scan with your phone camera. One stamp per shop every four hours. Redeem when your card is full.';sheet.appendChild(info);popup.document.body.appendChild(sheet);
  });
  popup.focus();
}
