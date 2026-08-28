// Replaces CloudCLI's service worker, whose cache name is the literal
// 'claude-ui-v2' in every build. A fixed key means a new image never
// invalidates the client bundle a browser already holds, so the app runs an old
// client against a new server until someone clears site data by hand.
//
// This one takes over, drops every cache, unregisters itself and reloads open
// tabs. Offline caching is worth nothing for a LAN app behind ForwardAuth.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const key of await caches.keys()) {
        await caches.delete(key);
      }
      await self.registration.unregister();
      for (const client of await self.clients.matchAll({ type: 'window' })) {
        client.navigate(client.url);
      }
    })(),
  );
});
