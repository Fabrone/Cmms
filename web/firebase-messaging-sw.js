importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js")
importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging.js")

// Initialize Firebase
const firebaseApp = firebase.initializeApp({
  apiKey: "AIzaSyDPc49Am9wPVKqisi-qlP_1Ub2BT9rgTLI",
  authDomain: "cmms-e8a97.firebaseapp.com",
  projectId: "cmms-e8a97",
  storageBucket: "cmms-e8a97.firebasestorage.app",
  messagingSenderId: "1008434940174",
  appId: "1:1008434940174:web:3b76f298fa2c853c8c6f5f",
  measurementId: "G-BEF6SMCHBQ",
})

const messaging = firebase.messaging()

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  console.log("[firebase-messaging-sw.js] Received background message ", payload)

  if (payload.notification) {
    const notificationTitle = payload.notification.title || "NyumbaSmart Maintenance"
    const notificationOptions = {
      body: payload.notification.body || "You have maintenance tasks to check",
      icon: "/icon.png",
      badge: "/icon.png",
      tag: "maintenance-notification",
      requireInteraction: true,
      actions: [
        {
          action: "view",
          title: "View Details",
          icon: "/icon.png",
        },
        {
          action: "dismiss",
          title: "Dismiss",
          icon: "/icon.png",
        },
      ],
      data: {
        notificationId: payload.data?.notificationId || "",
        url: payload.data?.url || "/",
        timestamp: Date.now(),
        type: payload.data?.type || "maintenance_reminder",
      },
      vibrate: [200, 100, 200],
      silent: false,
      renotify: true,
    }

    // Increment notification count in localStorage
    try {
      const currentCount = Number.parseInt(localStorage.getItem("notification_count") || "0")
      localStorage.setItem("notification_count", (currentCount + 1).toString())
    } catch (e) {
      console.error("Error updating notification count:", e)
    }

    return self.registration.showNotification(notificationTitle, notificationOptions)
  }
})

// Handle notification clicks
self.addEventListener("notificationclick", (event) => {
  console.log("[firebase-messaging-sw.js] Notification click received.")

  event.notification.close()

  // Reset notification count
  try {
    localStorage.setItem("notification_count", "0")
  } catch (e) {
    console.error("Error resetting notification count:", e)
  }

  if (event.action === "view") {
    // Open the app and navigate to notification details
    event.waitUntil(
      clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
        // Check if app is already open
        for (const client of clientList) {
          if (client.url.includes(self.location.origin) && "focus" in client) {
            client.focus()
            client.postMessage({
              type: "NOTIFICATION_CLICKED",
              notificationId: event.notification.data?.notificationId,
            })
            return
          }
        }
        // If no window is open, open a new one
        return clients.openWindow("/maintenance-tasks")
      }),
    )
  } else if (event.action === "dismiss") {
    // Just close the notification
    console.log("Notification dismissed")
  } else {
    // Default action - open the app
    event.waitUntil(
      clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
        for (const client of clientList) {
          if (client.url.includes(self.location.origin) && "focus" in client) {
            client.focus()
            return
          }
        }
        return clients.openWindow("/")
      }),
    )
  }
})

// Handle notification close
self.addEventListener("notificationclose", (event) => {
  console.log("[firebase-messaging-sw.js] Notification closed.")
})

// Handle push events for better reliability
self.addEventListener("push", (event) => {
  console.log("[firebase-messaging-sw.js] Push event received.")

  if (event.data) {
    try {
      const payload = event.data.json()
      console.log("Push payload:", payload)
    } catch (e) {
      console.error("Error parsing push payload:", e)
    }
  }
})
