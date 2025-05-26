const functions = require("firebase-functions")
const admin = require("firebase-admin")
const nodemailer = require("nodemailer")

admin.initializeApp()

// Email configuration (you'll need to set these up in Firebase Functions config)
const transporter = nodemailer.createTransporter({
  service: "gmail", // or your email service
  auth: {
    user: functions.config().email.user,
    pass: functions.config().email.password,
  },
})

// Cloud Function to check and trigger notifications daily
exports.checkNotifications = functions.pubsub
  .schedule("0 9 * * *") // Run daily at 9 AM
  .timeZone("UTC")
  .onRun(async (context) => {
    const now = new Date()
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())

    try {
      // Get due notifications
      const notificationsSnapshot = await admin
        .firestore()
        .collection("Notifications")
        .where("notificationDate", "<=", admin.firestore.Timestamp.fromDate(today))
        .where("isTriggered", "==", false)
        .get()

      const batch = admin.firestore().batch()

      for (const doc of notificationsSnapshot.docs) {
        const data = doc.data()
        const notifications = data.notifications || []

        // Update each individual notification's isTriggered status
        const updatedNotifications = notifications.map((notification) => ({
          ...notification,
          isTriggered: true,
        }))

        // Get technician tokens and emails
        const techniciansSnapshot = await admin.firestore().collection("Technicians").get()
        const technicianIds = techniciansSnapshot.docs.map((doc) => doc.id)

        for (const technicianId of technicianIds) {
          const userDoc = await admin.firestore().collection("Users").doc(technicianId).get()

          if (userDoc.exists) {
            const userData = userDoc.data()
            const fcmToken = userData.fcmToken
            const email = userData.email

            const categories = [...new Set(notifications.map((n) => n.category))]
            const title = "Maintenance Reminder"
            const body = `You have ${notifications.length} maintenance tasks due in categories: ${categories.join(", ")}`

            // Send FCM notification
            if (fcmToken) {
              try {
                await admin.messaging().send({
                  token: fcmToken,
                  notification: {
                    title: title,
                    body: body,
                  },
                  data: {
                    notificationId: doc.id,
                    type: "maintenance_reminder",
                    taskCount: notifications.length.toString(),
                  },
                })
                console.log(`FCM sent to ${technicianId}`)
              } catch (error) {
                console.error(`Error sending FCM to ${technicianId}:`, error)
              }
            }

            // Send email notification
            if (email) {
              try {
                const emailHtml = generateEmailHtml(notifications, categories)
                await transporter.sendMail({
                  from: functions.config().email.user,
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
        }

        // Mark notification as triggered with updated individual notifications
        batch.update(doc.ref, {
          isTriggered: true,
          notifications: updatedNotifications,
        })
      }

      await batch.commit()
      console.log(`Processed ${notificationsSnapshot.docs.length} notification groups`)
    } catch (error) {
      console.error("Error in checkNotifications:", error)
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
        from: functions.config().email.user,
        to: data.to,
        subject: data.subject,
        text: data.body,
      })

      // Mark as processed
      await snap.ref.update({ processed: true })

      console.log(`Email sent to ${data.to}`)
    } catch (error) {
      console.error("Error sending email:", error)
      await snap.ref.update({
        processed: true,
        error: error.message,
      })
    }
  })

function generateEmailHtml(notifications, categories) {
  return `
    <html>
      <body style="font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5;">
        <div style="max-width: 600px; margin: 0 auto; background-color: white; border-radius: 8px; padding: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
          <h2 style="color: #37474f; margin-bottom: 20px;">🔧 Maintenance Reminder</h2>
          
          <p style="color: #555; font-size: 16px;">
            You have <strong>${notifications.length}</strong> maintenance tasks due for inspection.
          </p>
          
          <div style="background-color: #e3f2fd; padding: 15px; border-radius: 5px; margin: 20px 0;">
            <h3 style="color: #1976d2; margin: 0 0 10px 0;">Categories to Check:</h3>
            <p style="color: #1976d2; margin: 0; font-weight: bold;">${categories.join(", ")}</p>
          </div>
          
          <h3 style="color: #37474f;">Task Details:</h3>
          
          ${notifications
            .map(
              (notification) => `
            <div style="border-left: 4px solid #607d8b; padding-left: 15px; margin: 15px 0;">
              <h4 style="color: #37474f; margin: 0 0 5px 0;">${notification.category}</h4>
              <p style="margin: 5px 0; color: #666;"><strong>Component:</strong> ${notification.component}</p>
              <p style="margin: 5px 0; color: #666;"><strong>Intervention:</strong> ${notification.intervention}</p>
              <p style="margin: 5px 0; color: #666;"><strong>Frequency:</strong> ${notification.frequency} months</p>
            </div>
          `,
            )
            .join("")}
          
          <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #eee;">
            <p style="color: #888; font-size: 14px; margin: 0;">
              This is an automated reminder from your CMMS system. Please log in to mark tasks as completed.
            </p>
          </div>
        </div>
      </body>
    </html>
  `
}