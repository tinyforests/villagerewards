/* Pure copy formatter: transaction data supplies names, amounts and timestamps. */
(function(root) {
  function formatActivity(tx, now) {
    if (!tx) return { title: 'Your next little win starts here.', message: 'Visit a participating local and show your code to start earning.', time: '' };
    var timestamp = Date.parse(tx.created_at);
    var age = (now == null ? Date.now() : now) - timestamp;
    var recent = Number.isFinite(timestamp) && age >= -60000 && age < 5 * 60000;
    var just = recent ? 'You just ' : 'You ';
    var shop = tx.shop_name ? ' at ' + tx.shop_name : '';
    var points = tx.type === 'purchase' ? 1 : Math.abs(Number(tx.points) || 0);
    var unit = points === 1 ? 'stamp' : 'stamps';
    var title, message;
    if (tx.type === 'checkin') {
      title = just + 'checked in' + shop + '!';
      message = tx.note === 'gps_visit' ? 'Every 6 GPS check-ins earns 1 village stamp.' : 'Visit recorded. Scan the shop QR to earn a stamp.';
    } else if (tx.type === 'redeem' || tx.type === 'reward') {
      var item = tx.reward_title ? ' for ' + tx.reward_title : '';
      title = tx.type === 'reward' ? just + 'claimed your shop reward' + shop + '.' : just + 'redeemed ' + points + ' ' + unit + item + shop + '.';
      message = /coffee|espresso|cappuccino|latte|flat white|tea\b/i.test(tx.reward_title || '') ? 'Enjoy the cuppa!' : 'Enjoy your little treat!';
    } else if (tx.type === 'purchase') {
      title = tx.note === 'qr_scan' ? 'Stamp at ' + (tx.shop_name || 'your local shop') : just + 'earned ' + points + ' ' + unit + shop + '!';
      message = 'Thanks for shopping local. Your next treat is a little closer.';
    } else if (tx.type === 'bonus' && Number(tx.points) >= 0) {
      title = tx.note === 'shop_card_completion_bonus' ? 'Card completed! You earned 1 village stamp.' : tx.note === 'gps_checkin_bonus' ? 'Six visits! You earned 1 village stamp.' : 'A little extra: ' + points + ' bonus ' + unit + '!';
      message = tx.note === 'shop_card_completion_bonus' ? 'Your completed shop card earned a bonus in your village balance.' : tx.note === 'gps_checkin_bonus' ? 'Your next set of 6 check-ins starts now. This stamp is in your village balance.' : 'That’s something to smile about.';
    } else {
      title = 'Your stamps have been updated.';
      message = 'See your recent activity for the details.';
    }
    return { title: title, message: message, time: Number.isFinite(timestamp) ? (recent ? 'Just now' : new Date(timestamp).toLocaleString('en-AU', {day:'numeric',month:'short',hour:'numeric',minute:'2-digit'})) : 'Latest activity' };
  }
  root.formatCustomerActivity = formatActivity;
  if (typeof module !== 'undefined' && module.exports) module.exports = formatActivity;
})(typeof window !== 'undefined' ? window : globalThis);
