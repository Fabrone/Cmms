const functions = require("firebase-functions")
const admin = require("firebase-admin")

admin.initializeApp()

// Update the cloud function to include more notification details
exports.checkNotifications = functions.pubsub
  .schedule("0 9 * * *") // Run daily at 9:00 AM UTC
  .timeZone("UTC") // You can change this to your local timezone
  .onRun(async (context) => {
    const now = new Date()
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())

    console.log(`Running notification check at ${now.toISOString()}`)

    try {
      // Get due notifications that haven't been triggered
      const notificationsSnapshot = await admin
        .firestore()
        .collection("Notifications")
        .where("notificationDate", "<=", admin.firestore.Timestamp.fromDate(today))
        .where("isTriggered", "==", false)
        .get()

      console.log(`Found ${notificationsSnapshot.docs.length} notifications to process`)

      const batch = admin.firestore().batch()
      let processedCount = 0

      for (const doc of notificationsSnapshot.docs) {
        const data = doc.data()
        const notifications = data.notifications || []

        console.log(`Processing notification group ${doc.id} with ${notifications.length} tasks`)

        // Update each individual notification's isTriggered status
        const updatedNotifications = notifications.map((notification) => ({
          ...notification,
          isTriggered: true,
        }))

        // Get all technicians and admins
        const [techniciansSnapshot, adminsSnapshot] = await Promise.all([
          admin.firestore().collection("Technicians").get(),
          admin.firestore().collection("Admins").get(),
        ])

        const allUserIds = [
          ...techniciansSnapshot.docs.map((doc) => doc.id),
          ...adminsSnapshot.docs.map((doc) => doc.id),
        ]

        console.log(`Sending notifications to ${allUserIds.length} users`)

        // Send notifications to all users
        for (const userId of allUserIds) {
          try {
            const userDoc = await admin.firestore().collection("Users").doc(userId).get()

            if (userDoc.exists) {
              const userData = userDoc.data()
              const fcmToken = userData.fcmToken

              const categories = [...new Set(notifications.map((n) => n.category))]
              const title = "🔧 Maintenance Reminder"
              const body = `Upcoming maintenance tasks for the following categories: ${categories.join(", ")}`

              // Send FCM notification with enhanced details
              if (fcmToken) {
                try {
                  await admin.messaging().send({
                    token: fcmToken,
                    notification: {
                      title: title,
                      body: body,
                      icon: "ic_launcher",
                    },
                    data: {
                      notificationId: doc.id,
                      type: "maintenance_reminder",
                      taskCount: notifications.length.toString(),
                      categories: categories.join(","),
                      notificationDate: data.notificationDate.toDate().toISOString(),
                      isTriggered: "true",
                      clickAction: "FLUTTER_NOTIFICATION_CLICK",
                    },
                    android: {
                      notification: {
                        channelId: "maintenance_channel",
                        priority: "high",
                        defaultSound: true,
                        defaultVibrateTimings: true,
                        sound: "default",
                        vibrationPattern: [200, 500, 200, 500],
                        color: "#3F51B5",
                        icon: "ic_launcher",
                        clickAction: "FLUTTER_NOTIFICATION_CLICK",
                      },
                      priority: "high",
                    },
                    apns: {
                      payload: {
                        aps: {
                          sound: "default",
                          badge: 1,
                          contentAvailable: true,
                        },
                      },
                      headers: {
                        "apns-priority": "10",
                      },
                    },
                    webpush: {
                      notification: {
                        icon: "ic_launcher",
                      },
                      headers: {
                        Urgency: "high",
                      },
                    },
                  })
                  console.log(`FCM sent to user ${userId}`)
                } catch (error) {
                  console.error(`Error sending FCM to ${userId}:`, error)
                }
              }
            }
          } catch (error) {
            console.error(`Error processing user ${userId}:`, error)
          }
        }

        // Mark notification as triggered with updated individual notifications
        batch.update(doc.ref, {
          isTriggered: true,
          notifications: updatedNotifications,
          triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
        })

        processedCount++
      }

      await batch.commit()
      console.log(`Successfully processed ${processedCount} notification groups`)

      return {
        success: true,
        processedCount,
        message: `Processed ${processedCount} notification groups`,
      }
    } catch (error) {
      console.error("Error in checkNotifications:", error)
      throw new functions.https.HttpsError("internal", "Failed to process notifications", error)
    }
  })
