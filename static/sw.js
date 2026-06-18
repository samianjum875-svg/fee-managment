// AXIS PWA Service Worker
const CACHE_NAME = 'axis-cache-v1';
const STATIC_ASSETS = [
    '/manifest.json',
    '/static/icons/icon-192.png',
    '/static/icons/icon-512.png'
];

// Install event – cache static assets
self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => {
                // Add all static assets we can find
                return cache.addAll(STATIC_ASSETS).catch(err => {
                    console.warn('Some assets failed to cache:', err);
                });
            })
    );
    self.skipWaiting();
});

// Activate – clean old caches
self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys().then(cacheNames => {
            return Promise.all(
                cacheNames.map(cacheName => {
                    if (cacheName !== CACHE_NAME) {
                        return caches.delete(cacheName);
                    }
                })
            );
        })
    );
    self.clients.claim();
});

// Fetch strategy: network-first for API/portal, cache-first for static
self.addEventListener('fetch', event => {
    const url = new URL(event.request.url);
    // Network-first for dynamic content
    if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/portal/') || url.pathname === '/') {
        event.respondWith(
            fetch(event.request)
                .then(response => {
                    // If successful, clone and cache? We'll just return network response.
                    return response;
                })
                .catch(() => {
                    // Offline fallback: return cached response if available
                    return caches.match(event.request);
                })
        );
    } else {
        // Cache-first for static assets (CSS, JS, images, etc.)
        event.respondWith(
            caches.match(event.request)
                .then(cached => {
                    if (cached) {
                        return cached;
                    }
                    // Not in cache: fetch and cache for future
                    return fetch(event.request).then(response => {
                        const cloned = response.clone();
                        caches.open(CACHE_NAME).then(cache => {
                            cache.put(event.request, cloned);
                        });
                        return response;
                    });
                })
        );
    }
});
