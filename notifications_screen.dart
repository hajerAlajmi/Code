// Imports
// Packages and project files used by this screen.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


// NotificationsScreen
// Main widget/class definition for this part of the app.
// This screen is responsible for showing the notification history generated from real-time sensor, system, and emergency data.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  // Shared theme colors used across this screen.
  static const softBlue = Color(0xFF4A90E2);
  static const navy = Color(0xFF0D1B2A);
  static const green = Color(0xFF2E7D32);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

// NotificationsSession
// This class acts like a shared in-memory session for notifications.
// Notifications should remain available even if the widget rebuilds or the user switches tabs.
class NotificationsSession {
  static final List<Notif> notifications = [];

  // Latest raw Firebase maps stored in memory.
  static Map<String, dynamic> sensorsMap = {};
  static Map<String, dynamic> systemMap = {};
  static Map<String, dynamic> emergencyMap = {};
  static Map<String, dynamic> userSettings = {};

  // Timestamp trackers used for duration-based logic.
  static int lastMotionSeenMs = 0;
  static int pressureStartMs = 0;
  static int vibrationStartMs = 0;
  static int tempHighStartMs = 0;

  // Flags used to prevent repeated sending of the same critical notification
  // while the condition is still continuously active.
  static bool motionCriticalSent = false;
  static bool pressureCriticalSent = false;
  static bool tempCriticalSent = false;

  // Previous states used to detect transitions.
  static bool? prevMotionDetected;
  static String? prevDoorState;
  static bool? prevPressureDetected;
  static bool? prevAlarmOn;
  static bool? prevEmergencyOn;
  static bool? prevTempHigh;
  static bool? prevVibrationDetected;

  // General initialization flags.
  static bool initialized = false;
  static bool settingsLoaded = false;
}


// _NotificationsScreenState
// Main widget/class definition for this part of the app.
class _NotificationsScreenState extends State<NotificationsScreen>
    with AutomaticKeepAliveClientMixin {
 
  // Firebase database references used to read or update live data.
  // sensorsDb: all sensor values
  // systemDb: app/system-level values such as alarm state
  // emergencyDb: emergency calling state and related data
  final DatabaseReference sensorsDb = FirebaseDatabase.instance.ref('sensors');
  final DatabaseReference systemDb = FirebaseDatabase.instance.ref('system');
  final DatabaseReference emergencyDb = FirebaseDatabase.instance.ref('emergency');
  
  // Current logged-in user.
  // Needed so the screen can read the signed-in user's settings document.
  final User? user = FirebaseAuth.instance.currentUser;

  // Stream subscriptions are stored so they can be cancelled in dispose().
  StreamSubscription<DatabaseEvent>? _sensorsSub;
  StreamSubscription<DatabaseEvent>? _systemSub;
  StreamSubscription<DatabaseEvent>? _emergencySub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSettingsSub;
  
  // Timers used for periodic refresh or live updates.
  // This ticker is important because some alerts depend on elapsed time, not only on immediate database changes.
  Timer? _ticker;

  // Controls initial loading state before the first sensor snapshot arrives.
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  // Shortcut getter for the shared notifications list.
  List<Notif> get _notifications => NotificationsSession.notifications;

  // User settings getters with default true fallback.
  // That means alerts remain enabled unless the user explicitly disables them.
  bool get _emailAlertsEnabled =>
      NotificationsSession.userSettings['emailAlerts'] ?? true;

  bool get _mobileAlertsEnabled =>
      NotificationsSession.userSettings['mobileAlerts'] ?? true;

  bool get _emergencyAlertsEnabled =>
      NotificationsSession.userSettings['emergencyAlerts'] ?? true;


  // Runs once when this screen starts and prepares initial state.
  @override
  void initState() {
    super.initState();

    // Start all real-time Firebase listeners.
    _listenRealtime();

    // Periodically re-evaluate logic such as: no motion for 60 seconds, pressure continued for 60 seconds, temperature high for 60 seconds
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _evaluateAndAppendNotifications(fromTicker: true);
    }); //Timer.periodic
  }

// Internal helper method for the screen logic.
  void _listenRealtime() {
    // Listen for sensor data changes.
    _sensorsSub = sensorsDb.onValue.listen((event) {
      final raw = event.snapshot.value;

      // Safely convert raw snapshot into a Dart map.
      NotificationsSession.sensorsMap =
          raw is Map ? Map<String, dynamic>.from(raw) : {};

      // First sensor snapshot means loading is done.
      _loading = false;

      // Re-run notification evaluation after new data arrives.
      _evaluateAndAppendNotifications();
    });

    // Listen for system state changes.
    _systemSub = systemDb.onValue.listen((event) {
      final raw = event.snapshot.value;
      NotificationsSession.systemMap =
          raw is Map ? Map<String, dynamic>.from(raw) : {};
      _evaluateAndAppendNotifications();
    });

    // Listen for emergency state changes.
    _emergencySub = emergencyDb.onValue.listen((event) {
      final raw = event.snapshot.value;
      NotificationsSession.emergencyMap =
          raw is Map ? Map<String, dynamic>.from(raw) : {};
      _evaluateAndAppendNotifications();
    });

    // If a user is logged in, listen to their Firestore settings document.
    if (user != null) {
      _userSettingsSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .snapshots()
          .listen((event) {
        NotificationsSession.userSettings = event.data() ?? {};
        NotificationsSession.settingsLoaded = true;
        _evaluateAndAppendNotifications();
      });
    }
  }


// Internal helper method for the screen logic.
  void _evaluateAndAppendNotifications({bool fromTicker = false}) {
    // Current timestamp used as fallback when a sensor-specific timestamp is missing.
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Extract each sensor map safely from the shared sensors snapshot.
    final motionMap = NotificationsSession.sensorsMap['motion'] is Map
        ? Map<String, dynamic>.from(NotificationsSession.sensorsMap['motion'])
        : <String, dynamic>{};

    final doorMap = NotificationsSession.sensorsMap['door'] is Map
        ? Map<String, dynamic>.from(NotificationsSession.sensorsMap['door'])
        : <String, dynamic>{};

    final vibrationMap = NotificationsSession.sensorsMap['vibration'] is Map
        ? Map<String, dynamic>.from(NotificationsSession.sensorsMap['vibration'])
        : <String, dynamic>{};

    final temperatureMap = NotificationsSession.sensorsMap['temperature'] is Map
        ? Map<String, dynamic>.from(
            NotificationsSession.sensorsMap['temperature'],
          )
        : <String, dynamic>{};

    final pressure1Map = NotificationsSession.sensorsMap['pressure1'] is Map
        ? Map<String, dynamic>.from(NotificationsSession.sensorsMap['pressure1'])
        : <String, dynamic>{};

    final pressure2Map = NotificationsSession.sensorsMap['pressure2'] is Map
        ? Map<String, dynamic>.from(NotificationsSession.sensorsMap['pressure2'])
        : <String, dynamic>{};

    // Motion logic
    final motionStatus = (motionMap['status'] ?? '').toString().toLowerCase();
    final bool motionDetected = motionStatus == 'detected';

    // Try several possible timestamp fields because device data might be written under different names depending on the sender logic.
    final int motionTimestamp = _firstPositiveInt([
      motionMap['lastDetected'],
      motionMap['detectedAt'],
      motionMap['timestamp'],
      motionMap['lastUpdated'],
    ]);

    // If motion is detected now, refresh last seen motion time and reset the critical flag so a future no-motion period can generate a new alert.
    if (motionDetected) {
      NotificationsSession.lastMotionSeenMs =
          motionTimestamp > 0 ? motionTimestamp : nowMs;
      NotificationsSession.motionCriticalSent = false;
    } else {
      // If motion is not currently detected, keep the previous lastMotionSeenMs. But if it was never initialized and a valid timestamp exists, set it once.
      if (NotificationsSession.lastMotionSeenMs == 0 && motionTimestamp > 0) {
        NotificationsSession.lastMotionSeenMs = motionTimestamp;
      }
    }

    // Compute how many seconds passed since motion was last seen.
    final int noMotionSeconds = NotificationsSession.lastMotionSeenMs > 0
        ? DateTime.now()
            .difference(
              DateTime.fromMillisecondsSinceEpoch(
                NotificationsSession.lastMotionSeenMs,
              ),
            )
            .inSeconds
        : 0;

    // Door logic
    final rawDoorStatus =
        (doorMap['status'] ?? 'closed').toString().toLowerCase();
    String door = "closed";

    // This mapping intentionally flips the raw door values according to the project’s current sensor interpretation logic.
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

    // Timestamp used when creating door notifications.
    final int doorTimestamp = _firstPositiveInt([
      doorMap['timestamp'],
      doorMap['lastUpdated'],
      doorMap['lastDetected'],
    ]);

    // Vibration logic
    final vibrationStatus =
        (vibrationMap['status'] ?? '').toString().toLowerCase();
    final bool vibrationDetected = vibrationStatus == 'detected';

    final int vibrationTimestamp = _firstPositiveInt([
      vibrationMap['lastDetected'],
      vibrationMap['detectedAt'],
      vibrationMap['timestamp'],
      vibrationMap['lastUpdated'],
    ]);

    // Track the start time of a vibration period.
    if (vibrationDetected) {
      if (NotificationsSession.vibrationStartMs == 0) {
        NotificationsSession.vibrationStartMs =
            vibrationTimestamp > 0 ? vibrationTimestamp : nowMs;
      }
    } else {
      NotificationsSession.vibrationStartMs = 0;
    }

    // Temperature logic
    final double temperature = _asDouble(
      temperatureMap['celsius'] ??
          temperatureMap['value'] ??
          temperatureMap['bodyTemp'],
      fallback: 36.8,
    );

    // In this notification logic, only high temperature is tracked as critical.
    final bool tempHigh = temperature > 38.0;

    final int temperatureTimestamp = _firstPositiveInt([
      temperatureMap['lastDetected'],
      temperatureMap['lastUpdated'],
      temperatureMap['timestamp'],
    ]);

    // Track how long temperature has stayed high.
    if (tempHigh) {
      if (NotificationsSession.tempHighStartMs == 0) {
        NotificationsSession.tempHighStartMs =
            temperatureTimestamp > 0 ? temperatureTimestamp : nowMs;
      }
    } else {
      // Reset timers/flags when temperature returns to normal.
      NotificationsSession.tempHighStartMs = 0;
      NotificationsSession.tempCriticalSent = false;
    }

    final int tempHighSeconds = NotificationsSession.tempHighStartMs > 0
        ? DateTime.now()
            .difference(
              DateTime.fromMillisecondsSinceEpoch(
                NotificationsSession.tempHighStartMs,
              ),
            )
            .inSeconds
        : 0;

    // Pressure logic
    final String p1Status =
        (pressure1Map['status'] ?? '').toString().toLowerCase();
    final String p2Status =
        (pressure2Map['status'] ?? '').toString().toLowerCase();
    final bool pressureDetected = p1Status == 'pressed' || p2Status == 'pressed';

    // Track how long continuous pressure has been active.
    if (pressureDetected) {
      if (NotificationsSession.pressureStartMs == 0) {
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
        NotificationsSession.pressureStartMs =
            pressureTimestamp > 0 ? pressureTimestamp : nowMs;
      }
    } else {
      NotificationsSession.pressureStartMs = 0;
      NotificationsSession.pressureCriticalSent = false;
    }

    final int pressureSeconds = NotificationsSession.pressureStartMs > 0
        ? DateTime.now()
            .difference(
              DateTime.fromMillisecondsSinceEpoch(
                NotificationsSession.pressureStartMs,
              ),
            )
            .inSeconds
        : 0;

    // System and emergency logic
    final int systemTimestamp = _normalizeTimestamp(
      NotificationsSession.systemMap['timestamp'] ??
          NotificationsSession.systemMap['lastUpdate'] ??
          NotificationsSession.systemMap['time'],
    );

    final bool alarmOn = _asBool(
      NotificationsSession.systemMap['alarmOn'] ??
          NotificationsSession.systemMap['alarm'] ??
          NotificationsSession.systemMap['isAlarmOn'],
    );

    final int emergencyTimestamp = _normalizeTimestamp(
      NotificationsSession.emergencyMap['timestamp'] ??
          NotificationsSession.emergencyMap['lastUpdate'] ??
          NotificationsSession.emergencyMap['time'],
    );

    final bool emergencyOn = _asBool(
      NotificationsSession.emergencyMap['active'] ??
          NotificationsSession.emergencyMap['isActive'] ??
          NotificationsSession.emergencyMap['triggered'] ??
          NotificationsSession.emergencyMap['emergencyOn'] ??
          NotificationsSession.emergencyMap['calling'] ??
          NotificationsSession.emergencyMap['isCalling'] ??
          NotificationsSession.emergencyMap['callActive'],
    );

    // On the first run, initialize all previous states without generating notifications.
    // This prevents false "change" notifications on initial load.
    if (!NotificationsSession.initialized) {
      NotificationsSession.prevMotionDetected = motionDetected;
      NotificationsSession.prevDoorState = door;
      NotificationsSession.prevPressureDetected = pressureDetected;
      NotificationsSession.prevAlarmOn = alarmOn;
      NotificationsSession.prevEmergencyOn = emergencyOn;
      NotificationsSession.prevTempHigh = tempHigh;
      NotificationsSession.prevVibrationDetected = vibrationDetected;
      NotificationsSession.initialized = true;

      if (mounted) setState(() {});
      return;
    }

    // Track whether anything changed that requires rebuilding the UI.
    bool changed = false;

    // Notification generation rules

    // Motion started
    if (NotificationsSession.prevMotionDetected != motionDetected &&
        motionDetected) {
      _addNotification(
        Notif(
          title: "Motion Detected",
          desc: "Motion sensor detected activity.",
          time: _formatRelative(
            NotificationsSession.lastMotionSeenMs > 0
                ? NotificationsSession.lastMotionSeenMs
                : nowMs,
          ),
          icon: Icons.directions_walk,
          timestamp: NotificationsSession.lastMotionSeenMs > 0
              ? NotificationsSession.lastMotionSeenMs
              : nowMs,
          type: 'motion',
          label: 'Normal',
          level: NotifLevel.normal,
          sensorDetails: 'Sensor: motion • State: detected',
        ),
      );
      changed = true;
    }

    // No motion for at least 1 minute
    if (!motionDetected &&
        NotificationsSession.lastMotionSeenMs > 0 &&
        noMotionSeconds >= 60 &&
        !NotificationsSession.motionCriticalSent) {
      final int criticalMotionTime =
          NotificationsSession.lastMotionSeenMs + 60000;
      _addNotification(
        Notif(
          title: "No Motion Detected",
          desc: "No motion has been detected for 1 minute.",
          time: _formatRelative(criticalMotionTime),
          icon: Icons.directions_walk,
          timestamp: criticalMotionTime,
          type: 'motion',
          label: 'Critical',
          level: NotifLevel.critical,
          sensorDetails: 'Sensor: motion • Inactivity: 1 min',
        ),
      );
      NotificationsSession.motionCriticalSent = true;
      changed = true;
    }

    // Door opened
    if (NotificationsSession.prevDoorState != door && door == 'open') {
      _addNotification(
        Notif(
          title: "Door Opened",
          desc: "Door is open and needs attention.",
          time: _formatRelative(doorTimestamp > 0 ? doorTimestamp : nowMs),
          icon: Icons.door_front_door,
          timestamp: doorTimestamp > 0 ? doorTimestamp : nowMs,
          type: 'door',
          label: 'Critical',
          level: NotifLevel.critical,
          sensorDetails: 'Sensor: door • State: open',
        ),
      );
      changed = true;
    }

    // Door closed
    if (NotificationsSession.prevDoorState != door && door == 'closed') {
      _addNotification(
        Notif(
          title: "Door Closed",
          desc: "Door is closed normally.",
          time: _formatRelative(doorTimestamp > 0 ? doorTimestamp : nowMs),
          icon: Icons.door_front_door,
          timestamp: doorTimestamp > 0 ? doorTimestamp : nowMs,
          type: 'door',
          label: 'Low Attention',
          level: NotifLevel.low,
          sensorDetails: 'Sensor: door • State: closed',
        ),
      );
      changed = true;
    }

    // Vibration started
    if (NotificationsSession.prevVibrationDetected != vibrationDetected &&
        vibrationDetected) {
      _addNotification(
        Notif(
          title: "Vibration Detected",
          desc: "Vibration detected and needs attention.",
          time: _formatRelative(vibrationTimestamp > 0 ? vibrationTimestamp : nowMs),
          icon: Icons.vibration,
          timestamp: vibrationTimestamp > 0 ? vibrationTimestamp : nowMs,
          type: 'vibration',
          label: 'Critical',
          level: NotifLevel.critical,
          sensorDetails: 'Sensor: vibration • State: detected',
        ),
      );
      changed = true;
    }

    // Vibration stopped
    if (NotificationsSession.prevVibrationDetected != vibrationDetected &&
        !vibrationDetected) {
      _addNotification(
        Notif(
          title: "Vibration Stopped",
          desc: "No vibration is currently detected.",
          time: _formatRelative(vibrationTimestamp > 0 ? vibrationTimestamp : nowMs),
          icon: Icons.vibration,
          timestamp: vibrationTimestamp > 0 ? vibrationTimestamp : nowMs,
          type: 'vibration',
          label: 'Low Attention',
          level: NotifLevel.low,
          sensorDetails: 'Sensor: vibration • State: stopped',
        ),
      );
      changed = true;
    }

    // Pressure first detected
    if (pressureDetected &&
        NotificationsSession.prevPressureDetected != pressureDetected) {
      _addNotification(
        Notif(
          title: "Pressure Detected",
          desc: "Pressure is detected but less than 1 minute.",
          time: _formatRelative(
            NotificationsSession.pressureStartMs > 0
                ? NotificationsSession.pressureStartMs
                : nowMs,
          ),
          icon: Icons.event_seat,
          timestamp: NotificationsSession.pressureStartMs > 0
              ? NotificationsSession.pressureStartMs
              : nowMs,
          type: 'pressure',
          label: 'Normal',
          level: NotifLevel.normal,
          sensorDetails: 'Sensor: pressure • Active now',
        ),
      );
      changed = true;
    }

    // Pressure continued for 1 minute
    if (pressureDetected &&
        NotificationsSession.pressureStartMs > 0 &&
        pressureSeconds >= 60 &&
        !NotificationsSession.pressureCriticalSent) {
      final int criticalPressureTime =
          NotificationsSession.pressureStartMs + 60000;
      _addNotification(
        Notif(
          title: "Pressure Detected",
          desc: "Pressure has continued for 1 minute.",
          time: _formatRelative(criticalPressureTime),
          icon: Icons.event_seat,
          timestamp: criticalPressureTime,
          type: 'pressure',
          label: 'Critical',
          level: NotifLevel.critical,
          sensorDetails: 'Sensor: pressure • Continuous for 1 min',
        ),
      );
      NotificationsSession.pressureCriticalSent = true;
      changed = true;
    }

    // Temperature returned to normal
    if (NotificationsSession.prevTempHigh != tempHigh && !tempHigh) {
      _addNotification(
        Notif(
          title: "Temperature Normal",
          desc: "Temperature is within the normal range.",
          time: _formatRelative(temperatureTimestamp > 0 ? temperatureTimestamp : nowMs),
          icon: Icons.thermostat,
          timestamp: temperatureTimestamp > 0 ? temperatureTimestamp : nowMs,
          type: 'temperature',
          label: 'Low Attention',
          level: NotifLevel.low,
          sensorDetails: 'Sensor: temperature • ${temperature.toStringAsFixed(1)}°C',
        ),
      );
      changed = true;
    }

    // Temperature stayed high for 1 minute
    if (tempHigh &&
        NotificationsSession.tempHighStartMs > 0 &&
        tempHighSeconds >= 60 &&
        !NotificationsSession.tempCriticalSent) {
      final int criticalTempTime =
          NotificationsSession.tempHighStartMs + 60000;
      _addNotification(
        Notif(
          title: "Temperature High",
          desc: "Temperature stayed high for 1 minute straight.",
          time: _formatRelative(criticalTempTime),
          icon: Icons.thermostat,
          timestamp: criticalTempTime,
          type: 'temperature',
          label: 'Critical',
          level: NotifLevel.critical,
          sensorDetails: 'Sensor: temperature • ${temperature.toStringAsFixed(1)}°C',
        ),
      );
      NotificationsSession.tempCriticalSent = true;
      changed = true;
    }

    // Alarm triggered
    if (NotificationsSession.prevAlarmOn != alarmOn && alarmOn) {
      _addNotification(
        Notif(
          title: "Alarm Triggered",
          desc: "Emergency alarm is currently active.",
          time: _formatRelative(systemTimestamp > 0 ? systemTimestamp : nowMs),
          icon: Icons.notifications_active,
          timestamp: systemTimestamp > 0 ? systemTimestamp : nowMs,
          type: 'alarm',
          label: 'Critical',
          level: NotifLevel.critical,
          sensorDetails: 'Sensor: alarm • State: on',
        ),
      );
      changed = true;
    }

    // Alarm stopped
    if (NotificationsSession.prevAlarmOn != alarmOn && !alarmOn) {
      _addNotification(
        Notif(
          title: "Alarm Stopped",
          desc: "Emergency alarm has been stopped.",
          time: _formatRelative(systemTimestamp > 0 ? systemTimestamp : nowMs),
          icon: Icons.notifications_active,
          timestamp: systemTimestamp > 0 ? systemTimestamp : nowMs,
          type: 'alarm',
          label: 'Normal',
          level: NotifLevel.normal,
          sensorDetails: 'Sensor: alarm • State: stopped',
        ),
      );
      changed = true;
    }

    // Emergency calling became active
    if (NotificationsSession.prevEmergencyOn != emergencyOn && emergencyOn) {
      _addNotification(
        Notif(
          title: "Emergency Calling",
          desc: "Emergency calling is active.",
          time: _formatRelative(emergencyTimestamp > 0 ? emergencyTimestamp : nowMs),
          icon: Icons.call,
          timestamp: emergencyTimestamp > 0 ? emergencyTimestamp : nowMs,
          type: 'emergency',
          label: 'Critical',
          level: NotifLevel.critical,
          sensorDetails: 'Sensor: emergency • Calling active',
        ),
      );
      changed = true;
    }

    // Save current values as previous states for the next comparison cycle.
    NotificationsSession.prevMotionDetected = motionDetected;
    NotificationsSession.prevDoorState = door;
    NotificationsSession.prevPressureDetected = pressureDetected;
    NotificationsSession.prevAlarmOn = alarmOn;
    NotificationsSession.prevEmergencyOn = emergencyOn;
    NotificationsSession.prevTempHigh = tempHigh;
    NotificationsSession.prevVibrationDetected = vibrationDetected;

    // Rebuild only when needed.
    if (changed && mounted) {
      setState(() {});
    } else if (!fromTicker && mounted) {
      setState(() {});
    }
  }

  // Handles an action, backend update, or user request for this screen.
  void _addNotification(Notif notification) {
    // If emergency alerts are disabled, suppress critical notifications entirely.
    if (notification.level == NotifLevel.critical && !_emergencyAlertsEnabled) {
      return;
    }

    final String newKey = notification.key;

    // Prevent duplicate notifications from being inserted repeatedly
    // within a very short time window.
    if (_notifications.isNotEmpty) {
      final latest = _notifications.first;
      if (latest.key == newKey &&
          (notification.timestamp - latest.timestamp).abs() < 3000) {
        return;
      }
    }

    // Insert newest notification at the top.
    _notifications.insert(0, notification);

    // Limit memory growth by keeping only the latest 200 notifications.
    if (_notifications.length > 200) {
      _notifications.removeRange(200, _notifications.length);
    }
  }

  // Releases resources here to avoid memory leaks.
  @override
  void dispose() {
    // Cancel all listeners/timers when the screen is disposed.
    _sensorsSub?.cancel();
    _systemSub?.cancel();
    _emergencySub?.cancel();
    _userSettingsSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  // Main build method that returns the widget tree for the screen.
  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Show a loading indicator only during the initial load when there are still no notifications to show.
    if (_loading && _notifications.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Split notifications into visual sections by severity level.
    final critical =
        _notifications.where((n) => n.level == NotifLevel.critical).toList();
    final normal =
        _notifications.where((n) => n.level == NotifLevel.normal).toList();
    final low = _notifications.where((n) => n.level == NotifLevel.low).toList();

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left column: Critical notifications
            Expanded(
              child: _columnCard(
                title: "Critical",
                titleColor: Colors.red,
                icon: Icons.warning_amber_rounded,
                child: critical.isEmpty
                    ? const _EmptyState(text: "No critical alerts")
                    : Column(
                        children: critical
                            .map(
                              (n) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _notifTile(n),
                              ),
                            )
                            .toList(),
                      ),
              ),
            ),
            const SizedBox(width: 12),

            // Right column: Normal and Low Attention notifications
            Expanded(
              child: Column(
                children: [
                  _columnCard(
                    title: "Normal",
                    titleColor: NotificationsScreen.softBlue,
                    icon: Icons.notifications_active_outlined,
                    child: normal.isEmpty
                        ? const _EmptyState(text: "No normal alerts")
                        : Column(
                            children: normal
                                .map(
                                  (n) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _notifTile(n),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                  const SizedBox(height: 12),
                  _columnCard(
                    title: "Low Attention",
                    titleColor: NotificationsScreen.green,
                    icon: Icons.done_all,
                    child: low.isEmpty
                        ? const _EmptyState(text: "No low-attention alerts")
                        : Column(
                            children: low
                                .map(
                                  (n) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _notifTile(n),
                                  ),
                                )
                                .toList(),
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


  // Helper function used to convert, format, or prepare data for display.
  static int _firstPositiveInt(List<dynamic> values) {
    // Returns the first valid positive timestamp found in the list.
    for (final value in values) {
      final int parsed = _normalizeTimestamp(value);
      if (parsed > 0) return parsed;
    }
    return 0;
  }


  // Helper function used to convert, format, or prepare data for display.
  static double _asDouble(dynamic value, {double fallback = 0.0}) {
    // Safely converts dynamic numeric input into double.
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  // Helper function used to convert, format, or prepare data for display.
  static bool _asBool(dynamic value) {
    // Safely converts several database representations into a boolean.
    if (value is bool) return value;

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
  static int _normalizeTimestamp(dynamic value) {
    if (value == null) return 0;

    if (value is DateTime) return value.millisecondsSinceEpoch;

    if (value is int) {
      if (value > 0 && value < 1000000000000) return value * 1000;
      return value;
    }

    if (value is double) {
      final parsed = value.toInt();
      if (parsed > 0 && parsed < 1000000000000) return parsed * 1000;
      return parsed;
    }

    final text = value.toString().trim();
    if (text.isEmpty || text == '0') return 0;

    final parsedDate = DateTime.tryParse(text);
    if (parsedDate != null) return parsedDate.millisecondsSinceEpoch;

    final parsed = int.tryParse(text) ?? 0;
    if (parsed <= 0) return 0;
    if (parsed < 1000000000000) return parsed * 1000;
    return parsed;
  }

  // Helper function used to convert, format, or prepare data for display.
  static String _formatRelative(int timestampMs) {
    // Converts absolute timestamps into compact relative text.
    if (timestampMs <= 0) return "Now";

    final now = DateTime.now();
    final time = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final diff = now.difference(time);

    if (diff.isNegative) return "Now";

    if (diff.inSeconds < 60) {
      return "${diff.inSeconds}s ago";
    }

    if (diff.inMinutes < 60) {
      return "${diff.inMinutes}m ago";
    }

    if (diff.inHours < 24) {
      return "${diff.inHours}h ago";
    }

    return "${diff.inDays}d ago";
  }

  // Internal helper method for the screen logic.
  static Color _colorForLevel(NotifLevel level) {
    // Maps a notification level to its main accent color.
    switch (level) {
      case NotifLevel.critical:
        return Colors.red;
      case NotifLevel.normal:
        return NotificationsScreen.softBlue;
      case NotifLevel.low:
        return NotificationsScreen.green;
    }
  }

  // Internal helper method for the screen logic.
  static Color _bgForLevel(NotifLevel level) {
    // Maps a notification level to a matching soft background color.
    switch (level) {
      case NotifLevel.critical:
        return const Color(0xFFFFE9E9);
      case NotifLevel.normal:
        return const Color(0xFFEAF3FF);
      case NotifLevel.low:
        return const Color(0xFFEAF7EE);
    }
  }

  // Internal helper method for the screen logic.
  static Widget _columnCard({
    required String title,
    required Color titleColor,
    required IconData icon,
    required Widget child,
  }) {
    // Reusable container for each notification group column.
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              color: Color(0x11000000),
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row with icon + text
            Row(
              children: [
                Icon(icon, color: titleColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  // Internal helper method for the screen logic.
  static Widget _notifTile(Notif n) {
    // Each tile is styled according to its notification level.
    final Color accent = _colorForLevel(n.level);
    final Color bg = _bgForLevel(n.level);

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withOpacity(0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left icon container
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(n.icon, color: accent),
            ),
            const SizedBox(width: 10),

            // Right content section
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row + severity label badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: NotificationsScreen.navy,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          n.label,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Notification description
                  Text(
                    n.desc,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 5),

                  // Sensor detail line
                  Text(
                    n.sensorDetails,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Relative timestamp
                  Text(
                    _formatRelative(n.timestamp),
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
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


// _EmptyState
// Main widget/class definition for this part of the app.
class _EmptyState extends StatelessWidget {
  final String text;

  const _EmptyState({required this.text});

  // Main build method that returns the widget tree for the screen.
  @override
  Widget build(BuildContext context) {
    // Simple placeholder shown when a notification section is empty.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 12,
        ),
      ),
    );
  }
}

// Notification severity levels used throughout the screen.
enum NotifLevel {
  critical,
  normal,
  low,
}

// Notification data model.
// Each notification stores both visual information for the UI and structured metadata for duplicate prevention and categorization.
class Notif {
  final String title;
  final String desc;
  final String time;
  final IconData icon;
  final int timestamp;
  final String type;
  final String label;
  final NotifLevel level;
  final String sensorDetails;

  const Notif({
    required this.title,
    required this.desc,
    required this.time,
    required this.icon,
    required this.timestamp,
    required this.type,
    required this.label,
    required this.level,
    required this.sensorDetails,
  });

  // Unique key used to compare notifications and suppress duplicates.
  String get key =>
      '$title|$desc|$timestamp|$type|$label|${level.name}|$sensorDetails';
}