importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging.js');

firebase.initializeApp({
    apiKey: 'AIzaSyDPc49Am9wPVKqisi-qlP_1Ub2BT9rgTLI',
    authDomain: 'cmms-e8a97.firebaseapp.com',
    projectId: 'cmms-e8a97',
    storageBucket: 'cmms-e8a97.firebasestorage.app',
    messagingSenderId: '1008434940174',
    appId: '1:1008434940174:web:3b76f298fa2c853c8c6f5f',
    measurementId: 'G-BEF6SMCHBQ'
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
    console.log('[firebase-messaging-sw.js] Received background message ', payload);
    if (payload.notification) {
        const notificationTitle = payload.notification.title || 'Notification';
        const notificationOptions = {
            body: payload.notification.body || '',
            icon: '/favicon.png'
        };
        return self.registration.showNotification(notificationTitle, notificationOptions);
    }
});