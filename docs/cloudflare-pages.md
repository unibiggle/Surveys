# Cloudflare Pages Deployment (Flutter Web + Supabase)

This guide walks you through hosting the Flutter web app on Cloudflare Pages. The deployed site can be used to build templates and view completed surveys; all data is served securely from Supabase (Auth/DB/Storage) with Row Level Security.

---

## What you’ll get
- Global CDN hosting for the Flutter web app (static SPA)
- SPA routing with deep‑link support
- Custom domain + HTTPS
- CI/CD (optional) via GitHub Actions or Cloudflare Pages Git integration

Supabase stays your backend for Auth, Postgres, and Storage. Only the anon key is used in the browser and is safe to expose.

---

## Prerequisites
- Cloudflare account (free tier is enough)
- Supabase project ready (Auth + DB + Storage)
- Local Flutter SDK (to build the web bundle)
- This repo checked out locally

Recommended Supabase settings before deploying:
- Authentication → URL Configuration → add your final web domain(s) to Redirect URLs (production + preview)
- Run the provided SQL in `supabase/schema.sql` and `supabase/storage_policies.sql` (branding bucket + policies)

---

## Build the Flutter web bundle

From the repo root:

```
flutter build web --release --pwa-strategy=none
```

Notes
- `--pwa-strategy=none` avoids service worker stale cache issues during early iterations. You can switch to offline‑first later if desired.
- Output is in `build/web` (contains `index.html`, `assets/`, etc.).

Optional: add headers to prevent index.html from being cached aggressively. Create a file named `_headers` inside `build/web` with:

```
# Never cache the SPA shell
/index.html
  Cache-Control: no-cache, no-store, must-revalidate

# Cache hashed assets for a long time (optional – Flutter already hashes assets)
/assets/*
  Cache-Control: public, max-age=31536000, immutable
```

---

## Option A: Deploy with Wrangler (Direct Uploads)
This is the simplest, provider‑agnostic path (works great with Flutter).

1) Install + login
```
npm i -g wrangler
wrangler login
```

2) Create the Pages project (one‑time)
```
wrangler pages project create surveys-web
```

3) Deploy the current build
```
wrangler pages deploy build/web --project-name surveys-web
```

4) Enable SPA fallback
- Cloudflare Dashboard → Pages → your project → Settings → Build & deployments
- Toggle “Single‑Page Application” (history API fallback). This ensures all deep links serve `index.html`.

5) Add a custom domain (optional)
- Pages → Custom domains → Add
- Follow DNS instructions. Cloudflare will provision TLS automatically.

---

## Option B: GitHub Actions CI (build with Flutter, then deploy)

Add this workflow in `.github/workflows/deploy-pages.yml` (edit project name):

```yaml
name: Deploy Web to Cloudflare Pages
on:
  push:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
          channel: 'stable'

      - name: Install dependencies
        run: flutter pub get

      - name: Build web
        run: flutter build web --release --pwa-strategy=none

      - name: Install wrangler
        run: npm i -g wrangler

      - name: Deploy to Cloudflare Pages
        env:
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
        run: |
          wrangler pages deploy build/web \
            --project-name surveys-web \
            --branch main
```

Secrets to add in your GitHub repo → Settings → Secrets → Actions:
- `CLOUDFLARE_ACCOUNT_ID` (found in Cloudflare dashboard → Workers & Pages → Overview)
- `CLOUDFLARE_API_TOKEN` with Pages Write permission (create from Cloudflare → My Profile → API Tokens → Create Custom Token → scope: Account:Workers Pages = Edit)

After the first deploy, enable SPA fallback in the Pages project settings.

---

## Configure Supabase Auth Redirects
Supabase Dashboard → Authentication → URL Configuration:
- Add your production domain (e.g., `https://surveys.example.com/*`).
- Add the Cloudflare preview domain pattern (e.g., `https://*.pages.dev/*`) so preview deployments can log in.

No extra CORS settings are required for standard PostgREST/WebSocket usage from the browser.

---

## Environment configuration
The app reads Supabase settings from `.env` bundled as an asset (see `pubspec.yaml`). For production:
- Ensure `.env` contains:
  - `SUPABASE_URL=...`
  - `SUPABASE_ANON_KEY=...`
- Rebuild the app when you change `.env`.

This is safe: the anon key is designed for public clients. Do NOT include the service role key in the client bundle.

---

## Using the web app
- Sign in with Supabase Auth (email/password or magic link depending on your setup).
- Build templates (sections, branding, publish to shared library).
- View completed surveys; the app pulls team‑scoped and shared templates, and can be extended to pull surveys/responses automatically.

If you protect the site with Cloudflare Access (optional), keep in mind the Supabase OAuth/email flows must still be reachable.

---

## Troubleshooting
- Deep link 404s
  - Ensure “Single‑Page Application” is enabled in Pages settings.
- Stale UI after a deploy
  - Use `--pwa-strategy=none` (as shown) and add the `_headers` snippet to disable index.html caching.
- Auth popup blocked
  - Make sure your domain is in Supabase Auth Redirect URLs.
- Blank logo
  - For private logos stored in Supabase Storage, ensure the path is under `branding/{team_id}/...`. The app generates signed URLs automatically in the builder and at runtime in the runner.

---

## Optional: Split projects (staging/prod)
- Create two Pages projects (e.g., `surveys-web-stg` and `surveys-web`) and deploy from different branches.
- In Supabase, add both domains to Auth Redirect URLs.

---

## Quick Commands Recap
```
# Build locally
flutter build web --release --pwa-strategy=none

# First-time create & deploy (Wrangler)
wrangler login
wrangler pages project create surveys-web
wrangler pages deploy build/web --project-name surveys-web
```

That’s it. Once this is in place, you’ll have a fast, global web app for template building and survey viewing, backed by Supabase.

