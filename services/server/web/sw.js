// Offline shell for the installed app. Never touches /api, /export, /login or other origins.
const CACHE = 'nexus-shell-v1'
const SHELL = ['/app', '/app.js', '/app.css', '/manifest.webmanifest', '/icons/icon-192.png', '/icons/apple-touch-icon.png']

self.addEventListener('install', event => {
  self.skipWaiting()
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL)))
})

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) if (key !== CACHE) await caches.delete(key)
    await self.clients.claim()
  })())
})

/** Network first; after 3 s, offline, or a 5xx (the tunnel is down), the cached copy. */
async function networkFirst(request, fallback) {
  const cache = await caches.open(CACHE)
  const network = fetch(request).then(res => {
    if (res.ok) cache.put(fallback ?? request, res.clone())
    return res
  })
  const timeout = new Promise(resolve => setTimeout(resolve, 3000))
  try {
    const res = await Promise.race([network, timeout])
    if (res && res.status < 500) return res
  } catch { /* offline */ }
  const cached = await cache.match(fallback ?? request)
  return cached ?? network
}

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url)
  if (event.request.method !== 'GET' || url.origin !== location.origin) return
  if (/^\/(api|export|login|logout|health)(\/|$)/.test(url.pathname)) return
  if (event.request.mode === 'navigate') {
    // Every /app page boots the same shell.
    if (url.pathname === '/app' || url.pathname.startsWith('/app/')) event.respondWith(networkFirst(event.request, '/app'))
    return
  }
  if (SHELL.includes(url.pathname)) event.respondWith(networkFirst(event.request))
})
