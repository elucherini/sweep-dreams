/* web/firebase-messaging-sw.js */

importScripts("https://www.gstatic.com/firebasejs/9.6.10/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.6.10/firebase-messaging-compat.js");

// TODO: Replace with your own config from Firebase console
firebase.initializeApp({
  apiKey: "AIzaSyBPCgA3KnxhLOuwXcW-1tmUqpXQq3eh5gc",
  authDomain: "sweep-dreams.firebaseapp.com",
  projectId: "sweep-dreams",
  storageBucket: "sweep-dreams.firebasestorage.app",
  messagingSenderId: "625444034450",
  appId: "1:625444034450:web:0502cc539a212a26f5934b",
});

// Retrieve an instance of Firebase Messaging
const messaging = firebase.messaging();
