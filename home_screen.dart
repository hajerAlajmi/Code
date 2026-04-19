// Imports
// Packages and project files used by this screen.
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notifications_screen.dart';


// HomeScreen
// Main widget/class definition for this part of the app.
// This is the main home page of the app.
// It gives the caregiver a quick overview of the monitored environment
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenCameraTab,
  });

  // Callback used to switch to the camera tab from the home screen.
  // This is passed in from the parent shell so HomeScreen does not directly manage tab navigation itself.
  final VoidCallback onOpenCameraTab;

  // Shared theme colors used throughout the screen.
  static const softBlue = Color(0xFF4A90E2);
  static const navy = Color(0xFF0D1B2A);
  static const lightBlueBg = Color(0xFFEAF3FF);
  static const lightRedBg = Color(0xFFFFE9E9);
  static const lightGreenBg = Color(0xFFEAF7EE);
  static const lightYellowBg = Color(0xFFFFF4D6);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}


// _HomeScreenState
// Main widget/class definition for this part of the app.

// State class that holds live values, controllers, and UI logic for the screen.
class _HomeScreenState extends State<HomeScreen> {
  
    // Firebase database references used to read or update live data.
    // _rootDb is used for general writes such as adding events.
    // _sensorsDb streams live sensor data.
    // _systemDb streams live system state such as alarmOn.
  final DatabaseReference _rootDb = FirebaseDatabase.instance.ref();
  final DatabaseReference _sensorsDb = FirebaseDatabase.instance.ref('sensors');
  final DatabaseReference _systemDb = FirebaseDatabase.instance.ref('system');
  
    // Current logged-in user.
    // Needed for reading user settings and emergency contact details.
  final User? user = FirebaseAuth.instance.currentUser;

  // Holds the latest Firestore user settings document.
  // This is updated live through a StreamBuilder.
  Map<String, dynamic> _userSettings = {};

  // Convenience getters for user preferences.
  // These default to true when no explicit setting exists,so core safety features remain enabled unless the user disables them.
  bool get _soundAlarmEnabled => _userSettings['soundAlarm'] ?? true;
  bool get _callEmergencyEnabled =>
      _userSettings['callEmergencyContact'] ?? true;
  bool get _emailAlertsEnabled => _userSettings['emailAlerts'] ?? true;
  bool get _mobileAlertsEnabled => _userSettings['mobileAlerts'] ?? true;
  bool get _emergencyAlertsEnabled =>
      _userSettings['emergencyAlerts'] ?? true;

  // Tracks the last moment when motion was seen.
  // This is important because safety logic depends not just on whether motion is currently detected, but how long it has been absent.
  int _lastMotionSeenMs = 0;

  // Tracks when a pressure event started.
  // This lets the app calculate how many minutes pressure has continued.
  int _pressureStartMs = 0;

  // Stores the latest meaningful sync timestamp shown on the home page.
  int _lastSyncMs = 0;

  // Compact fingerprint of the previous sensor snapshot.
  // Used to detect whether the live state changed.
  String _lastSnapshotKey = '';

  // Mapping of supported countries to their phone calling codes.
  // Used when building the full emergency contact phone number.
  final Map<String, String> countryCodes = {
    "Kuwait": "+965",
    "UAE": "+971",
    "Saudi Arabia": "+966",
    "Oman": "+968",
    "Qatar": "+974",
    "Bahrain": "+973",
  };

  // Returns a live stream of the signed-in user's settings document.
  // If there is no logged-in user, an empty stream is returned so the UI can stay safe without crashing.
  Stream<DocumentSnapshot<Map<String, dynamic>>> _userSettingsStream() {
    if (user == null) {
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .snapshots();
  }


  // Handles an action, backend update, or user request for this screen.
  Future<void> _addEvent({
    required String title,
    required String message,
    required String type,
    required String priority,
  }) async {
    // Capture one shared timestamp for the event.
    final now = DateTime.now();

    // Push a new record into the events list in Realtime Database.
    // This keeps a history of major actions such as: alarm triggered, alarm stopped
    await _rootDb.child('events').push().set({
      'title': title,
      'message': message,
      'time': _formatClock(now),
      'type': type,
      'priority': priority,
      'timestamp': now.millisecondsSinceEpoch,
    });

    // Update system lastUpdate so the rest of the UI can show fresh sync state.
    await _rootDb.child('system').update({
      'lastUpdate': now.millisecondsSinceEpoch,
    });
  }


  // Handles an action, backend update, or user request for this screen.
  Future<void> _callEmergencyContact() async {
    // Respect user settings before attempting any call.
    if (!_callEmergencyEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency calling is disabled in Settings'),
        ),
      );
      return;
    }

    // A logged-in user is required because contact info is stored in Firestore.
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logged in user')),
      );
      return;
    }

    try {
      // Load the current user's Firestore profile document.
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      final data = doc.data() ?? {};

      // Read emergency contact country and phone from saved settings.
      final emergencyCountry =
          (data['emergencyContactCountry'] ?? 'Kuwait').toString();
      final emergencyPhone =
          (data['emergencyContactPhone'] ?? '').toString().trim();

      // Convert country name to dial code.
      final emergencyCode = countryCodes[emergencyCountry] ?? '+965';

      // If no phone number exists, notify the user.
      if (emergencyPhone.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No emergency contact number saved in Settings'),
          ),
        );
        return;
      }

      // Build the final dialable number and convert it into a tel: URI.
      final fullNumber = '$emergencyCode$emergencyPhone';
      final Uri phoneUri = Uri(scheme: 'tel', path: fullNumber);

      // Attempt to launch the phone call action on the current platform/device.
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open phone call')),
        );
      }
    } catch (e) {
      // Show a readable error if Firestore read or launch fails.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reading emergency contact: $e')),
      );
    }
  }


  // Handles an action, backend update, or user request for this screen.
  Future<void> _triggerAlarm() async {
    // Shared timestamp used for consistent updates.
    final now = DateTime.now();

    try {
      // Update the system node to reflect an active alarm state.
      await _rootDb.child('system').update({
        'alarmOn': true,
        'dashboardStatus': 'alert',
        'latestAlert': _soundAlarmEnabled
            ? 'Alarm is currently active'
            : 'Alarm triggered (sound disabled in settings)',
        'lastUpdate': now.millisecondsSinceEpoch,
      });

      // Also store the action in the events log for history/tracking.
      await _addEvent(
        title: 'Alarm Triggered',
        message: _soundAlarmEnabled
            ? 'Alarm was triggered manually'
            : 'Alarm triggered manually with sound disabled in settings',
        type: 'alarm',
        priority: 'high',
      );

      // Give the user immediate feedback in the UI.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _soundAlarmEnabled
                ? 'Alarm triggered'
                : 'Alarm triggered without sound',
          ),
        ),
      );
    } catch (e) {
      // Show any database/write error to the user.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error triggering alarm: $e')),
      );
    }
  }


  // Handles an action, backend update, or user request for this screen.
  Future<void> _stopAlarm() async {
    // Shared timestamp used for consistent logging.
    final now = DateTime.now();

    try {
      // Reset the system state back to safe.
      await _rootDb.child('system').update({
        'alarmOn': false,
        'dashboardStatus': 'safe',
        'latestAlert': '',
        'lastUpdate': now.millisecondsSinceEpoch,
      });

      // Record the stop action in the events list.
      await _addEvent(
        title: 'Alarm Stopped',
        message: 'Caregiver stopped the alarm',
        type: 'alarm',
        priority: 'normal',
      );

      // Confirm success to the user.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarm stopped')),
      );
    } catch (e) {
      // Show any error that occurred while updating the alarm state.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error stopping alarm: $e')),
      );
    }
  }


  // Main build method that returns the widget tree for the screen.
  @override
  Widget build(BuildContext context) {
    // First stream: user settings from Firestore.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userSettingsStream(),
      builder: (context, userSettingsSnapshot) {
        // Save latest settings locally so helper getters can use them.
        _userSettings = userSettingsSnapshot.data?.data() ?? {};

        // Second stream: live sensor data from Realtime Database.
        return StreamBuilder<DatabaseEvent>(
          stream: _sensorsDb.onValue,
          builder: (context, sensorsSnapshot) {

            // Third stream: live system state, including alarmOn.
            return StreamBuilder<DatabaseEvent>(
              stream: _systemDb.onValue,
              builder: (context, systemSnapshot) {

                // Fourth stream: periodic one-second tick.
                // This is important because some UI states depend on elapsed time,even when the raw database values are unchanged.
                return StreamBuilder<int>(
                  stream: Stream<int>.periodic(
                    const Duration(seconds: 1),
                    (count) => count,
                  ), // Stream.periodic
                  builder: (context, _) {
                    // Default values before live parsing.
                    bool motionDetected = false;
                    String door = "closed";
                    bool vibrationDetected = false;
                    double temperature = 36.8;
                    bool pressureDetected = false;
                    bool cameraOnline = true;
                    bool alarmOn = false;

                    // Timestamps used for duration-based safety logic.
                    int vibrationStartMs = 0;
                    int temperatureStateMs = 0;

                    // Parse live sensor data if available.
                    if (sensorsSnapshot.hasData &&
                        sensorsSnapshot.data!.snapshot.value != null) {
                      final raw = sensorsSnapshot.data!.snapshot.value as Map;
                      final sensors = Map<String, dynamic>.from(raw);

                      // Extract each sensor block safely.
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

                      // Determine whether the camera is still considered online.
                      final int cameraLastSeen = _asInt(
                        cameraMap['lastSeen'] ??
                            cameraMap['lastUpdated'] ??
                            cameraMap['timestamp'],
                      );

                      final int cameraNowMs =
                          DateTime.now().millisecondsSinceEpoch;

                      cameraOnline = cameraLastSeen > 0 &&
                          (cameraNowMs - cameraLastSeen) <= 10000;

                      // Motion status normalization.
                      final motionStatus =
                          (motionMap['status'] ?? '').toString().toLowerCase();
                      motionDetected = motionStatus == 'detected';

                      // Door status normalization and inversion logic.
                      // This flips values because the physical/database logic is represented opposite to the desired UI meaning.
                      final rawDoorStatus = (doorMap['status'] ?? 'closed')
                          .toString()
                          .toLowerCase();

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

                      // Vibration status normalization.
                      final vibrationStatus = (vibrationMap['status'] ?? '')
                          .toString()
                          .toLowerCase();
                      vibrationDetected = vibrationStatus == 'detected';

                      // Read temperature from multiple possible field names.
                      temperature = _asDouble(
                        temperatureMap['celsius'] ??
                            temperatureMap['value'] ??
                            temperatureMap['bodyTemp'],
                        fallback: 36.8,
                      );

                      // Pressure is considered active if either pressure sensor is pressed.
                      final p1Status =
                          (pressure1Map['status'] ?? '').toString().toLowerCase();
                      final p2Status =
                          (pressure2Map['status'] ?? '').toString().toLowerCase();

                      pressureDetected =
                          p1Status == 'pressed' || p2Status == 'pressed';

                      final int nowMs = DateTime.now().millisecondsSinceEpoch;

                      // Best available motion timestamp.
                      final int motionTimestamp = _asInt(
                        motionMap['lastDetected'] ??
                            motionMap['detectedAt'] ??
                            motionMap['timestamp'],
                      );

                      // Keep last motion time updated.
                      if (motionDetected) {
                        _lastMotionSeenMs =
                            motionTimestamp > 0 ? motionTimestamp : nowMs;
                      } else {
                        if (_lastMotionSeenMs == 0 && motionTimestamp > 0) {
                          _lastMotionSeenMs = motionTimestamp;
                        }
                      }

                      // Track how long pressure has continued.
                      if (pressureDetected) {
                        if (_pressureStartMs == 0) {
                          final int pressureTimestamp = _firstPositiveInt([
                            pressure1Map['pressedAt'],
                            pressure1Map['startTime'],
                            pressure1Map['startedAt'],
                            pressure1Map['timestamp'],
                            pressure2Map['pressedAt'],
                            pressure2Map['startTime'],
                            pressure2Map['startedAt'],
                            pressure2Map['timestamp'],
                          ]);

                          _pressureStartMs =
                              pressureTimestamp > 0 ? pressureTimestamp : nowMs;
                        }
                      } else {
                        _pressureStartMs = 0;
                      }

                      // Timestamp for vibration events.
                      vibrationStartMs = _asInt(
                        vibrationMap['lastDetected'] ??
                            vibrationMap['lastUpdated'] ??
                            vibrationMap['timestamp'],
                      );

                      // Timestamp for temperature state changes.
                      temperatureStateMs = _asInt(
                        temperatureMap['lastDetected'] ??
                            temperatureMap['lastUpdated'],
                      );

                      // Compact fingerprint of current snapshot.
                      final String snapshotKey = [
                        motionStatus,
                        rawDoorStatus,
                        vibrationStatus,
                        temperature.toStringAsFixed(1),
                        p1Status,
                        p2Status,
                        motionTimestamp.toString(),
                      ].join('|');

                      // Update sync time when the snapshot meaningfully changes.
                      if (_lastSnapshotKey.isEmpty) {
                        _lastSnapshotKey = snapshotKey;
                        _lastSyncMs = nowMs;
                      } else if (_lastSnapshotKey != snapshotKey) {
                        _lastSnapshotKey = snapshotKey;
                        _lastSyncMs = nowMs;
                      }

                      // Collect the freshest relevant sensor timestamp.
                      final int sensorTimestamp = _firstPositiveInt([
                        motionMap['lastDetected'],
                        motionMap['detectedAt'],
                        motionMap['timestamp'],

                        doorMap['lastDetected'],
                        doorMap['detectedAt'],
                        doorMap['timestamp'],

                        vibrationMap['lastDetected'],
                        vibrationMap['detectedAt'],
                        vibrationMap['timestamp'],

                        temperatureMap['lastDetected'],
                        temperatureMap['detectedAt'],
                        temperatureMap['timestamp'],

                        pressure1Map['pressedAt'],
                        pressure1Map['detectedAt'],
                        pressure1Map['timestamp'],

                        pressure2Map['pressedAt'],
                        pressure2Map['detectedAt'],
                        pressure2Map['timestamp'],
                      ]);

                      if (sensorTimestamp > 0) {
                        _lastSyncMs = sensorTimestamp;
                      }
                    }

                    // Parse live system data if available.
                    if (systemSnapshot.hasData &&
                        systemSnapshot.data!.snapshot.value != null) {
                      final rawSystem = systemSnapshot.data!.snapshot.value as Map;
                      final system = Map<String, dynamic>.from(rawSystem);

                      alarmOn = _asBool(system['alarmOn']);
                    }

                    final now = DateTime.now();

                    // Minutes since motion was last detected.
                    final int noMotionMinutes = _lastMotionSeenMs > 0
                        ? now
                            .difference(
                              DateTime.fromMillisecondsSinceEpoch(
                                _lastMotionSeenMs,
                              ),
                            )
                            .inMinutes
                        : 0;

                    // Motion logic.
                    final bool motionYellow = false;
                    final bool motionRed = !motionDetected &&
                        _lastMotionSeenMs > 0 &&
                        noMotionMinutes >= 1;

                    // Door and vibration emergency logic.
                    final bool doorRed = door == "open";
                    final bool vibrationRed = vibrationDetected;

                    // Temperature range logic.
                    final bool highTemperature = temperature > 38.0;
                    final bool lowTemperature = temperature < 36.0;
                    final bool tempOutOfRange =
                        highTemperature || lowTemperature;

                    // How long temperature has been outside the accepted range.
                    final int tempOutMinutes = temperatureStateMs > 0
                        ? now
                            .difference(
                              DateTime.fromMillisecondsSinceEpoch(
                                temperatureStateMs,
                              ),
                            )
                            .inMinutes
                        : 0;

                    final bool tempYellow = tempOutOfRange &&
                        temperatureStateMs > 0 &&
                        tempOutMinutes < 3;

                    final bool tempRed = tempOutOfRange &&
                        temperatureStateMs > 0 &&
                        tempOutMinutes >= 3;

                    // How long pressure has continued.
                    final int pressureMinutes = _pressureStartMs > 0
                        ? now
                            .difference(
                              DateTime.fromMillisecondsSinceEpoch(
                                _pressureStartMs,
                              ),
                            )
                            .inMinutes
                        : 0;

                    final bool pressureYellow = false;
                    final bool pressureRed = pressureDetected &&
                        _pressureStartMs > 0 &&
                        pressureMinutes >= 1;

                    // Combine all red/yellow conditions for banner logic.
                    final bool hasRed = alarmOn ||
                        motionRed ||
                        doorRed ||
                        vibrationRed ||
                        tempRed ||
                        pressureRed;

                    final bool hasYellow =
                        motionYellow || tempYellow || pressureYellow;

                    // Banner colors change according to severity.
                    final Color bannerColor = hasRed
                        ? Colors.red
                        : hasYellow
                            ? Colors.orange
                            : Colors.green;

                    final Color bannerBg = hasRed
                        ? HomeScreen.lightRedBg
                        : hasYellow
                            ? HomeScreen.lightYellowBg
                            : HomeScreen.lightGreenBg;

                    // Friendly display text values.
                    final String activity =
                        motionDetected ? "Moving" : "No Movement";
                    final String temperatureText =
                        "${temperature.toStringAsFixed(1)} °C";
                    final String doorText = door == "open" ? "Open" : "Closed";
                    final String vibrationText = vibrationRed
                        ? "Emergency"
                        : vibrationDetected
                            ? "Detected"
                            : "Normal";
                    final String cameraText =
                        cameraOnline ? "Online" : "Offline";

                    // Banner title and message explain the current highest-priority issue.
                    String statusTitle;
                    String statusMessage;

                    if (alarmOn) {
                      statusTitle = "Attention Needed!";
                      statusMessage = "Alarm is currently active";
                    } else if (motionRed) {
                      statusTitle = "Attention Needed!";
                      statusMessage =
                          "No motion has been detected for one minute";
                    } else if (doorRed) {
                      statusTitle = "Attention Needed!";
                      statusMessage = "Door is open";
                    } else if (vibrationRed) {
                      statusTitle = "Attention Needed!";
                      statusMessage = "Vibration detected";
                    } else if (tempRed) {
                      statusTitle = "Attention Needed!";
                      statusMessage = highTemperature
                          ? "High body temperature detected"
                          : "Low body temperature detected";
                    } else if (pressureRed) {
                      statusTitle = "Attention Needed!";
                      statusMessage = "Pressure has continued for 1 minute";
                    } else if (tempYellow) {
                      statusTitle = "Warning";
                      statusMessage =
                          "Temperature is outside the normal range";
                    } else {
                      statusTitle = "Everything is Safe";
                      statusMessage =
                          "All monitored conditions look normal";
                    }

                    // Pull the most recent critical notifications only.
                    final List<Notif> realCritical =
                        NotificationsSession.notifications
                            .where((n) => n.level == NotifLevel.critical)
                            .take(3)
                            .toList();

                    return Scaffold(
                      body: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            /// Top banner summarizing overall home state.
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: bannerBg,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    hasRed
                                        ? Icons.warning_amber_rounded
                                        : hasYellow
                                            ? Icons.error_outline
                                            : Icons.verified,
                                    color: bannerColor,
                                    size: 32,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          statusTitle,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: bannerColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          statusMessage,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: bannerColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Activity and health summary section.
                            const Text(
                              "Activity & Health",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: HomeScreen.navy,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Current activity card.
                            _sensorCard(
                              Icons.directions_walk,
                              "Current Activity",
                              activity,
                            ),
                            const SizedBox(height: 12),

                            // Temperature and last movement cards.
                            Row(
                              children: [
                                Expanded(
                                  child: _infoCard(
                                    icon: Icons.thermostat,
                                    title: "Body Temperature",
                                    value: temperatureText,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _infoCard(
                                    icon: Icons.access_time,
                                    title: "Last Movement",
                                    value: _formatRelative(_lastMotionSeenMs),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Quick actions section for emergency features.
                            const Text(
                              "Quick Actions",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: HomeScreen.navy,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Emergency Call + Alarm action buttons.
                            Row(
                              children: [
                                Expanded(
                                  child: _actionButton(
                                    icon: Icons.phone,
                                    label: "Emergency Call",
                                    onTap: _callEmergencyContact,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _actionButton(
                                    icon: alarmOn
                                        ? Icons.stop_circle_outlined
                                        : Icons.notifications_active,
                                    label: alarmOn
                                        ? "Stop Alarm"
                                        : "Trigger Alarm",
                                    onTap:
                                        alarmOn ? _stopAlarm : _triggerAlarm,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Home status section showing current sensor states.
                            const Text(
                              "Home Status",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: HomeScreen.navy,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Door and vibration cards.
                            Row(
                              children: [
                                Expanded(
                                  child: _infoCard(
                                    icon: Icons.door_front_door,
                                    title: "Door Status",
                                    value: doorText,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _infoCard(
                                    icon: Icons.vibration,
                                    title: "Vibration",
                                    value: vibrationText,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Camera and last update cards.
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: widget.onOpenCameraTab,
                                    borderRadius: BorderRadius.circular(16),
                                    child: _infoCard(
                                      icon: Icons.videocam,
                                      title: "Camera Status",
                                      value: cameraText,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _infoCard(
                                    icon: Icons.update,
                                    title: "Last Update",
                                    value: _formatRelative(_lastSyncMs),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Critical notifications preview section.
                            const Text(
                              "Critical Notifications",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: HomeScreen.navy,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Show either a safe placeholder or the latest critical alerts.
                            if (realCritical.isEmpty)
                              _notificationCard(
                                icon: Icons.verified_outlined,
                                title:
                                    "No critical notifications right now",
                                time: "Now",
                              )
                            else
                              Column(
                                children: [
                                  for (int i = 0;
                                      i < realCritical.length;
                                      i++) ...[
                                    _notificationCard(
                                      icon: realCritical[i].icon,
                                      title: realCritical[i].title,
                                      time: _formatRelative(
                                        realCritical[i].timestamp,
                                      ),
                                    ),
                                    if (i != realCritical.length - 1)
                                      const SizedBox(height: 12),
                                  ],
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }


  // Helper function used to convert, format, or prepare data for display.
  static bool _asBool(dynamic value) {
    // Safely converts common Firebase values into a boolean.
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      final v = value.toLowerCase().trim();
      return v == 'true' ||
          v == '1' ||
          v == 'yes' ||
          v == 'on' ||
          v == 'online' ||
          v == 'active';
    }
    return false;
  }


  // Helper function used to convert, format, or prepare data for display.
  static int _asInt(dynamic value) {
    // Safely converts int/double/string-like values into int.
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  // Helper function used to convert, format, or prepare data for display.
  static int _maxInt(int a, int b) {
    // Returns the larger of two integer values.
    return a > b ? a : b;
  }

  // Helper function used to convert, format, or prepare data for display.
  static int _firstPositiveInt(List<dynamic> values) {
    // Returns the first value in the list that converts to a positive int.
    for (final value in values) {
      final int parsed = _asInt(value);
      if (parsed > 0) return parsed;
    }
    return 0;
  }

  static double _asDouble(dynamic value, {double fallback = 0.0}) {
    // Safely converts values into a double.
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  // Helper function used to convert, format, or prepare data for display.
  static String _formatClock(DateTime time) {
    // Formats DateTime into a human-readable 12-hour clock time.
    final hour =
        time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  // Helper function used to convert, format, or prepare data for display.
  static String _formatRelative(int timestampMs) {
    /// Converts a timestamp into relative text
    if (timestampMs == 0) return "Not yet";

    final now = DateTime.now();
    final time = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final diff = now.difference(time);

    if (diff.inSeconds < 10) return "Just now";
    if (diff.inMinutes < 1) return "${diff.inSeconds} sec ago";
    if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
    if (diff.inHours < 24) return "${diff.inHours} hr ago";
    return "${diff.inDays} day(s) ago";
  }


// Internal helper method for the screen logic.
  // Reusable sensor card used to display one sensor with details.
  static Widget _sensorCard(IconData icon, String title, String value) {
    // Wider horizontal card used for a primary single summary item.
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            color: Color(0x11000000),
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: HomeScreen.softBlue, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: HomeScreen.navy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Internal helper method for the screen logic.
  static Widget _infoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
  // Reusable compact info card used across the home page.
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            color: Color(0x11000000),
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: HomeScreen.softBlue, size: 24),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: HomeScreen.navy,
            ),
          ),
        ],
      ),
    );
  }

  // Internal helper method for the screen logic.
  static Widget _notificationCard({
    required IconData icon,
    required String title,
    required String time,
  }) {
    // Reusable row card used to preview critical notifications.
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            color: Color(0x11000000),
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.red, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: HomeScreen.navy,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }


// Internal helper method for the screen logic.
// Reusable action button used for alarm and call actions.
  static Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    // Reusable large action button for quick emergency features.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF3FF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: HomeScreen.softBlue),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: HomeScreen.navy,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}