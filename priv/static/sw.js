// ponytail: pass-through service worker. Android Chrome only offers "install" when a
// worker with a fetch handler is registered; we cache nothing (the game is live).
// Add caching here if offline start is ever wanted.
self.addEventListener("install", () => self.skipWaiting())
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()))
self.addEventListener("fetch", () => {})
