importScripts(
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js',
);

firebase.initializeApp({
  apiKey: 'AIzaSyBsDkRB2A6-IPJs1n-5siCVWiMOETudKXo',
  authDomain: 'smarthcane-11b47.firebaseapp.com',
  projectId: 'smarthcane-11b47',
  storageBucket: 'smarthcane-11b47.firebasestorage.app',
  messagingSenderId: '60336439697',
  appId: '1:60336439697:web:5863a0a5ba25821dbc1a30',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const data = payload.data || {};
  if (data.type !== 'sos') return;

  const title = data.title || 'SOS Darurat';
  const body = data.body || 'Pengguna membutuhkan bantuan segera';

  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    requireInteraction: true,
    tag: data.sosId ? `sos-${data.sosId}` : 'sos-alert',
    data,
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const familyUrl = new URL('/#/family/home', self.location.origin).href;

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(
      (clients) => {
        for (const client of clients) {
          if ('focus' in client) {
            client.focus();
            if ('navigate' in client) {
              return client.navigate(familyUrl);
            }
            return undefined;
          }
        }

        if (self.clients.openWindow) {
          return self.clients.openWindow(familyUrl);
        }

        return undefined;
      },
    ),
  );
});
