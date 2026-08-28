/* eslint-disable no-undef */
// Firebase Cloud Messaging service worker for mCare web push.
// `firebase-config.json` is deployment-specific, public Firebase metadata.
// Copy firebase-config.example.json and keep it aligned with the Flutter
// MCARE_FIREBASE_* build-time values.

importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

fetch('/firebase-config.json', { cache: 'no-store' })
  .then((response) => {
    if (!response.ok) throw new Error('firebase-config.json is unavailable');
    return response.json();
  })
  .then((firebaseConfig) => {
    firebase.initializeApp(firebaseConfig);
    const messaging = firebase.messaging();

    messaging.onBackgroundMessage((payload) => {
      const title = payload.notification?.title || 'mCare alert';
      const options = {
        body: payload.notification?.body || 'New clinical update',
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        tag: payload.data?.kind === 'sos' ? 'mcare-sos' : 'mcare-alert',
        requireInteraction: payload.data?.kind === 'sos',
        data: payload.data || {},
      };
      return self.registration.showNotification(title, options);
    });
  })
  .catch((error) => console.error('mCare web push is not configured', error));

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow('/');
    }),
  );
});
