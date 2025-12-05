/* web/firebase-messaging-sw.js */

importScripts("https://www.gstatic.com/firebasejs/9.6.10/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.6.10/firebase-messaging-compat.js");

console.log("[SW] firebase-messaging-sw.js loaded");

firebase.initializeApp({
  apiKey: "AIzaSyBPCgA3KnxhLOuwXcW-1tmUqpXQq3eh5gc",
  authDomain: "sweep-dreams.firebaseapp.com",
  projectId: "sweep-dreams",
  storageBucket: "sweep-dreams.firebasestorage.app",
  messagingSenderId: "625444034450",
  appId: "1:625444034450:web:0502cc539a212a26f5934b",
});

const messaging = firebase.messaging();

// For debugging: log and *always* show a notification for background messages
messaging.onBackgroundMessage((payload) => {
  console.log("[SW] onBackgroundMessage", payload);

  const title = payload.notification?.title || "Sweep Dreams (bg)";
  const body =
    payload.notification?.body || JSON.stringify(payload.data || {});

  self.registration.showNotification(title, {
    body,
    data: payload.data,
  });
});
