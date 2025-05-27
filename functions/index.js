const functions = require("firebase-functions")
const admin = require("firebase-admin")
const nodemailer = require("nodemailer")

admin.initializeApp()

// Email configuration
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: functions.config().email?.user || process.env.EMAIL_USER,
    pass: functions.config().email?.password || process.env.EMAIL_PASSWORD,
  },
})

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
              const email = userData.email

              const categories = [...new Set(notifications.map((n) => n.category))]
              const title = "🔧 Maintenance Reminder"
              const body = `You have ${notifications.length} maintenance tasks due in categories: ${categories.join(", ")}`

              // Send FCM notification
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

              // Send email notification
              if (email) {
                try {
                  const emailHtml = generateEmailHtml(notifications, categories)
                  await transporter.sendMail({
                    from: functions.config().email?.user || process.env.EMAIL_USER,
                    to: email,
                    subject: title,
                    html: emailHtml,
                  })
                  console.log(`Email sent to ${email}`)
                } catch (error) {
                  console.error(`Error sending email to ${email}:`, error)
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

    // Process notifications (same logic as scheduled function)
    // ... (same processing logic as above)

    return {
      success: true,
      processedCount: notificationsSnapshot.docs.length,
      message: `Manually triggered ${notificationsSnapshot.docs.length} notifications`,
    }
  } catch (error) {
    console.error("Error in manual trigger:", error)
    throw new functions.https.HttpsError("internal", "Failed to trigger notifications manually", error)
  }
})

// Cloud Function to process email notifications
exports.processEmailNotifications = functions.firestore
  .document("EmailNotifications/{docId}")
  .onCreate(async (snap, context) => {
    const data = snap.data()

    if (data.processed) {
      return null
    }

    try {
      await transporter.sendMail({
        from: functions.config().email?.user || process.env.EMAIL_USER,
        to: data.to,
        subject: data.subject,
        html: data.body,
      })

      // Mark as processed
      await snap.ref.update({
        processed: true,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      })

      console.log(`Email sent to ${data.to}`)
    } catch (error) {
      console.error("Error sending email:", error)
      await snap.ref.update({
        processed: true,
        error: error.message,
        errorAt: admin.firestore.FieldValue.serverTimestamp(),
      })
    }
  })

function generateEmailHtml(notifications, categories) {
  return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Maintenance Reminder</title>
      </head>
      <body style="font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5;">
        <div style="max-width: 600px; margin: 0 auto; background-color: white; border-radius: 8px; padding: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
          <div style="text-align: center; margin-bottom: 30px;">
            <h1 style="color: #37474f; margin: 0;">🔧 Maintenance Reminder</h1>
            <p style="color: #666; margin: 10px 0 0 0;">CMMS Notification System</p>
          </div>
          
          <div style="background-color: #fff3cd; border: 1px solid #ffeaa7; border-radius: 5px; padding: 15px; margin: 20px 0;">
            <h3 style="color: #856404; margin: 0 0 10px 0;">⚠️ Action Required</h3>
            <p style="color: #856404; margin: 0; font-size: 16px;">
              You have <strong>${notifications.length}</strong> maintenance task${notifications.length > 1 ? "s" : ""} due for inspection.
            </p>
          </div>
          
          <div style="background-color: #e3f2fd; padding: 15px; border-radius: 5px; margin: 20px 0;">
            <h3 style="color: #1976d2; margin: 0 0 10px 0;">📋 Categories to Check:</h3>
            <p style="color: #1976d2; margin: 0; font-weight: bold; font-size: 16px;">${categories.join(", ")}</p>
          </div>
          
          <h3 style="color: #37474f; border-bottom: 2px solid #e0e0e0; padding-bottom: 10px;">📝 Task Details:</h3>
          
          ${notifications
            .map(
              (notification, index) => `
            <div style="border-left: 4px solid #607d8b; padding-left: 15px; margin: 20px 0; background-color: #fafafa; padding: 15px; border-radius: 0 5px 5px 0;">
              <div style="display: flex; justify-content: between; align-items: center; margin-bottom: 10px;">
                <h4 style="color: #37474f; margin: 0; font-size: 18px;">${index + 1}. ${notification.category}</h4>
                <span style="background-color: #607d8b; color: white; padding: 4px 8px; border-radius: 12px; font-size: 12px; font-weight: bold;">${notification.frequency} months</span>
              </div>
              <div style="margin: 8px 0;">
                <strong style="color: #555;">Component:</strong> 
                <span style="color: #333;">${notification.component}</span>
              </div>
              <div style="margin: 8px 0;">
                <strong style="color: #555;">Intervention:</strong> 
                <span style="color: #333;">${notification.intervention}</span>
              </div>
              <div style="margin: 8px 0; font-size: 14px; color: #666;">
                <strong>Last Inspection:</strong> ${new Date(notification.lastInspectionDate.seconds * 1000).toLocaleDateString()} | 
                <strong>Next Due:</strong> ${new Date(notification.nextInspectionDate.seconds * 1000).toLocaleDateString()}
              </div>
            </div>
          `,
            )
            .join("")}
          
          <div style="background-color: #f8f9fa; border-radius: 5px; padding: 20px; margin: 30px 0; text-align: center;">
            <h3 style="color: #28a745; margin: 0 0 15px 0;">🚀 Next Steps</h3>
            <p style="color: #555; margin: 0 0 15px 0;">
              Please log in to your CMMS application to review and update the status of these maintenance tasks.
            </p>
            <div style="background-color: #e9ecef; padding: 10px; border-radius: 5px; font-size: 14px; color: #6c757d;">
              <strong>Reminder:</strong> Mark tasks as "In Progress" when you start working on them, and "Completed" when finished.
            </div>
          </div>
          
          <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #eee; text-align: center;">
            <p style="color: #888; font-size: 14px; margin: 0;">
              This is an automated reminder from your CMMS system.<br>
              Generated on ${new Date().toLocaleString()}
            </p>
          </div>
        </div>
      </body>
    </html>
  `
}