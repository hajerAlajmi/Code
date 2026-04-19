// Imports
// Packages and project files used by this screen.
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'notifications_screen.dart';

// AssistantPage
// Main widget/class definition for this part of the app.


// This screen works like an in-app assistant/chat page.
// It receives live values from the previous screen, also refreshes current Firebase data, then sends the combined app context to the backend assistant API.
class AssistantPage extends StatefulWidget {
 
// Current status passed into the page.
  final bool motion;
  final String door;
  final bool vibration;
  final double temperature;
  final String systemStatus;
  final String motionNote;
  final String doorNote;
  final String vibrationNote;
  final String temperatureNote;
  final int noMotionMinutes;

  // Whether pressure is currently detected.
  final bool pressureDetected;
  
  // Human-readable note about pressure.
  final String pressureNote;
  
  // Minutes that pressure has continued.
  final int pressureMinutes;
  
  // Whether alarm is currently active.
  final bool alarmOn;
  
  // Whether camera is currently online.
  final bool cameraOnline;
  
  // Readable text for last sync time.
  final String lastSyncText;
  
  // Name of the current page or source screen.
  final String currentPage;

  // Extra live context map passed in from outside if needed.
  final Map<String, dynamic> liveContext;

  const AssistantPage({
    super.key,
    required this.motion,
    required this.door,
    required this.vibration,
    required this.temperature,
    required this.systemStatus,
    required this.motionNote,
    required this.doorNote,
    required this.vibrationNote,
    required this.temperatureNote,
    required this.noMotionMinutes,
    required this.pressureDetected,
    required this.pressureNote,
    required this.pressureMinutes,
    required this.alarmOn,
    required this.cameraOnline,
    required this.lastSyncText,
    required this.currentPage,
    required this.liveContext,
  });

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

// _AssistantPageState
// Main widget/class definition for this part of the app.

// State class that holds live values, controllers, and UI logic for the screen.
class _AssistantPageState extends State<AssistantPage> {
// Color theme used across this screen to keep the UI consistent.
  static const Color softBlue = Color(0xFF4A90E2);
  static const Color navy = Color(0xFF0D1B2A);
// Color theme used across this screen to keep the UI consistent.
  static const Color pageBg = Color(0xFFF7F9FC);

// Stores all chat messages shown in the conversation area.
// This includes both user messages and assistant replies.
  final List<_ChatMsg> _messages = [];
   
// Controllers for scrolling and message input.
  final ScrollController _scroll = ScrollController();
// Text controllers used by form fields and input boxes.
  final TextEditingController _controller = TextEditingController();


// Firebase database references used to read or update live data.
// These point to the realtime database nodes used by the app.
  final DatabaseReference _sensorsDb = FirebaseDatabase.instance.ref('sensors');
  final DatabaseReference _systemDb = FirebaseDatabase.instance.ref('system');
  final DatabaseReference _emergencyDb =
      FirebaseDatabase.instance.ref('emergency');

// Indicates whether the assistant is currently waiting for a reply.
// Used to disable input and show the "Thinking..." bubble.
  bool _isThinking = false;

// Timers used for periodic refresh or live updates.
// This timer keeps refreshing live context every second.
  Timer? _liveTicker;

// Stores the last known timestamp when motion was seen.
// Used to calculate inactivity duration.
  int _lastMotionSeenMs = 0;
  
// Stores the timestamp when pressure started.
// Used to calculate how long pressure continues.
  int _pressureStartMs = 0;

// Stores the latest sync timestamp from the most recent snapshot.
  int _lastSnapshotSyncMs = 0;

// Used to compare whether the live snapshot changed from the previous one.
  String _lastSnapshotKey = '';


// Full app context that will be sent to the assistant backend.
// This contains caregiver info, monitored person data, realtime status, settings, etc.
  Map<String, dynamic> _liveAssistantContext = {};
  
    // Whether live data has been loaded at least once.
  bool _liveReady = false;


// Backend endpoint that handles assistant questions.
  final String _apiUrl = "https://askassistant-fktio5l7wa-uc.a.run.app";


// Predefined quick action buttons shown below the chat input.
// These allow the user to ask common questions with one tap.
  final List<_QuickAction> _quickActions = const [
    _QuickAction("Daily Summary", "daily_summary", Icons.today),
    _QuickAction(
      "Explain Last Alert",
      "explain_last_alert",
      Icons.notifications_active_outlined,
    ),
    _QuickAction(
      "Current Status",
      "current_status",
      Icons.monitor_heart_outlined,
    ),
    _QuickAction("What should I do now?", "what_to_do_now", Icons.help_outline),
    _QuickAction("Safety Tips", "safety_tips", Icons.shield_outlined),
  ];

// Runs once when this screen starts and prepares initial state.
  @override
  void initState() {
    super.initState();

// Add the first assistant greeting message when the page opens.
// This gives the user immediate guidance about what the assistant can answer.
    _messages.add(
      _ChatMsg(
        role: _Role.assistant,
        text:
            "Hi! I can help with live home status, alerts, recent activity, caregiver details, and monitored person details.",
        time: DateTime.now(),
      ), //_ChatMsg
    );
  // Load the latest live context immediately.
    _refreshLiveContext();

// Refresh the live context every second so the assistant uses fresh values.
// silent: true means it updates in the background without forcing the loading banner again.
    _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshLiveContext(silent: true);
    }); //Timer.periodic
  }

// Releases resources here to avoid memory leaks.
  @override
  void dispose() {
// Cancel periodic refresh timer when screen is removed.
    _liveTicker?.cancel();

// Dispose controllers to free memory properly.
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }


// Internal helper method for the screen logic.
// This method gathers the latest realtime database values, reads user profile details from Firestore,
// derives status logic (safe/warning/emergency), and builds one combined context object for the assistant.
  Future<void> _refreshLiveContext({bool silent = false}) async {
    try {

      // Get current signed-in user.
      // Needed to fetch caregiver/patient information from Firestore.
      final user = FirebaseAuth.instance.currentUser;


// Read current values from Realtime Database.
// These are the raw live values coming from the sensors/system.
      final sensorsSnap = await _sensorsDb.get();
      final systemSnap = await _systemDb.get();
      final emergencySnap = await _emergencyDb.get();

      // This map will hold user profile data if it exists.
      Map<String, dynamic> userData = {};
     
       // If a user is logged in, load their Firestore profile document.
      if (user != null) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          final rawUser = doc.data();
          // Convert Firestore data into a regular map for easier access.
          if (rawUser != null) {
            userData = Map<String, dynamic>.from(rawUser);
          }
        } catch (_) {}
      }

      // Raw snapshot values from the realtime database.
      final sensorsRaw = sensorsSnap.value;
      final systemRaw = systemSnap.value;
      final emergencyRaw = emergencySnap.value;


 // Safely convert raw values into maps.
// If any node is missing or not a map, use an empty fallback map.
      final sensors = sensorsRaw is Map
          ? Map<String, dynamic>.from(sensorsRaw)
          : <String, dynamic>{};

      final system = systemRaw is Map
          ? Map<String, dynamic>.from(systemRaw)
          : <String, dynamic>{};

      final emergency = emergencyRaw is Map
          ? Map<String, dynamic>.from(emergencyRaw)
          : <String, dynamic>{};

// Extract each sensor section as its own map.
// This makes the rest of the logic cleaner and easier to read.
      final motionMap = sensors['motion'] is Map
          ? Map<String, dynamic>.from(sensors['motion'])
          : <String, dynamic>{};

      final doorMap = sensors['door'] is Map
          ? Map<String, dynamic>.from(sensors['door'])
          : <String, dynamic>{};

      final vibrationMap = sensors['vibration'] is Map
          ? Map<String, dynamic>.from(sensors['vibration'])
          : <String, dynamic>{};

      final temperatureMap = sensors['temperature'] is Map
          ? Map<String, dynamic>.from(sensors['temperature'])
          : <String, dynamic>{};

      final pressure1Map = sensors['pressure1'] is Map
          ? Map<String, dynamic>.from(sensors['pressure1'])
          : <String, dynamic>{};

      final pressure2Map = sensors['pressure2'] is Map
          ? Map<String, dynamic>.from(sensors['pressure2'])
          : <String, dynamic>{};

      final cameraMap = sensors['camera'] is Map
          ? Map<String, dynamic>.from(sensors['camera'])
          : <String, dynamic>{};


// Normalize motion status.
// The raw status text is converted to lowercase to avoid case issues.
      final String motionStatus =
          (motionMap['status'] ?? '').toString().toLowerCase();
      
  // Motion is considered active only when the status says "detected".
      final bool motionDetected = motionStatus == 'detected';

// Read raw door status.
// Default is "closed" if the field is missing.
      final String rawDoorStatus =
          (doorMap['status'] ?? 'closed').toString().toLowerCase();


 // Convert door status into the app's expected meaning.
// This code intentionally flips some values because of the sensor logic wiring.
      String door = 'closed';
      if (rawDoorStatus == 'open') {
        door = 'closed';
      } else if (rawDoorStatus == 'closed') {
        door = 'open';
      } else if (rawDoorStatus == 'detected') {
        door = 'closed';
      } else if (rawDoorStatus == 'not detected') {
        door = 'open';
      } else {
        door = rawDoorStatus;
      }
      // Normalize vibration status and derive a boolean flag.
      final String vibrationStatus =
          (vibrationMap['status'] ?? '').toString().toLowerCase();
      final bool vibrationDetected = vibrationStatus == 'detected';

// Read temperature using several possible field names.
// fallback: 36.8 is used if no valid value is found.
      final double temperature = _asDouble(
        temperatureMap['celsius'] ??
            temperatureMap['value'] ??
            temperatureMap['bodyTemp'],
        fallback: 36.8,
      );

      // Read the pressure sensor statuses.
      final String p1Status =
          (pressure1Map['status'] ?? '').toString().toLowerCase();
      final String p2Status =
          (pressure2Map['status'] ?? '').toString().toLowerCase();
       // Pressure is considered detected if either pressure sensor is pressed.
      final bool pressureDetected =
          p1Status == 'pressed' || p2Status == 'pressed';

      // Current time in milliseconds.
      final int nowMs = DateTime.now().millisecondsSinceEpoch;


// Find the most reliable timestamp for motion events.
// The helper picks the first valid positive timestamp from the list.
      final int motionTimestamp = _firstPositiveInt([
        motionMap['lastDetected'],
        motionMap['detectedAt'],
        motionMap['timestamp'],
        motionMap['lastUpdated'],
      ]);


// Update the last known motion timestamp.
// If motion is currently detected, use the latest valid timestamp or now.
      if (motionDetected) {
        _lastMotionSeenMs = motionTimestamp > 0 ? motionTimestamp : nowMs;
      } else {

        // If motion is not currently detected, keep the previous last seen time.
        // But if it was never set before and a timestamp exists, initialize it.
        if (_lastMotionSeenMs == 0 && motionTimestamp > 0) {
          _lastMotionSeenMs = motionTimestamp;
        }
      }

      // Track when pressure started.
      if (pressureDetected) {
        if (_pressureStartMs == 0) {
          final int pressureTimestamp = _firstPositiveInt([
            pressure1Map['pressedAt'],
            pressure1Map['startTime'],
            pressure1Map['startedAt'],
            pressure1Map['timestamp'],
            pressure1Map['lastUpdated'],
            pressure2Map['pressedAt'],
            pressure2Map['startTime'],
            pressure2Map['startedAt'],
            pressure2Map['timestamp'],
            pressure2Map['lastUpdated'],
          ]);

          // If no valid timestamp exists, use the current time.
          _pressureStartMs = pressureTimestamp > 0 ? pressureTimestamp : nowMs;
        }
      } else {
                // Reset pressure timer when pressure is no longer detected.
        _pressureStartMs = 0;
      }

 // Timestamp for temperature state changes.
// Used to calculate how long the temperature has been out of range.
      final int temperatureStateMs = _firstPositiveInt([
        temperatureMap['lastDetected'],
        temperatureMap['lastUpdated'],
        temperatureMap['timestamp'],
      ]);

// Timestamp for camera activity.
 // Used to determine whether the camera is considered online.
      final int cameraLastSeen = _firstPositiveInt([
        cameraMap['lastSeen'],
        cameraMap['lastUpdated'],
        cameraMap['timestamp'],
      ]);

// Camera is considered online only if it was seen recently.
// Here the threshold is 10 seconds.
      final bool cameraOnline =
          cameraLastSeen > 0 && (nowMs - cameraLastSeen) <= 10000;

// Create a compact snapshot key from the important live values.
// This helps detect whether anything changed since the last refresh.
      final String snapshotKey = [
        motionStatus,
        rawDoorStatus,
        vibrationStatus,
        temperature.toStringAsFixed(1),
        p1Status,
        p2Status,
        cameraOnline.toString(),
        _asBool(system['alarmOn']).toString(),
      ].join('|');

      // First snapshot initialization.
      if (_lastSnapshotKey.isEmpty) {
        _lastSnapshotKey = snapshotKey;
        _lastSnapshotSyncMs = nowMs;
      } else if (_lastSnapshotKey != snapshotKey) {
       // If the snapshot changed, update both the key and sync time.
        _lastSnapshotKey = snapshotKey;
        _lastSnapshotSyncMs = nowMs;
      }


 // Find the freshest sensor/system timestamp available.
// This makes the sync time more accurate across all sources.
      final int sensorTimestamp = _firstPositiveInt([
        motionMap['lastDetected'],
        motionMap['detectedAt'],
        motionMap['timestamp'],
        motionMap['lastUpdated'],
        doorMap['lastDetected'],
        doorMap['detectedAt'],
        doorMap['timestamp'],
        doorMap['lastUpdated'],
        vibrationMap['lastDetected'],
        vibrationMap['detectedAt'],
        vibrationMap['timestamp'],
        vibrationMap['lastUpdated'],
        temperatureMap['lastDetected'],
        temperatureMap['detectedAt'],
        temperatureMap['timestamp'],
        temperatureMap['lastUpdated'],
        pressure1Map['pressedAt'],
        pressure1Map['detectedAt'],
        pressure1Map['timestamp'],
        pressure1Map['lastUpdated'],
        pressure2Map['pressedAt'],
        pressure2Map['detectedAt'],
        pressure2Map['timestamp'],
        pressure2Map['lastUpdated'],
        cameraMap['lastSeen'],
        cameraMap['lastUpdated'],
        cameraMap['timestamp'],
        system['lastUpdate'],
        system['timestamp'],
      ]);

      // If this timestamp is newer than the current stored sync time, use it.
      if (sensorTimestamp > _lastSnapshotSyncMs) {
        _lastSnapshotSyncMs = sensorTimestamp;
      }

      final now = DateTime.now();


      // Calculate how many minutes passed since motion was last seen.
      final int noMotionMinutes = _lastMotionSeenMs > 0
          ? now
              .difference(DateTime.fromMillisecondsSinceEpoch(_lastMotionSeenMs))
              .inMinutes
          : 0;

      // Motion becomes emergency if no motion was detected for 1 minute.
      final bool motionRed =
          !motionDetected && _lastMotionSeenMs > 0 && noMotionMinutes >= 1;

      // Door is emergency if interpreted state is open.
      final bool doorRed = door == "open";
       // Any vibration is treated as emergency.
      final bool vibrationRed = vibrationDetected;

      // Temperature is outside the acceptable range if too high or too low.
      final bool highTemperature = temperature > 38.0;
      final bool lowTemperature = temperature < 36.0;
      final bool tempOutOfRange = highTemperature || lowTemperature;

      // Calculate how long the temperature has stayed outside the normal range.
      final int tempOutMinutes = temperatureStateMs > 0
          ? now
              .difference(DateTime.fromMillisecondsSinceEpoch(temperatureStateMs))
              .inMinutes
          : 0;

      // Temperature warning for less than 3 minutes outside range.
      final bool tempYellow =
          tempOutOfRange && temperatureStateMs > 0 && tempOutMinutes < 3;

      // Temperature emergency after 3 minutes outside range.
      final bool tempRed =
          tempOutOfRange && temperatureStateMs > 0 && tempOutMinutes >= 3;

      // Calculate how many minutes pressure has continued.
      final int pressureMinutes = _pressureStartMs > 0
          ? now
              .difference(DateTime.fromMillisecondsSinceEpoch(_pressureStartMs))
              .inMinutes
          : 0;

      // Pressure becomes emergency after 1 minute.
      final bool pressureRed =
          pressureDetected && _pressureStartMs > 0 && pressureMinutes >= 1;

      // Alarm status from system node using several possible field names.
      final bool alarmOn = _asBool(
        system['alarmOn'] ?? system['alarm'] ?? system['isAlarmOn'],
      );

      // Emergency calling status using multiple possible field names.
      final bool emergencyOn = _asBool(
        emergency['active'] ??
            emergency['isActive'] ??
            emergency['triggered'] ??
            emergency['emergencyOn'] ??
            emergency['calling'] ??
            emergency['isCalling'] ??
            emergency['callActive'],
      );

      // Overall red status if any emergency-level condition is active.
      final bool hasRed = alarmOn ||
          emergencyOn ||
          motionRed ||
          doorRed ||
          vibrationRed ||
          tempRed ||
          pressureRed;

      // Currently yellow status is only tied to temperature warning.
      final bool hasYellow = tempYellow;

      // Overall text status shown to the assistant.
      final String overallStatus = hasRed
          ? "Attention Needed"
          : hasYellow
              ? "Warning"
              : "Safe";

      // Human-readable notes that explain each sensor condition.
      final String motionNote = motionRed
          ? "No motion has been detected for 1 minute."
          : "Motion is within normal condition.";

      final String doorNote = doorRed
          ? "Front door is open and needs attention."
          : "Door is closed normally.";

      final String vibrationNote = vibrationRed
          ? "Vibration detected and needs immediate attention."
          : "No abnormal vibration condition.";

      final String tempNote = tempRed
          ? "Temperature stayed outside the normal range for 3 minutes."
          : tempYellow
              ? "Temperature is outside the normal range."
              : "Temperature is within normal range.";

      final String pressureNote = pressureRed
          ? "Pressure has continued for 1 minute."
          : "Pressure is within normal condition.";

      // Convert last sync timestamp into user-friendly text.
      final String syncText = _formatRelative(_lastSnapshotSyncMs);

// Caregiver details from Firestore.
// Fallback values are used if fields are missing.
      final caregiverFirstName =
          (userData['firstName'] ?? userData['name'] ?? "Caregiver").toString();
      final caregiverLastName = (userData['lastName'] ?? "").toString();
      final caregiverFullName =
          "$caregiverFirstName ${caregiverLastName.trim()}".trim();

      // Monitored person details from Firestore.
      final patientFirstName =
          (userData['patientFirstName'] ?? "Monitored").toString();
      final patientLastName =
          (userData['patientLastName'] ?? "Person").toString();
      final patientFullName =
          "$patientFirstName ${patientLastName.trim()}".trim();

      // Additional monitored person fields.
      final patientDob = (userData['patientDob'] ?? "").toString();
      final patientGender = (userData['patientGender'] ?? "").toString();
      final patientCountry = (userData['patientCountry'] ?? "Kuwait").toString();
      final patientRegion = (userData['patientRegion'] ?? "").toString();
      final patientFullAddress =
          (userData['patientFullAddress'] ?? "").toString();
      final patientNotes = (userData['patientNotes'] ?? "").toString();

      // Emergency contact details from Firestore.
      final emergencyContactCountry =
          (userData['emergencyContactCountry'] ?? patientCountry).toString();
      final emergencyContactName =
          (userData['emergencyContactName'] ?? "").toString();
      final emergencyContactPhone =
          (userData['emergencyContactPhone'] ?? "").toString();

      // User settings / preferences from Firestore.
      final soundAlarm = userData['soundAlarm'] ?? true;
      final callEmergencyContact = userData['callEmergencyContact'] ?? true;
      final emailAlerts = userData['emailAlerts'] ?? true;
      final mobileAlerts = userData['mobileAlerts'] ?? true;
      final emergencyAlerts = userData['emergencyAlerts'] ?? true;

// Collect the latest notifications from the session object.
// Only the first 8 are sent to the assistant to keep the payload smaller.
      final List<Map<String, dynamic>> recentNotifications = [];
      for (final n in NotificationsSession.notifications.take(8)) {
        recentNotifications.add({
          "title": n.title,
          "desc": n.desc,
          "label": n.label,
          "level": n.level.name,
          "type": n.type,
          "timestamp": n.timestamp,
          "sensorDetails": n.sensorDetails,
        });
      }

// Build the final structured assistant context object.
      // This is the main payload used by the backend assistant
      // so it can answer based on the latest app state.
      _liveAssistantContext = {
        "caregiver": {
          "name": caregiverFullName,
          "email": user?.email ?? "",
        },
        "monitoredPerson": {
          "name": patientFullName,
          "dob": patientDob,
          "gender": patientGender,
          "country": patientCountry,
          "region": patientRegion,
          "fullAddress": patientFullAddress,
          "medicalNotes": patientNotes,
        },
        "emergencyContact": {
          "name": emergencyContactName,
          "phone": emergencyContactPhone,
          "country": emergencyContactCountry,
        },
        "settings": {
          "soundAlarm": soundAlarm,
          "callEmergencyContact": callEmergencyContact,
          "emailAlerts": emailAlerts,
          "mobileAlerts": mobileAlerts,
          "emergencyAlerts": emergencyAlerts,
        },
        "realtime": {
          "status": overallStatus,
          "alarmOn": alarmOn,
          "emergencyOn": emergencyOn,
          "lastSyncMs": _lastSnapshotSyncMs,
          "lastSyncText": syncText,
          "cameraOnline": cameraOnline,
          "motion": {
            "detected": motionDetected,
            "noMotionMinutes": noMotionMinutes,
            "isEmergency": motionRed,
            "note": motionNote,
          },
          "door": {
            "state": door,
            "isEmergency": doorRed,
            "note": doorNote,
          },
          "vibration": {
            "detected": vibrationDetected,
            "isEmergency": vibrationRed,
            "note": vibrationNote,
          },
          "temperature": {
            "value": temperature,
            "high": highTemperature,
            "low": lowTemperature,
            "warning": tempYellow,
            "isEmergency": tempRed,
            "minutesOutsideRange": tempOutMinutes,
            "note": tempNote,
          },
          "pressure": {
            "detected": pressureDetected,
            "minutes": pressureMinutes,
            "isEmergency": pressureRed,
            "note": pressureNote,
          },
        },
        "logicSummary": {
          "overallStatus": overallStatus,
          "hasEmergency": hasRed,
          "hasWarning": hasYellow,
          "primaryReason": alarmOn
              ? "Alarm is currently active"
              : emergencyOn
                  ? "Emergency calling is active"
                  : motionRed
                      ? "No motion has been detected for 1 minute"
                      : doorRed
                          ? "Door is open"
                          : vibrationRed
                              ? "Vibration detected"
                              : tempRed
                                  ? (highTemperature
                                      ? "High body temperature detected"
                                      : "Low body temperature detected")
                                  : pressureRed
                                      ? "Pressure has continued for 1 minute"
                                      : tempYellow
                                          ? "Temperature is outside the normal range"
                                          : "All monitored conditions look normal",
        },
        "recentNotifications": recentNotifications,
       
       // Raw data is also included so the backend can inspect original values
      // in addition to the processed logic summary.
        "raw": {
          "sensors": sensors,
          "system": system,
          "emergency": emergency,
        },
      };

// Mark live context as ready.
// If not silent, rebuild the UI so the loading banner disappears.
      if (mounted && !silent) {
        setState(() {
          _liveReady = true;
        });
      } else {
        _liveReady = true;
      }
    } catch (_) {
      // If anything fails, keep the page alive without crashing.
      // When not silent, force a rebuild so UI remains responsive.
      if (mounted && !silent) {
        setState(() {});
      }
    }
  }

// Builds the recent chat history to send to the assistant backend.
// Only the last few messages are included to limit request size.
  List<Map<String, String>> _buildChatHistory() {
    final start = _messages.length > 6 ? _messages.length - 6 : 0;
    final recent = _messages.sublist(start);

    return recent.map((m) {
      return {
        "role": m.role == _Role.user ? "user" : "assistant",
        "text": m.text,
      };
    }).toList();
  }

  // Handles an action, backend update, or user request for this screen.
  Future<void> _sendMessage() async {
       // Read the text input and remove surrounding spaces.
    final text = _controller.text.trim();
        // Do nothing if message is empty or the assistant is already busy.
    if (text.isEmpty || _isThinking) return;
    // Clear the input field immediately after taking the text.
    _controller.clear();

    // Add the user's message to the chat and show thinking state.
    setState(() {
      _messages.add(
        _ChatMsg(role: _Role.user, text: text, time: DateTime.now()),
      );
      _isThinking = true;
    });
    // Scroll so the new message is visible, then send it.
    _scrollToBottom();
    await _sendToAssistant(text);
  }

  // Handles an action, backend update, or user request for this screen.
  Future<void> _sendQuick(_QuickAction action) async {
        // Prevent multiple requests while the assistant is busy.
    if (_isThinking) return;

    // Add the quick action label as if the user typed it.
    setState(() {
      _messages.add(
        _ChatMsg(role: _Role.user, text: action.label, time: DateTime.now()),
      );
      _isThinking = true;
    });

    // Scroll to bottom and send the quick action text.
    _scrollToBottom();
    await _sendToAssistant(action.label);
  }

  // Handles an action, backend update, or user request for this screen.
  Future<void> _sendToAssistant(String message) async {
    try {
     // Refresh context first so the assistant always gets the latest app state.
      await _refreshLiveContext();

      // Send POST request to assistant backend.
      final res = await http.post(
        Uri.parse(_apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "message": message,
          "appContext": _liveAssistantContext,
          "chatHistory": _buildChatHistory(),
        }),
      );

      // Default fallback reply.
      String reply = "I could not get a response right now.";

      if (res.statusCode == 200) {
        // Parse normal successful response.
        final data = jsonDecode(res.body);
        reply = (data["reply"] ?? reply).toString().trim();
      } else {
        // Try to parse error message returned by the backend.
        try {
          final data = jsonDecode(res.body);
          reply = (data["error"] ?? reply).toString().trim();
        } catch (_) {}
      }
      // Handle network or unexpected errors gracefully.
      if (!mounted) return;
      // Add assistant reply to the conversation and stop thinking state.
      setState(() {
        _messages.add(
          _ChatMsg(
            role: _Role.assistant,
            text: reply.isEmpty ? "I could not get a response right now." : reply,
            time: DateTime.now(),
          ),
        );
        _isThinking = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _messages.add(
          _ChatMsg(
            role: _Role.assistant,
            text: "Connection error. Please try again.",
            time: DateTime.now(),
          ),
        );
        _isThinking = false;
      });
    }

    _scrollToBottom();
  }


  // Internal helper method for the screen logic.
  void _scrollToBottom() {
    // This runs after the current frame is drawn, so the list has already updated with the new message.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
     // Animate down a bit beyond max extent for smoother behavior.
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }


  // Helper function used to convert, format, or prepare data for display.
  static int _normalizeTimestamp(dynamic value) {
    // Null means invalid timestamp.
    if (value == null) return 0;
   
    // Already a DateTime object.
    if (value is DateTime) return value.millisecondsSinceEpoch;

    // Integer timestamp handling.
    // If it looks like seconds, convert to milliseconds.
    if (value is int) {
      if (value > 0 && value < 1000000000000) return value * 1000;
      return value;
    }
    // Double timestamp handling.
    if (value is double) {
      final parsed = value.toInt();
      if (parsed > 0 && parsed < 1000000000000) return parsed * 1000;
      return parsed;
    }
    // String handling.
    final text = value.toString().trim();
    if (text.isEmpty || text == '0') return 0;

    // Try ISO date parsing first.
    final parsedDate = DateTime.tryParse(text);
    if (parsedDate != null) return parsedDate.millisecondsSinceEpoch;

    // Otherwise try numeric parsing.
    final parsed = int.tryParse(text) ?? 0;
    if (parsed <= 0) return 0;
    if (parsed < 1000000000000) return parsed * 1000;
    return parsed;
  }


  // Helper function used to convert, format, or prepare data for display.
  static int _firstPositiveInt(List<dynamic> values) {
  // Return the first valid positive normalized timestamp/value.
    for (final value in values) {
      final parsed = _normalizeTimestamp(value);
      if (parsed > 0) return parsed;
    }
    return 0;
  }

  // Helper function used to convert, format, or prepare data for display.
  static double _asDouble(dynamic value, {double fallback = 0.0}) {
       // Convert value to double safely.
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }


  // Helper function used to convert, format, or prepare data for display.
  static bool _asBool(dynamic value) {
  // If already a boolean, return directly.
    if (value is bool) return value;

    // Normalize text so multiple backend/device representations can map to true.
    final text = (value ?? '').toString().trim().toLowerCase();
    return text == 'true' ||
        text == '1' ||
        text == 'yes' ||
        text == 'open' ||
        text == 'opened' ||
        text == 'detected' ||
        text == 'active' ||
        text == 'on' ||
        text == 'calling' ||
        text == 'called';
  }


  // Helper function used to convert, format, or prepare data for display.
  static String _formatRelative(int timestampMs) {
      // If no timestamp exists yet.
    if (timestampMs <= 0) return "Not yet";

    final now = DateTime.now();
    final time = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final diff = now.difference(time);

    // Future timestamps are treated as "Just now".
    if (diff.isNegative) return "Just now";
    if (diff.inSeconds < 10) return "Just now";
    if (diff.inMinutes < 1) return "${diff.inSeconds} sec ago";
    if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
    if (diff.inHours < 24) return "${diff.inHours} hr ago";
    return "${diff.inDays} day(s) ago";
  }


  // Main build method that returns the widget tree for the screen.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = navy;
    final card = Colors.white;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Assistant",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
         // Show loading info until live context is prepared.
            if (!_liveReady)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: const Color(0xFFEAF3FF),
                child: const Text(
                  "Loading live app status...",
                  style: TextStyle(
                    color: navy,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          // Main chat area.
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
               // Add one extra item when assistant is thinking,
                // so the thinking bubble appears at the bottom.
                itemCount: _messages.length + (_isThinking ? 1 : 0),
                itemBuilder: (context, index) {
                 // Last temporary item = animated thinking bubble.
                  if (_isThinking && index == _messages.length) {
                    return _ThinkingBubble(bubbleColor: card);
                  }

                  final msg = _messages[index];
                  final isUser = msg.role == _Role.user;

                  // User messages use primary color, assistant uses white card style.
                  final bubbleColor = isUser ? primary : card;
                  final textColor = isUser
                      ? Colors.white
                      : (theme.textTheme.bodyMedium?.color ?? Colors.black);

                  return Align(
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isUser ? 16 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                              color: Colors.black.withOpacity(0.06),
                            ),
                          ],
                        ),
                        child: Text(
                          msg.text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: textColor,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),           
           // Bottom input area with text box and quick question chips.
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: pageBg,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 14,
                    offset: const Offset(0, -4),
                    color: Colors.black.withOpacity(0.06),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
             // Main input row.
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                        // Pressing enter/send on keyboard triggers sending.
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) =>
                              _isThinking ? null : _sendMessage(),
                          decoration: InputDecoration(
                            hintText: "Ask the assistant...",
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.black.withOpacity(0.08),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.black.withOpacity(0.08),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: softBlue,
                                width: 1.4,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                     // Send button.
                      Container(
                        decoration: BoxDecoration(
                          color: navy,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: _isThinking ? null : _sendMessage,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                 // Quick question section title.
                  Text(
                    "Quick questions",
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                 // Horizontal list of quick action chips.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(_quickActions.length, (index) {
                        final a = _quickActions[index];

                        return Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: SizedBox(
                            width: 190,
                            child: ActionChip(
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.black.withOpacity(0.08),
                              ),
                              avatar: Icon(a.icon, size: 18, color: softBlue),
                              label: Center(
                                child: Text(
                                  a.label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: navy,
                                    fontWeight: FontWeight.w600,
                                  ), //TextStyle
                                ),
                              ),
                             // Sends predefined prompt to the assistant.
                              onPressed: _isThinking ? null : () => _sendQuick(a),
                            ),
                          ),
                        );
                      }), // List.generate
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// _ThinkingBubble
// Main widget/class definition for this part of the app.

/// Small temporary widget shown while waiting for backend reply.
class _ThinkingBubble extends StatefulWidget {
  final Color bubbleColor;
  const _ThinkingBubble({required this.bubbleColor});

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

// _ThinkingBubbleState
// Main widget/class definition for this part of the app.


// State class that holds live values, controllers, and UI logic for the screen.
class _ThinkingBubbleState extends State<_ThinkingBubble> {
    // Controls how many dots are currently shown in "Thinking..."
  int _dot = 1;

    // Timers used for periodic refresh or live updates.
    // Timer animates the dots repeatedly.
  Timer? _t;


  // Runs once when this screen starts and prepares initial state.
  @override
  void initState() {
    super.initState();
        // Update the number of dots every 350 ms to create a simple animation.
    _t = Timer.periodic(const Duration(milliseconds: 350), (_) {
      setState(() => _dot = _dot == 3 ? 1 : _dot + 1);
    }); //Timer.periodic
  }


  // Releases resources here to avoid memory leaks.
  @override
  void dispose() {
  // Stop the animation timer when widget is removed.
    _t?.cancel();
    super.dispose();
  }


  // Main build method that returns the widget tree for the screen.
  @override
  Widget build(BuildContext context) {
   // Build the animated dot text.
    final dots = "." * _dot;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.bubbleColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 10,
              offset: const Offset(0, 4),
              color: Colors.black.withOpacity(0.06),
            ),
          ],
        ),
        child: Text(
          "Thinking$dots",
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF0D1B2A),
              ),
        ),
      ),
    );
  }
}
// Enum used to distinguish message sender type.
enum _Role { user, assistant }

// Represents one chat message in the conversation.
class _ChatMsg {
  final _Role role;
  final String text;
  final DateTime time;

  _ChatMsg({
    required this.role,
    required this.text,
    required this.time,
  });
}

// Represents one quick action chip shown below the input.
class _QuickAction {
  final String label;
  final String key;
  final IconData icon;

  const _QuickAction(this.label, this.key, this.icon);
}