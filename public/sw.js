const CACHE = 'monopoly-shell-v1';
const SHELL = ['/', '/crear', '/unirse', '/sala', '/favicon.svg'];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim()));
});
self.addEventListener('fetch', event => {
  const request=event.request;
  const url=new URL(request.url);
  if (url.origin!==self.location.origin || request.method!=='GET' || url.pathname.startsWith('/api')) return;
  if (request.mode==='navigate') {
    event.respondWith(fetch(request).catch(async () => {
      const cached=await caches.match(url.pathname);
      return cached || new Response('Sin conexión. Vuelve a intentarlo cuando tengas internet.',{status:503,headers:{'Content-Type':'text/plain; charset=utf-8'}});
    }));
    return;
  }
  if (url.pathname.startsWith('/_astro/') || url.pathname.startsWith('/favicon')) {
    event.respondWith(caches.match(request).then(cached => cached || fetch(request).then(response=>{
      if (response.ok) {
        const copy=response.clone();
        void caches.open(CACHE).then(cache=>cache.put(request,copy));
      }
      return response;
    })));
  }
});
