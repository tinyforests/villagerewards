# Village Rewards - Architecture Documentation

**Deployment:** GitHub Pages → villagerewards.com.au  
**Backend:** Supabase PostgreSQL  
**Build:** None (static HTML/CSS/JS)

---

## System Overview

Village Rewards is a **zero-build static web application** that uses Supabase as a backend-as-a-service. The entire application consists of flat HTML files served directly from GitHub Pages, with no transpilation, bundling, or server-side rendering.

This architecture was chosen for **simplicity and speed** during the MVP phase. It has served the pilot well but will likely need refactoring for multi-village scale.

---

## Architecture Diagram

```
┌─────────────┐
│   Customer  │
│   (Mobile)  │
└──────┬──────┘
       │
       │ HTTPS
       │
       ▼
┌─────────────────────────────────────────────────┐
│                                                 │
│           GitHub Pages (Static Host)            │
│                                                 │
│  ┌────────────┐  ┌──────────────┐  ┌─────────┐ │
│  │ index.html │  │   app.html   │  │ admin   │ │
│  │  (Landing) │  │ (PWA - Main) │  │  (D3)   │ │
│  └────────────┘  └──────┬───────┘  └────┬────┘ │
│                         │                │      │
└─────────────────────────┼────────────────┼──────┘
                          │                │
                          │ Supabase JS    │
                          │ Client (CDN)   │
                          │                │
                          ▼                ▼
                ┌────────────────────────────────┐
                │                                │
                │      Supabase PostgreSQL       │
                │                                │
                │  ┌─────────┐  ┌──────────┐    │
                │  │customers│  │   shops  │    │
                │  └─────────┘  └──────────┘    │
                │  ┌─────────┐  ┌──────────┐    │
                │  │  trans- │  │  views   │    │
                │  │ actions │  │(stats)   │    │
                │  └─────────┘  └──────────┘    │
                │                                │
                │  RLS Policies + Triggers       │
                │                                │
                └────────────────────────────────┘
```

---

## Frontend Architecture

### File Structure (Flat)

```
villagerewards/
├── index.html                 # Marketing landing page (48KB)
├── app.html                   # Main PWA (customer + trader) (60KB)
├── village-rewards-admin.html # Admin dashboard (60KB)
├── ma-presentation.html       # Mont Albert trader pitch deck (32KB)
├── village-rewards-pwa.html   # DEAD CODE - localStorage prototype
├── sw.js                      # Service worker (PWA offline support)
└── CNAME                      # Custom domain config
```

### Technology Stack

**HTML/CSS/JS:**
- Pure vanilla JavaScript (ES5 + some ES6 async/await)
- No framework, no build step, no transpilation
- Inline CSS with CSS custom properties (design tokens)
- No TypeScript, no JSX, no preprocessors

**PWA:**
- Service worker: `sw.js` (caches HTML/CSS/JS for offline)
- No manifest.json (❌ **Android install broken**)
- iOS meta tags present (`apple-mobile-web-app-capable`)

**Dependencies (CDN-loaded):**
```html
<!-- Supabase client -->
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>

<!-- QR code generation -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>

<!-- D3.js (admin dashboard only) -->
<script src="https://d3js.org/d3.v7.min.js"></script>

<!-- Google Fonts -->
<link href="https://fonts.googleapis.com/css2?family=Abril+Fatface&display=swap">
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&display=swap">
```

### Page Responsibilities

**index.html** (Landing Page):
- Public marketing site
- Explains Village Rewards concept
- Links to customer registration (app.html)
- G&S brand identity
- No Supabase connection

**app.html** (Main PWA):
- Customer registration
- Customer points dashboard
- QR code generation (earning points)
- Trader login (currently disabled)
- Trader POS interface (issue points, check-ins, redemptions)
- Supabase: customers, shops, transactions tables

**village-rewards-admin.html** (Admin Dashboard):
- Admin login (currently disabled)
- Realtime activity feed
- D3 force-directed network graph (cross-shop journeys)
- Cross-pollination matrix
- Customer/transaction tables
- Heatmap (hour × day)
- Badge system
- Supabase: All tables + views

**village-rewards-pwa.html** (DEAD CODE):
- Earlier localStorage-only prototype
- No Supabase connection
- Not linked from anywhere
- Should be removed or archived

**ma-presentation.html** (Pitch Deck):
- HTML slide deck for Mont Albert traders
- Static content
- No Supabase connection
- Used for in-person presentations

---

## Backend Architecture (Supabase)

### Supabase Components Used

**PostgreSQL Database:**
- Tables: customers, shops, transactions
- Views: village_stats, customer_stats, shop_stats, cross_pollination, etc.
- Triggers: update customer points after transaction insert
- RLS Policies: (configured but not documented)

**Supabase Auth:**
- Not currently used (pending implementation)
- Will use for admin + trader authentication

**Supabase Realtime:**
- Used in admin dashboard for live activity feed
- Subscribes to `transactions` table inserts
- WebSocket connection via Supabase JS client

**PostgREST API:**
- Auto-generated REST API for all tables
- Accessed via Supabase JS client
- RLS policies enforce access control

### Data Flow

**Customer Registration:**
```
Customer → app.html → Supabase JS → INSERT customers
```

**Point Earning (Purchase):**
```
Customer → shows QR → Trader scans QR → app.html
→ Trader enters amount → Supabase JS → INSERT transactions
→ Database trigger → UPDATE customers.points
```

**Point Earning (Check-in):**
```
Customer → requests check-in → Trader validates → app.html
→ JavaScript checks GPS distance (150m radius)
→ Supabase JS → INSERT transactions (type='checkin')
→ Database trigger → UPDATE customers.points
```

**Redemption (Current Prototype):**
```
Customer → selects reward → app.html → Supabase JS
→ INSERT transactions (type='redeem', points=negative)
→ Database trigger → UPDATE customers.points
```

**Admin Dashboard (Realtime):**
```
Admin dashboard → Supabase Realtime subscribe(transactions)
→ WebSocket connection → live feed updates
→ D3.js re-renders graphs on new data
```

---

## Deployment Architecture

### GitHub Pages

**Hosting:** GitHub Pages (free tier)  
**Domain:** villagerewards.com.au  
**SSL:** Automatic via GitHub Pages  
**CDN:** GitHub's CDN (global distribution)

**Deployment Flow:**
```
Developer → git commit → git push origin main
→ GitHub Actions (automatic) → Deploy to Pages
→ Live in ~30 seconds
```

**No Build Step:**
- HTML files deployed exactly as committed
- No webpack, Vite, Parcel, esbuild, etc.
- No minification, no concatenation, no tree-shaking
- CSS custom properties preserved (no PostCSS)

### Custom Domain Setup

**CNAME file:**
```
villagerewards.com.au
```

**DNS Configuration (External):**
```
CNAME villagerewards.com.au → tinyforests.github.io
```

### Environment Variables

**None.** All configuration is hardcoded in JavaScript:

```javascript
var SUPABASE_URL = 'https://hwtwfhvaeczofqktychc.supabase.co';
var SUPABASE_KEY = 'eyJhbGci...'; // Anon key (public)
var PTS_PER_DOLLAR = 1;
var CHECKIN_POINTS = 8;
```

---

## PWA Architecture

### Service Worker (sw.js)

**Purpose:** Offline support for customer PWA

**Cache Strategy:**
```javascript
// Cache-first for HTML/CSS/JS
self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((response) => {
      return response || fetch(event.request);
    })
  );
});
```

**Cached Assets:**
- app.html
- CSS (inline, but cached with HTML)
- JavaScript (inline, but cached with HTML)
- Fonts (Google Fonts - network-first)

### Missing: manifest.json

**Problem:** No `manifest.json` file exists

**Impact:**
- Android users can't "Add to Home Screen"
- iOS users can (via meta tags), but experience is degraded
- No custom app icon (uses favicon)
- No splash screen
- No app name customization

**sw.js references missing icons:**
```javascript
'/icons/icon-192.png'  // ❌ Does not exist
'/icons/badge-72.png'   // ❌ Does not exist
```

**Solution Required:**
```json
// manifest.json (create this file)
{
  "name": "Village Rewards",
  "short_name": "Village",
  "start_url": "/app.html",
  "display": "standalone",
  "background_color": "#fff0dc",
  "theme_color": "#3d4535",
  "icons": [
    {
      "src": "/icons/icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "/icons/icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
```

---

## Design System Architecture

### CSS Custom Properties

**Canonical Colors (G&S Brand):**
```css
:root {
  --green: #3d4535;      /* Gardener Green */
  --beige: #fff0dc;      /* Nostalgic Beige */
  --accent: #a8c285;     /* Signal Green */
  --dark: #1a1a1a;
  --mid: #666666;
  --light: #f5f5f5;
}
```

**Dark Mode (Canopy/Understory):**
```css
html.dark {
  --bg: var(--green);
  --text: var(--beige);
  /* ... inverted palette */
}
```

**Typography:**
```css
:root {
  --heading: 'Abril Fatface', serif;
  --body: 'IBM Plex Sans', sans-serif;
  --mono: 'IBM Plex Mono', monospace;
}
```

**Problem:** Design tokens duplicated across 4 HTML files. Any brand change requires editing:
- index.html
- app.html
- village-rewards-admin.html
- ma-presentation.html

**Solution:** Extract to shared `styles.css` or use CSS imports.

---

## Performance Characteristics

### Page Load Performance

**index.html (Landing):**
- Size: 48KB (inline HTML/CSS/JS)
- External requests: 2 (Google Fonts)
- No Supabase connection
- Fast: ~500ms first paint

**app.html (PWA):**
- Size: 60KB (inline HTML/CSS/JS)
- External requests: 4 (Fonts, Supabase CDN, QR library)
- Supabase connection: ~200ms
- Moderate: ~1000ms interactive

**admin.html (Dashboard):**
- Size: 60KB (inline HTML/CSS/JS)
- External requests: 5 (Fonts, Supabase, QR, D3)
- Initial data load: ~500ms (tables + views)
- Realtime subscription: WebSocket maintained
- Heavy: ~2000ms fully interactive (D3 graph rendering)

### Database Query Performance

**Fast queries (<50ms):**
- Single customer lookup by ID
- Single shop lookup
- Insert transaction

**Moderate queries (50-200ms):**
- Customer stats view (joins)
- Shop stats view (aggregates)
- Transaction history (sorted, limited)

**Slow queries (200-500ms):**
- Village stats (full table scans)
- Cross-pollination matrix (all customer journeys)

**Very slow queries (>500ms):**
- Admin dashboard initial load (all views + tables)

**No indexing strategy documented.** See `docs/SCHEMA.md` for index recommendations.

---

## Scalability Considerations

### Current Limits (Single Village)

**Mont Albert Pilot:**
- ~100 customers
- ~20 shops
- ~1000 transactions
- Performs well

**Estimated Breaking Points:**
- 1,000 customers: Fine
- 10,000 customers: Queries slow without indexes
- 100,000 transactions: Cross-pollination view becomes unusable
- 100 concurrent users: Supabase free tier rate limits hit

### Multi-Village Challenges

**Current architecture assumes single village:**
- No `village_id` foreign keys
- Mont Albert hardcoded throughout UI
- Views don't filter by village
- One global points pool

**Required changes for multi-village:**
1. Add `village_id` to customers, shops, transactions
2. Update all views to filter by village
3. Separate points balances per village (or global with village tracking)
4. Village selector UI
5. Multi-tenancy RLS policies

---

## Technology Debt

### Build System
- **Debt:** No build process means no TypeScript, no tree-shaking, no minification
- **Impact:** Low (files are small, load fast)
- **Migration Path:** Vite or Next.js if complexity grows

### Modularity
- **Debt:** All code in monolithic HTML files (60KB each)
- **Impact:** Medium (hard to maintain, hard to test)
- **Migration Path:** Extract to ES modules, use imports

### Testing
- **Debt:** Zero tests (no unit, integration, or E2E)
- **Impact:** High (regressions invisible until production)
- **Migration Path:** Vitest for unit, Playwright for E2E

### State Management
- **Debt:** Global variables, imperative DOM manipulation
- **Impact:** Medium (state hard to reason about)
- **Migration Path:** React + Context or Vue + Pinia

### Design Tokens
- **Debt:** CSS custom properties duplicated across files
- **Impact:** Low (values are consistent, just maintenance burden)
- **Migration Path:** Extract to shared stylesheet

---

## Migration Path (Future Architecture)

### Option 1: Modern Static (Recommended for Now)

Keep static hosting, add build tooling:

- **Framework:** None (stay vanilla) or Preact/Solid (minimal)
- **Build:** Vite for bundling, minification, TypeScript
- **Styling:** Keep CSS custom properties, add Tailwind (optional)
- **Hosting:** Keep GitHub Pages
- **Backend:** Keep Supabase

**Pros:** Minimal disruption, keeps simplicity, adds developer experience  
**Cons:** Still static (no server-side logic)

### Option 2: Full-Stack Framework

Move to server-rendered architecture:

- **Framework:** Next.js or SvelteKit
- **Hosting:** Vercel or Cloudflare Pages
- **Backend:** Keep Supabase or migrate to Prisma + own database
- **Auth:** Supabase Auth or NextAuth
- **API:** Next.js API routes or SvelteKit server endpoints

**Pros:** Server-side validation, better SEO, more control  
**Cons:** More complex deployment, higher hosting cost, steeper learning curve

### Option 3: Mobile-First (If Scaling Nationally)

Native or hybrid mobile apps:

- **Framework:** React Native or Flutter
- **Backend:** Supabase (keep) + serverless functions (add)
- **Hosting:** App Store + Google Play
- **Web:** Keep as companion site

**Pros:** Better mobile UX, offline-first, push notifications  
**Cons:** App store approval, platform-specific code, more maintenance

---

## Monitoring & Observability

**Current state:** None

**What's missing:**
- Error tracking (Sentry, etc.)
- Performance monitoring (Web Vitals, etc.)
- Analytics (Plausible, etc.)
- Supabase query logging
- Alert on Supabase rate limits

**Recommendation:** Add minimal observability before multi-village launch.

---

## Security Architecture

See `docs/SECURITY.md` for full security documentation.

**Current approach:**
- Client-side code (all business logic exposed)
- Supabase anon key (public, intentional)
- RLS policies (configured but undocumented)
- No server-side validation

**Required improvements:**
- Document RLS policies
- Move validation to database triggers or Edge Functions
- Add rate limiting
- Implement proper authentication

---

## Action Items

**Immediate (Fix Broken PWA):**
- [ ] Create manifest.json
- [ ] Add icon assets to /icons/
- [ ] Link manifest in app.html
- [ ] Test Android install flow

**Short-term (Improve Maintainability):**
- [ ] Extract CSS custom properties to shared file
- [ ] Remove dead file (village-rewards-pwa.html)
- [ ] Add basic error tracking (Sentry free tier)
- [ ] Document database indexes

**Medium-term (Prepare for Scale):**
- [ ] Add build process (Vite)
- [ ] Extract JavaScript to modules
- [ ] Add unit tests for business logic
- [ ] Set up staging environment

**Long-term (Multi-Village):**
- [ ] Migrate to Next.js or SvelteKit
- [ ] Add server-side validation
- [ ] Implement multi-tenancy
- [ ] Consider mobile app
