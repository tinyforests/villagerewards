/* Camera scanning only fills an existing code field. Staff still confirm actions. */
(function () {
  'use strict';
  var dialog = document.getElementById('qr-scanner');
  var video = document.getElementById('qr-video');
  var status = document.getElementById('qr-status');
  var canvas = document.createElement('canvas');
  var context = canvas.getContext('2d', { willReadFrequently: true });
  var stream = null, timer = null, generation = 0, target = null;

  function stop() {
    generation++;
    clearTimeout(timer);
    if (stream) stream.getTracks().forEach(function (track) { track.stop(); });
    stream = null;
    video.srcObject = null;
  }
  function close() { stop(); if (dialog.open) dialog.close(); }
  function accept(text) {
    var code = String(text).trim().toUpperCase();
    if (code.indexOf('DEMO-') === 0) {
      status.textContent = 'This is a demo reward, not a live redemption. To earn points, scan the customer’s village code.';
      return false;
    }
    var valid = target === 'v' ? /^[A-F0-9]{12}$/.test(code) : /^[A-Z0-9]{6}$/.test(code);
    if (!valid) {
      status.textContent = target === 'v' ? 'Show a live reward QR code. Customer membership codes go in Purchase or Check-in.' : 'Show the customer’s six-character village QR code. Links and reward codes are not membership codes.';
      return false;
    }
    var prefix = target;
    var field = document.getElementById(prefix + '-code');
    close();
    field.value = code;
    field.dispatchEvent(new Event('input', { bubbles: true }));
    field.focus();
    window.showToast('Code scanned. Check the customer and confirm the action.');
    return true;
  }
  function frame(id) {
    if (id !== generation || !dialog.open) return;
    try {
      if (video.readyState >= 2 && video.videoWidth) {
        var scale = Math.min(1, 720 / video.videoWidth);
        canvas.width = Math.round(video.videoWidth * scale);
        canvas.height = Math.round(video.videoHeight * scale);
        context.drawImage(video, 0, 0, canvas.width, canvas.height);
        var pixels = context.getImageData(0, 0, canvas.width, canvas.height);
        var result = window.jsQR(pixels.data, pixels.width, pixels.height, { inversionAttempts: 'dontInvert' });
        if (result && accept(result.data)) return;
      }
      timer = setTimeout(function () { frame(id); }, 125);
    } catch (error) {
      stop();
      status.textContent = 'Scanning stopped. Close this window and try again, or type the code below.';
    }
  }
  window.openQrScanner = async function (prefix) {
    if (['p', 'ci', 'r', 'v'].indexOf(prefix) < 0 || dialog.open) return;
    stop(); target = prefix;
    dialog.showModal();
    status.textContent = 'Allow camera access, then point at the QR code on the customer’s phone.';
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || !window.isSecureContext) {
      status.textContent = 'Camera scanning needs HTTPS and a supported browser. Open the live site in Safari or Chrome, or type the code.';
      return;
    }
    if (typeof window.jsQR !== 'function') {
      status.textContent = 'The scanner could not load. Check your connection and reload, or type the code.';
      return;
    }
    var id = generation;
    try {
      var opened = await navigator.mediaDevices.getUserMedia({ audio: false, video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } } });
      if (id !== generation || !dialog.open) { opened.getTracks().forEach(function (track) { track.stop(); }); return; }
      stream = opened;
      video.srcObject = stream;
      await video.play();
      if (id !== generation || !dialog.open) return;
      status.textContent = 'Hold the QR code steady inside the camera view.';
      frame(id);
    } catch (error) {
      if (id !== generation) return;
      stop();
      status.textContent = error.name === 'NotAllowedError' ? 'Camera access was denied. Allow it in browser settings and try again, or type the code.' : 'The camera is unavailable. Close other camera apps and try again, or type the code.';
    }
  };
  document.getElementById('qr-close').addEventListener('click', close);
  dialog.addEventListener('cancel', stop);
  dialog.addEventListener('close', stop);
  window.addEventListener('pagehide', close);
  document.addEventListener('visibilitychange', function () { if (document.hidden) close(); });
})();
