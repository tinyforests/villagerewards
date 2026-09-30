/* Pure copy formatter: transaction data supplies names, amounts and timestamps. */
(function(root) {
  function formatActivity(tx, now) {
    if (!tx) return { title: 'Your next little win starts here.', message: 'Visit a participating local and show your code to start earning.', time: '' };
    var timestamp = Date.parse(tx.created_at);
    var age = (now == null ? Date.now() : now) - timestamp;
    var recent = Number.isFinite(timestamp) && age >= -60000 && age < 5 * 60000;
    var just = recent ? 'You just ' : 'You ';
    var shop = tx.shop_name ? ' at ' + tx.shop_name : '';
    var points = Math.abs(Number(tx.points) || 0);
    var title, message;
    if (tx.type === 'checkin') {
      title = just + 'checked in' + shop + '!';
      message = 'Great to see you here!' + (points ? ' +' + points + ' points.' : '');
    } else if (tx.type === 'redeem' || tx.type === 'reward') {
      var item = tx.reward_title ? ' for ' + tx.reward_title : '';
      title = tx.type === 'reward' ? just + 'claimed your shop reward' + shop + '.' : just + 'redeemed ' + points + ' points' + item + shop + '.';
      message = /coffee|espresso|cappuccino|latte|flat white|tea\b/i.test(tx.reward_title || '') ? 'Enjoy the cuppa!' : 'Enjoy your little treat!';
    } else if (tx.type === 'purchase') {
      title = just + 'earned ' + points + ' points' + shop + '!';
      message = 'Thanks for shopping local. Your next treat is a little closer.';
    } else if (tx.type === 'bonus' && Number(tx.points) >= 0) {
      title = 'A little extra: ' + points + ' bonus points!';
      message = 'That’s something to smile about.';
    } else {
      title = 'Your points have been updated.';
      message = 'See your recent activity for the details.';
    }
    return { title: title, message: message, time: Number.isFinite(timestamp) ? (recent ? 'Just now' : new Date(timestamp).toLocaleString('en-AU', {day:'numeric',month:'short',hour:'numeric',minute:'2-digit'})) : 'Latest activity' };
  }
  root.formatCustomerActivity = formatActivity;
  if (typeof module !== 'undefined' && module.exports) module.exports = formatActivity;
})(typeof window !== 'undefined' ? window : globalThis);
