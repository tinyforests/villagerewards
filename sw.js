/* ─────────────────────────────────────────────────────
   Village Rewards · Service Worker
   v1.0 · Mont Albert Pilot
   ───────────────────────────────────────────────────── */

var CACHE_NAME = 'village-rewards-navigation-v5';

/* Assets to cache on install so the app loads offline */
var PRECACHE = [
  '/',
  '/app.html',
  '/assets/brand.css',
  '/assets/app-brand.css',
  '/assets/qr-scanner.js',
  '/assets/customer-activity.js',
  '/docs/brand-book.html',
  'https://fonts.googleapis.com/css2?family=Nunito+Sans:wght@400;600;700;800;900&display=swap',
  'https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js'
];

/* ── Install: cache shell ── */
self.addEventListener('install', function(e) {
  e.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      return cache.addAll(PRECACHE);
    }).then(function() {
      return self.skipWaiting(); // activate immediately
    })
  );
});

/* ── Activate: clear old caches ── */
self.addEventListener('activate', function(e) {
  e.waitUntil(
    caches.keys().then(function(keys) {
      return Promise.all(
        keys
          .filter(function(key) { return key.startsWith('village-rewards-') && key !== CACHE_NAME; })
          .map(function(key) { return caches.delete(key); })
      );
    }).then(function() {
      return self.clients.claim(); // take control immediately
    })
  );
});

/* ── Fetch: network-first for API, cache-first for assets ── */
self.addEventListener('fetch', function(e) {
  var url = new URL(e.request.url);

  /* Supabase API calls — always network, never cache */
  if (url.hostname.includes('supabase.co')) {
    e.respondWith(fetch(e.request));
    return;
  }

  /* Google Fonts — cache-first */
  if (url.hostname.includes('fonts.g') || url.hostname.includes('fonts.googleapis')) {
    e.respondWith(
      caches.match(e.request).then(function(cached) {
        return cached || fetch(e.request).then(function(response) {
          return caches.open(CACHE_NAME).then(function(cache) {
            cache.put(e.request, response.clone());
            return response;
          });
        });
      })
    );
    return;
  }

  /* App shell — network-first, fall back to cache */
  e.respondWith(
    fetch(e.request)
      .then(function(response) {
        /* Cache successful GET responses */
        if (e.request.method === 'GET' && response.status === 200) {
          var clone = response.clone();
          caches.open(CACHE_NAME).then(function(cache) {
            cache.put(e.request, clone);
          });
        }
        return response;
      })
      .catch(function() {
        /* Offline fallback */
        return caches.match(e.request).then(function(cached) {
          return cached || caches.match('/app.html');
        });
      })
  );
});

/* ── Push notifications (future use) ── */
self.addEventListener('push', function(e) {
  if (!e.data) return;
  var data = e.data.json();
  e.waitUntil(
    self.registration.showNotification(data.title || 'Village Rewards', {
      body: data.body || '',
      icon: '/icons/icon-192.png',
      badge: '/icons/badge-72.png',
      data: data
    })
  );
});

self.addEventListener('notificationclick', function(e) {
  e.notification.close();
  e.waitUntil(
    clients.openWindow('/')
  );
});
