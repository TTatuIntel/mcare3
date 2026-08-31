/* eslint-disable no-undef */
// Firebase Cloud Messaging service worker for mCare web push.
// `firebase-config.json` is deployment-specific, public Firebase metadata.
// Copy firebase-config.example.json and keep it aligned with the Flutter
// MCARE_FIREBASE_* build-time values.

// Keep this aligned with firebase_core_web's supportedFirebaseJsSdkVersion.
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-messaging-compat.js');

fetch(new URL('firebase-config.json', self.registration.scope), {
  cache: 'no-store',
})
  .then((response) => {
    if (!response.ok) throw new Error('firebase-config.json is unavailable');
    return response.json();
  })
  .then((firebaseConfig) => {
    firebase.initializeApp(firebaseConfig);
    const messaging = firebase.messaging();

    messaging.onBackgroundMessage((payload) => {
      // Notification payloads are displayed by FCM itself. Showing another
      // notification here would create duplicates. This branch is only the
      // safe fallback for a future data-only message.
      if (payload.notification) return undefined;

      const title = 'New mCare update';
      const options = {
        body: 'Open mCare to securely view this update.',
        icon: new URL('icons/Icon-192.png', self.registration.scope).href,
        badge: new URL('icons/Icon-192.png', self.registration.scope).href,
        tag: payload.data?.kind === 'sos' ? 'mcare-sos' : 'mcare-alert',
        requireInteraction: payload.data?.kind === 'sos',
        data: {
          ...(payload.data || {}),
          link: self.registration.scope,
        },
      };
      return self.registration.showNotification(title, options);
    });
  })
  .catch((error) => console.error('mCare web push is not configured', error));

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = event.notification.data?.link || self.registration.scope;
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ('focus' in client) {
          if ('navigate' in client) client.navigate(target);
          return client.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow(target);
    }),
  );
});
