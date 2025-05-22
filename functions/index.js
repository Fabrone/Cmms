const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.sendMaintenanceNotification = functions.https.onCall(async (data) => {
  const { token, title, body, taskId, facilityId, screen } = data;

  const message = {
    token,
    notification: { title, body },
    data: { taskId, facilityId, screen },
    android: {
      notification: { channelId: "maintenance_reminders" }
    },
    webpush: {
      notification: { icon: "/favicon.png" }
    }
  };

  try {
    await admin.messaging().send(message);
    return { result: "Message sent" };
  } catch (error) {
    console.error("Error sending message:", error);
    return { error: error.message };
  }
});
