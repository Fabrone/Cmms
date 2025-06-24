const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// Enhanced notification checker with 9 AM and 11 AM fallback
exports.checkNotifications = functions.pubsub
  .schedule("0 9,11 * * *") // Run at 9 AM and 11 AM daily
  .timeZone("Africa/Nairobi") // Change to your timezone
  .onRun(async () => {
    const now = new Date();
    const currentHour = now.getHours();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    console.log(`Running notification check at ${now.toISOString()} (Hour: ${currentHour})`);

    try {
      // Get due notifications that haven't been triggered
      const notificationsSnapshot = await admin
        .firestore()
        .collection("Notifications")
        .where("notificationDate", "<=", admin.firestore.Timestamp.fromDate(today))
        .where("isTriggered", "==", false)
        .get();

      console.log(`Found ${notificationsSnapshot.docs.length} notifications to process`);

      if (notificationsSnapshot.docs.length === 0) {
        console.log("No due notifications found");
        return { success: true, processedCount: 0, message: "No notifications to process" };
      }

      const batch = admin.firestore().batch();
      let processedCount = 0;

      for (const doc of notificationsSnapshot.docs) {
        const data = doc.data();
        const notifications = data.notifications || [];

        console.log(`Processing notification group ${doc.id} with ${notifications.length} tasks`);

        // Update each individual notification's isTriggered status
        const updatedNotifications = notifications.map((notification) => ({
          ...notification,
          isTriggered: true,
          triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
        }));

        // Get all users with FCM tokens (technicians, admins, and regular users)
        const usersSnapshot = await admin.firestore()
          .collection("Users")
          .where("fcmToken", "!=", null)
          .get();

        const validTokens = [];
        const userTokenMap = new Map();

        for (const userDoc of usersSnapshot.docs) {
          const userData = userDoc.data();
          const fcmToken = userData.fcmToken;

          // Check if notifications are enabled for this user
          const notificationsEnabled = userData.notificationsEnabled !== false; // Default to true

          if (fcmToken && notificationsEnabled) {
            validTokens.push(fcmToken);
            userTokenMap.set(fcmToken, userDoc.id);
          }
        }

        console.log(`Sending notifications to ${validTokens.length} users`);

        if (validTokens.length > 0) {
          const categories = [...new Set(notifications.map((n) => n.category))];
          const title = "🔧 Maintenance Tasks Due";
          const body = `${notifications.length} tasks due in: ${categories.join(", ")}`;

          // Prepare the message payload
          const messagePayload = {
            notification: { title, body },
            data: {
              notificationId: doc.id,
              type: "maintenance_reminder",
              taskCount: notifications.length.toString(),
              categories: categories.join(","),
              notificationDate: data.notificationDate.toDate().toISOString(),
              isTriggered: "true",
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
              triggeredHour: currentHour.toString(),
            },
            android: {
              notification: {
                channelId: "maintenance_channel",
                priority: "high",
                defaultSound: true,
                defaultVibrateTimings: true,
                sound: "default",
                color: "#607D8B",
                icon: "ic_launcher",
                clickAction: "FLUTTER_NOTIFICATION_CLICK",
                tag: "maintenance_notification",
              },
              priority: "high",
              ttl: 86400000, // 24 hours
            },
            apns: {
              payload: {
                aps: {
                  sound: "default",
                  badge: 1,
                  contentAvailable: true,
                  alert: { title, body },
                },
              },
              headers: {
                "apns-priority": "10",
                "apns-expiration": Math.floor(Date.now() / 1000) + 86400,
              },
            },
            webpush: {
              notification: {
                title,
                body,
                icon: "/icon.png",
                badge: "/icon.png",
                tag: "maintenance_notification",
                requireInteraction: true,
                vibrate: [200, 100, 200],
              },
              headers: { Urgency: "high", TTL: "86400" },
              data: { notificationId: doc.id, url: "/maintenance-tasks" },
            },
            tokens: validTokens,
          };

          try {
            const response = await admin.messaging().sendMulticast(messagePayload);
            console.log(`Sent ${response.successCount} notifications`);

            if (response.failureCount > 0) {
              console.log(`Failed to send ${response.failureCount} notifications`);
              response.responses.forEach((resp, idx) => {
                if (!resp.success) {
                  console.error(`Failed to send to token ${validTokens[idx]}: ${resp.error}`);
                }
              });
            }
          } catch (error) {
            console.error("Error sending multicast message:", error);
          }
        }

        // Mark notification as triggered with updated individual notifications
        batch.update(doc.ref, {
          isTriggered: true,
          isRead: false,
          notifications: updatedNotifications,
          triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
          triggeredHour: currentHour,
        });

        processedCount++;
      }

      await batch.commit();
      console.log(`Processed ${processedCount} groups at ${currentHour}:00`);

      return {
        success: true,
        processedCount,
        triggeredHour: currentHour,
        message: `Processed ${processedCount} notification groups at ${currentHour}:00`,
      };
    } catch (error) {
      console.error("Error in checkNotifications:", error);
      throw new functions.https.HttpsError("internal", "Failed to process notifications", error);
    }
  });

// Manual trigger function for testing
exports.triggerNotificationsManually = functions.https.onCall(async (data, context) => {
  // Verify the user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  console.log(`Manual trigger requested by user: ${context.auth.uid}`);

  try {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    // Get due notifications that haven't been triggered
    const notificationsSnapshot = await admin.firestore()
      .collection("Notifications")
      .where("notificationDate", "<=", admin.firestore.Timestamp.fromDate(today))
      .where("isTriggered", "==", false)
      .get();

    console.log(`Manual trigger found ${notificationsSnapshot.docs.length} notifications`);

    if (notificationsSnapshot.docs.length === 0) {
      return { success: true, processedCount: 0, message: "No notifications to process" };
    }

    const batch = admin.firestore().batch();
    let processedCount = 0;

    for (const doc of notificationsSnapshot.docs) {
      const data = doc.data();
      const notifications = data.notifications || [];

      // Update notification status
      const updatedNotifications = notifications.map((notification) => ({
        ...notification,
        isTriggered: true,
        triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
      }));

      // Mark as triggered
      batch.update(doc.ref, {
        isTriggered: true,
        isRead: false,
        notifications: updatedNotifications,
        triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
        triggeredManually: true,
        triggeredBy: context.auth.uid,
      });

      processedCount++;
    }

    await batch.commit();
    console.log(`Manual trigger processed ${processedCount} notification groups`);

    return {
      success: true,
      processedCount,
      message: `Manually triggered ${processedCount} notification groups`,
    };
  } catch (error) {
    console.error("Error in manual trigger:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to trigger notifications",
      error,
    );
  }
});

// Function to clean up old notifications (run weekly)
exports.cleanupOldNotifications = functions.pubsub
  .schedule("0 0 * * 0") // Run every Sunday at midnight
  .timeZone("Africa/Nairobi")
  .onRun(async () => {
    console.log("Running notification cleanup");

    try {
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

      const oldNotificationsSnapshot = await admin.firestore()
        .collection("Notifications")
        .where("notificationDate", "<", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
        .where("isTriggered", "==", true)
        .get();

      console.log(`Found ${oldNotificationsSnapshot.docs.length} old notifications to clean up`);

      const batch = admin.firestore().batch();
      let deletedCount = 0;

      for (const doc of oldNotificationsSnapshot.docs) {
        batch.delete(doc.ref);
        deletedCount++;
      }

      await batch.commit();
      console.log(`Cleaned up ${deletedCount} old notifications`);

      return {
        success: true,
        deletedCount,
        message: `Cleaned up ${deletedCount} old notifications`,
      };
    } catch (error) {
      console.error("Error in cleanup:", error);
      throw new functions.https.HttpsError("internal", "Failed to cleanup notifications", error);
    }
  });
