const {
  onRequest,
  onCall,
  HttpsError,
} = require("firebase-functions/v2/https");
// Imports the Firebase v2 HTTPS helpers.
// onCall: for callable functions directly invoked from the app.
// onRequest: for normal HTTP endpoints.
// HttpsError: sends structured errors back to the client.

const { defineSecret } = require("firebase-functions/params");
// Used to access secrets securely from Firebase Secret Manager instead of hardcoding sensitive values inside the source code.

const OpenAI = require("openai");
// OpenAI SDK used in this file for: classifying sensor notifications and answering assistant questions inside the app

const nodemailer = require("nodemailer");
// Nodemailer is used to send verification emails from the backend.

const admin = require("firebase-admin");
// Firebase Admin SDK gives privileged backend access to: Authentication and Firestore

admin.initializeApp();
// Initializes the Admin SDK once before any Firebase service is used.

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
// Secure OpenAI API key stored outside the source code.

const EMAIL_PASSWORD = defineSecret("EMAIL_PASSWORD");
// Secure sender-email password stored outside the source code.

const RESET_EMAIL_USER = "alerts@kuhomesafe.com";
// Main system email identity used for password reset messages.

function createTransporter() {
  // Creates and returns a reusable SMTP transporter.
  // Keeping this in one function avoids repeating the same config.
  return nodemailer.createTransport({
    host: "mail.privateemail.com",
    // SMTP server used to send outgoing mail.

    port: 587,
    // Standard submission port for TLS-based email sending.

    secure: false,
    // false because port 587 typically starts unsecured
    // and upgrades with STARTTLS.

    auth: {
      user: RESET_EMAIL_USER,
      // Email account that sends the message.

      pass: EMAIL_PASSWORD.value(),
      // Password is pulled securely at runtime from Secret Manager.
    },
  });
}

function isValidEmail(email) {
  // Simple format check before hitting Firebase Auth or Firestore.
  // This avoids unnecessary backend work for obviously invalid input.
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email || "").trim());
}

function generateCode() {
  // Generates a random 6-digit verification code.
  // The chosen math range guarantees the result is always 6 digits.
  return Math.floor(100000 + Math.random() * 900000).toString();
}

exports.sendResetCode = onCall(
  {
    secrets: [EMAIL_PASSWORD],
    // This callable function is allowed to access the email password secret.

    cors: true,
    // Enables cross-origin access for frontend calls if needed.
  },
  async (request) => {
    const { email } = request.data || {};
    // Pulls email from the request body sent by the app.

    const safeEmail = String(email || "").trim().toLowerCase();
    // Normalizes the email input: converts to string safely, removes surrounding spaces, lowercases it for consistent comparisons

    if (!safeEmail) {
      // Stops the flow immediately if email is missing.
      throw new HttpsError("invalid-argument", "Email is required");
    }

    if (!isValidEmail(safeEmail)) {
      // Rejects invalid email format before any database/auth lookup.
      throw new HttpsError("invalid-argument", "Enter a valid email");
    }

    try {
      // Checks whether this email actually belongs to a Firebase Auth user.
      // This keeps the reset process tied only to real accounts.
      await admin.auth().getUserByEmail(safeEmail);
    } catch (error) {
      // If no user exists with that email, the reset flow is blocked.
      throw new HttpsError("not-found", "No account found for this email");
    }

    const code = generateCode();
    // Fresh one-time verification code.

    const now = Date.now();
    // Current time in milliseconds.

    const expiresAtMs = now + 10 * 60 * 1000;
    // Code expiration set to 10 minutes after generation.
    // This limits the time window for misuse.

    await admin.firestore().collection("password_resets").add({
      // Stores the reset request in Firestore so later steps
      // can verify the code and track whether it was used.
      email: safeEmail,
      code,
      used: false,
      // Remains false until password is actually changed.

      verified: false,
      // Remains false until the user enters the correct code.

      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      // Uses server time instead of client time for consistency and trust.

      expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMs),
      // Stored expiration timestamp used later during verification/reset.
    });

    const transporter = createTransporter();
    // Creates the email sender connection only after the reset record exists.

    await transporter.sendMail({
      // Sends the actual verification email to the user.
      from: `"Safe Home Monitor" <${RESET_EMAIL_USER}>`,
      to: safeEmail,
      subject: "Your verification code",
html: `
<div style="background:#0D1B2A; padding:0; margin:0; font-family:Arial, sans-serif;">

  <div style="max-width:600px; margin:0 auto;">

    <!-- HEADER -->
    <div style="background:#0D1B2A; padding:18px; text-align:center;">
      <span style="color:#ffffff; font-size:20px; font-weight:600;">
        Safe Home Monitor
      </span>
    </div>

    <!-- BODY -->
    <div style="background:#1f2937; padding:30px 20px; text-align:center;">

      <p style="color:#ffffff; font-size:16px; margin-bottom:20px;">
        Your password reset verification code is:
      </p>

      <!-- CODE BOX -->
      <div style="
        background:#4A90E2;
        color:#000000;
        font-size:30px;
        font-weight:bold;
        letter-spacing:6px;
        padding:15px 25px;
        border-radius:12px;
        display:inline-block;
        margin-bottom:20px;
      ">
        ${code}
      </div>

      <p style="color:#d1d5db; font-size:14px;">
        This code will expire in 2 minutes
      </p>

      <p style="color:#9ca3af; font-size:13px; margin-top:10px;">
        If you didn't request this, you can ignore this email
      </p>

    </div>

  </div>

</div>
`
    });

    return {
      success: true,
      // Lets the frontend know the email was sent successfully.

      message: "Verification code sent",
    };
  }
);

exports.verifyResetCode = onCall(
  {
    cors: true,
    // Callable from the app during the "enter code" step.
  },
  async (request) => {
    const { email, code } = request.data || {};
    // Reads both values entered by the user in the reset flow.

    const safeEmail = String(email || "").trim().toLowerCase();
    // Normalized email.

    const safeCode = String(code || "").trim();
    // Normalized code string.

    if (!safeEmail || !safeCode) {
      // Both email and code are required to verify a reset request.
      throw new HttpsError("invalid-argument", "Email and code are required");
    }

    const snap = await admin
      .firestore()
      .collection("password_resets")
      .where("email", "==", safeEmail)
      // Must match the same email.

      .where("code", "==", safeCode)
      // Must match the exact code entered by the user.

      .where("used", "==", false)
      // Ignores codes that were already used.

      .limit(1)
      // Only one matching document is needed.

      .get();

    if (snap.empty) {
      // No matching unused reset request means the code is invalid.
      throw new HttpsError("not-found", "Invalid verification code");
    }

    const doc = snap.docs[0];
    // First matching Firestore document.

    const data = doc.data();
    // Reads its stored fields.

    const expiresAtMs = data.expiresAt?.toMillis?.() || 0;
    // Safely converts Firestore timestamp into milliseconds.

    if (Date.now() > expiresAtMs) {
      // Stops verification if the code has already expired.
      throw new HttpsError("deadline-exceeded", "Verification code expired");
    }

    await doc.ref.update({
      // Marks this reset request as verified.
      // Password reset step depends on this flag.
      verified: true,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      // Server-side time of successful verification.
    });

    return {
      success: true,
      message: "Code verified",
    };
  }
);

exports.resetPasswordWithCode = onCall(
  {
    cors: true,
    // Callable endpoint for the final reset-password step.
  },
  async (request) => {
    const { email, newPassword } = request.data || {};
    // Receives the email and the replacement password.

    const safeEmail = String(email || "").trim().toLowerCase();
    // Normalized email.

    const safePassword = String(newPassword || "");
    // Ensures password is safely handled as a string.

    if (!safeEmail || !safePassword) {
      // Both inputs are required to continue.
      throw new HttpsError(
        "invalid-argument",
        "Email and new password are required"
      );
    }

    if (safePassword.length < 6) {
      // Backend validation for minimum password length.
      // Important because client-side validation alone is not enough.
      throw new HttpsError(
        "invalid-argument",
        "Password must be at least 6 characters"
      );
    }

    const snap = await admin
      .firestore()
      .collection("password_resets")
      .where("email", "==", safeEmail)
      // Must belong to this email.

      .where("used", "==", false)
      // Must not have been used yet.

      .where("verified", "==", true)
      // Must already be verified before reset is allowed.

      .limit(1)
      .get();

    if (snap.empty) {
      // If no verified pending request exists, the flow order was not completed.
      throw new HttpsError(
        "failed-precondition",
        "Verification code has not been confirmed"
      );
    }

    const doc = snap.docs[0];
    const data = doc.data();
    const expiresAtMs = data.expiresAt?.toMillis?.() || 0;

    if (Date.now() > expiresAtMs) {
      // Even verified codes cannot be used after their expiration time.
      throw new HttpsError("deadline-exceeded", "Verification code expired");
    }

    let user;
    try {
      // Looks up the actual Firebase Auth account before changing password.
      user = await admin.auth().getUserByEmail(safeEmail);
    } catch (error) {
      // Handles the case where the account no longer exists.
      throw new HttpsError("not-found", "No account found for this email");
    }

    await admin.auth().updateUser(user.uid, {
      // Updates the password directly in Firebase Authentication.
      password: safePassword,
    });

    await doc.ref.update({
      // Marks this reset request as consumed so it cannot be reused later.
      used: true,
      usedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      message: "Password reset successfully",
    };
  }
);

exports.analyzeSensorData = onRequest(
  {
    secrets: [OPENAI_API_KEY],
    // This HTTP endpoint needs the OpenAI key to classify notifications.

    cors: true,
  },
  async (req, res) => {
    if (req.method === "OPTIONS") {
      // Handles CORS preflight requests from browser-based clients.
      res.status(204).send("");
      return;
    }

    if (req.method !== "POST") {
      // Only POST is valid because the endpoint expects a request body.
      return res.status(405).json({
        error: "Method not allowed. Use POST.",
      });
    }

    try {
      const {
        title,
        message,
        type,
        timestamp,
        count,
        sensorValue,
        durationMinutes,
        motion,
        inactivityMinutes,
        door,
        vibration,
      } = req.body || {};
      // Pulls all incoming sensor/notification-related data from the request.

      const safeTitle = (title ?? "").toString();
      // Ensures title is always treated as text.

      const safeMessage = (message ?? "").toString();
      // Ensures message is always treated as text.

      const safeType = (type ?? "").toString().toLowerCase();
      // Normalizes the type value for consistent prompt wording.

      const safeTimestamp = Number(timestamp ?? 0);
      // Converts timestamp to a number safely.

      const safeCount = Number(count ?? 0);
      // Converts count to a number safely.

      const safeSensorValue = Number(sensorValue ?? 0);
      // Converts sensor value to a number safely.

      const safeDurationMinutes = Number(
        durationMinutes ?? inactivityMinutes ?? 0
      );
      // Uses durationMinutes if available.
      // Falls back to inactivityMinutes when that is the relevant value.

      const safeMotion =
        typeof motion === "boolean" ? motion : String(motion ?? "");
      // Keeps motion as boolean when possible, otherwise converts safely to text.

      const safeDoor =
        typeof door === "boolean" ? door : String(door ?? "");
      // Same normalization for door state.

      const safeVibration =
        typeof vibration === "boolean" ? vibration : String(vibration ?? "");
      // Same normalization for vibration state.

      const client = new OpenAI({
        apiKey: OPENAI_API_KEY.value(),
        // Reads the OpenAI key securely at runtime.
      });

      const prompt = `
You are classifying elderly home-monitoring notifications.

Your job:
Classify each notification into exactly ONE of these app labels:
- Critical
- Normal
- Low Attention

Rules:
- Critical = immediate danger or urgent caregiver attention needed
- Normal = should be checked, but not immediate danger
- Low Attention = harmless update, low urgency

Notification data:
title: ${safeTitle}
message: ${safeMessage}
type: ${safeType}
timestamp: ${safeTimestamp}
count: ${safeCount}
sensorValue: ${safeSensorValue}
durationMinutes: ${safeDurationMinutes}

motion: ${safeMotion}
door: ${safeDoor}
vibration: ${safeVibration}

Return ONLY valid JSON:
{
  "label": "Critical" or "Normal" or "Low Attention",
  "reason": "very short reason"
}
`;
      // This prompt forces the model into your app’s label system.
      // The return format is tightly controlled so the frontend can parse it easily.

      const response = await client.responses.create({
        model: "gpt-5.4",
        // Model used for classification.

        input: prompt,
      });

      const text = (response.output_text || "").trim();
      // Pulls the generated text safely from the OpenAI response.

      let parsed;
      try {
        parsed = JSON.parse(text);
        // Best-case scenario: the model returned valid JSON directly.
      } catch (e) {
        const cleaned = text.match(/\{[\s\S]*\}/);
        // Fallback: extracts the JSON object if extra text appears around it.

        if (cleaned) {
          parsed = JSON.parse(cleaned[0]);
        } else {
          parsed = null;
          // Final fallback when no valid JSON can be recovered.
        }
      }

      let label = "Normal";
      // Default label if parsing fails or output is incomplete.

      let reason = "Needs review";
      // Default reason so the app always gets something usable back.

      if (parsed && typeof parsed === "object") {
        const rawLabel = (parsed.label ?? "").toLowerCase();
        // Normalizes returned label for controlled mapping.

        const rawReason = (parsed.reason ?? "").toString();
        // Reads reason as text safely.

        if (rawLabel === "critical") label = "Critical";
        else if (rawLabel === "low attention") label = "Low Attention";
        // Any other value stays as "Normal" by default.

        if (rawReason) reason = rawReason;
        // Uses the AI reason only when it exists.
      }

      return res.status(200).json({ label, reason });
      // Sends the cleaned final classification back to the app.
    } catch (error) {
      console.error("analyzeSensorData error:", error);
      // Backend logging for debugging.

      return res.status(500).json({
        error: error.message || "Unknown server error",
        // Safe error response for the client.
      });
    }
  }
);

exports.askAssistant = onRequest(
  {
    secrets: [OPENAI_API_KEY],
    // This endpoint also uses OpenAI, so it needs the same secret.

    cors: true,
  },
  async (req, res) => {
    if (req.method === "OPTIONS") {
      // Handles browser preflight CORS checks.
      res.status(204).send("");
      return;
    }

    if (req.method !== "POST") {
      // This endpoint only accepts POST because it expects message/context data.
      return res.status(405).json({
        error: "Method not allowed. Use POST.",
      });
    }

    try {
      const { message, appContext, chatHistory } = req.body || {};
      // Reads the user's question plus current app state/context.

      if (!message || !message.toString().trim()) {
        // Prevents empty assistant calls.
        return res.status(400).json({
          error: "Message is required.",
        });
      }

      const safeHistory = Array.isArray(chatHistory)
        ? chatHistory
            .slice(-6)
            // Keeps only the last few messages to control prompt size.

            .map((item) => {
              const role =
                item && item.role === "assistant" ? "assistant" : "user";
              // Limits role values to expected ones only.

              const text = (item && item.text ? item.text : "").toString();
              // Safely extracts message text.

              return `${role}: ${text}`;
            })
            .join("\n")
        : "";
      // Produces a short text history that can be inserted into the prompt.

      const safeContext =
        appContext && typeof appContext === "object" ? appContext : {};
      // Makes sure appContext is a usable object before reading from it.

      const realtime = safeContext.realtime || {};
      // Live sensor/system status.

      const logicSummary = safeContext.logicSummary || {};
      // Precomputed overall safety logic.

      const caregiver = safeContext.caregiver || {};
      // Caregiver info if present.

      const monitoredPerson = safeContext.monitoredPerson || {};
      // Monitored person details.

      const emergencyContact = safeContext.emergencyContact || {};
      // Emergency contact details.

      const settings = safeContext.settings || {};
      // App/user settings.

      const recentNotifications = Array.isArray(safeContext.recentNotifications)
        ? safeContext.recentNotifications
        : [];
      // Recent notifications used when the assistant is asked what happened.

      const client = new OpenAI({
        apiKey: OPENAI_API_KEY.value(),
        // Secure OpenAI key access at runtime.
      });

      const prompt = `
You are the AI assistant for Safe Home Monitor.

IMPORTANT:
You must follow the live calculated app logic exactly.
Do NOT invent your own sensor logic.
Do NOT say something is safe if the calculated live logic says attention is needed.

Live calculated context:
${JSON.stringify(
  {
    caregiver,
    monitoredPerson,
    emergencyContact,
    settings,
    realtime,
    logicSummary,
    recentNotifications,
  },
  null,
  2
)}

Strict sensor logic:
- If logicSummary.overallStatus is "Attention Needed", do not describe the home as safe.
- If realtime.alarmOn is true, say the alarm is active.
- If realtime.emergencyOn is true, say emergency calling is active.
- If realtime.motion.isEmergency is true, say no motion has been detected for 1 minute.
- If realtime.door.isEmergency is true, say the door is open.
- If realtime.vibration.isEmergency is true, say vibration is detected.
- If realtime.temperature.isEmergency is true, say temperature has stayed outside the normal range too long.
- If realtime.temperature.warning is true, say temperature is outside the normal range.
- If realtime.pressure.isEmergency is true, say pressure has continued for 1 minute.
- If realtime.cameraOnline is false and relevant, mention that the camera is offline.
- If overallStatus is "Safe", then and only then say the home is currently safe.

Answering style:
- neat sentences
- calm and clear
- 1 to 4 short sentences usually
- mention the most important problem first
- then the most useful next step
- do not dump raw JSON
- do not say "based on the provided data"
- do not contradict the live calculated logic
- if asked about profile, monitored person, caregiver, emergency contact, or settings, answer from the context
- if asked what happened recently, use recentNotifications
- if asked what is happening now, use realtime and logicSummary first

Recent chat:
${safeHistory || "No previous chat."}

User question:
${message}

Write the reply now.
`;
      // This prompt is carefully designed so the assistant does NOT invent logic.
      // It must obey the app’s already-calculated live status and wording rules.

      const response = await client.responses.create({
        model: "gpt-5.4",
        // Same model used here for assistant responses.

        input: prompt,
      });

      return res.status(200).json({
        reply: (response.output_text || "No reply").trim(),
        // Sends the final cleaned assistant reply back to the app.
      });
    } catch (error) {
      console.error("askAssistant error:", error);
      // Logs backend errors for debugging.

      return res.status(500).json({
        error: error.message || "Unknown server error",
        // Safe generic error response for frontend use.
      });
    }
  }
);