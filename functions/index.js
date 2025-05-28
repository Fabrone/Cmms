const functions = require("firebase-functions")
const admin = require("firebase-admin")

admin.initializeApp()

// Cloud Function to check and trigger notifications daily at 9:00 AM
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

              // Send FCM notification only (removed email)
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
                    },
                    android: {
                      notification: {
                        channelId: "maintenance_channel",
                        priority: "high",
                        defaultSound: true,
                        defaultVibrateTimings: true,
                      },
                    },
                    apns: {
                      payload: {
                        aps: {
                          sound: "default",
                          badge: 1,
                        },
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

// Manual trigger function for testing
exports.triggerNotificationsManually = functions.https.onCall(async (data, context) => {
  // Verify the user is authenticated and has proper permissions
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated")
  }

  try {
    // Check if user is a developer
    const userDoc = await admin.firestore().collection("Developers").doc(context.auth.uid).get()
    if (!userDoc.exists) {
      throw new functions.https.HttpsError("permission-denied", "Only developers can manually trigger notifications")
    }

    // Run the same logic as the scheduled function
    const now = new Date()
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())

    const notificationsSnapshot = await admin
      .firestore()
      .collection("Notifications")
      .where("notificationDate", "<=", admin.firestore.Timestamp.fromDate(today))
      .where("isTriggered", "==", false)
      .get()

    console.log(`Manual trigger: Found ${notificationsSnapshot.docs.length} notifications`)

    const batch = admin.firestore().batch()
    let processedCount = 0

    for (const doc of notificationsSnapshot.docs) {
      const data = doc.data()
      const notifications = data.notifications || []

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

      const allUserIds = [...techniciansSnapshot.docs.map((doc) => doc.id), ...adminsSnapshot.docs.map((doc) => doc.id)]

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

            // Send FCM notification only
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
                  },
                  android: {
                    notification: {
                      channelId: "maintenance_channel",
                      priority: "high",
                      defaultSound: true,
                      defaultVibrateTimings: true,
                    },
                  },
                  apns: {
                    payload: {
                      aps: {
                        sound: "default",
                        badge: 1,
                      },
                    },
                  },
                })
                console.log(`Manual FCM sent to user ${userId}`)
              } catch (error) {
                console.error(`Error sending manual FCM to ${userId}:`, error)
              }
            }
          }
        } catch (error) {
          console.error(`Error processing user ${userId}:`, error)
        }
      }

      // Mark notification as triggered
      batch.update(doc.ref, {
        isTriggered: true,
        notifications: updatedNotifications,
        triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
      })

      processedCount++
    }

    await batch.commit()

    return {
      success: true,
      processedCount: processedCount,
      message: `Manually triggered ${processedCount} notifications`,
    }
  } catch (error) {
    console.error("Error in manual trigger:", error)
    throw new functions.https.HttpsError("internal", "Failed to trigger notifications manually", error)
  }
})

// Test notification function
exports.sendTestNotification = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated")
  }

  try {
    const userDoc = await admin.firestore().collection("Users").doc(context.auth.uid).get()

    if (userDoc.exists) {
      const userData = userDoc.data()
      const fcmToken = userData.fcmToken

      if (fcmToken) {
        await admin.messaging().send({
          token: fcmToken,
          notification: {
            title: "🔧 Test Maintenance Reminder",
            body: "This is a test notification for maintenance tasks.",
            icon: "ic_launcher",
          },
          data: {
            type: "test_notification",
            timestamp: new Date().toISOString(),
          },
          android: {
            notification: {
              channelId: "maintenance_channel",
              priority: "high",
              defaultSound: true,
              defaultVibrateTimings: true,
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: 1,
              },
            },
          },
        })

        return {
          success: true,
          message: "Test notification sent successfully",
        }
      } else {
        throw new functions.https.HttpsError("failed-precondition", "No FCM token found for user")
      }
    } else {
      throw new functions.https.HttpsError("not-found", "User not found")
    }
  } catch (error) {
    console.error("Error sending test notification:", error)
    throw new functions.https.HttpsError("internal", "Failed to send test notification", error)
  }
})
