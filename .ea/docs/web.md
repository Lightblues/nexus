# Web app

The server serves a landing page and a read-only web app from `services/server/web/` (plain HTML, CSS, and one
JavaScript module; no build step). It is a tool app in the pwa skill's sense: every level is a URL with a clickable
breadcrumb, there is a ⋯ page menu, and ids and absolute times are visible on hover.

## Pages

| Path | Page |
|---|---|
| `/` | Landing: what Nexus is, the brew command, links to the app and GitHub |
| `/login` | Paste a key; `POST /login` (form field `key`) sets the session and redirects to `/app` |
| `/app` | Today |
| `/app/day/<day>` | One day: active time, pomodoros, first and last activity, a 24 h timeline (category blocks, pomodoro row), categories, projects, apps, sites, focus blocks, sessions; links to the day before and after |
| `/app/day/<day>/records` | Every cleaned activity row of the day |
| `/app/history?to=<day>` | 30 days, one row each with a stacked category bar; earlier and later pages |
| `/app/devices` | Each device's name, id, last push, last activity, row counts |

Every `/app/*` path returns the same `app.html`; `app.js` routes on `location.pathname`, and in-app links use
`history.pushState`. A 401 from the API sends the browser to `/login`. The ⋯ menu has Back to top, Share… (when
`navigator.share` exists), Copy link, Reload, and Sign out.

## Sessions

`POST /login` checks the key like a bearer and creates a session (`sessions` table, sha256 of a random token, 90
days). The cookie `nexus_session` is `HttpOnly; Secure; SameSite=Lax`. A session only reads, even when the key
was a write key: the read routes accept it, and `/api/sync/*`, `/api/settings` and the write routes do not.
`POST /logout` deletes the session. The browser never stores the key.

## PWA

`manifest.webmanifest` (`start_url` `/app`, standalone), icons rendered from `icons/icon.svg` by
`scripts/generate-icons.py` (192, 512, 180 for `apple-touch-icon`, 32 favicon; the same script writes the Mac
AppIcon set; the root `icon.svg` symlink is what Paseo shows), `viewport-fit=cover` with safe-area padding, light and dark `theme-color`.
`sw.js` caches the shell (`nexus-shell-v1`): navigations under `/app` are network-first and fall back to the cached
`/app` after 3 s, offline, or a 5xx; the shell files are network-first; `/api`, `/export`, `/login` are never
touched. Bump the cache name when the shell's file list changes. No Web Push: nothing here needs to notify.

## Security

The pages are public; the data behind them is not. HTML responses carry a CSP (`default-src 'self'`, no inline
scripts, `frame-ancestors 'none'`). Only the files present in `web/` at start are served, by exact name. Changing
`web/` needs a server restart.
