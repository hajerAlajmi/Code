// Imports
// Packages and project files used by this screen.
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'assistant_page.dart';


// DashboardScreen
// Main widget/class definition for this part of the app.
// This screen shows the main live dashboard of the monitoring system. It listens to realtime sensor data and system status,
// applies the app's alert logic, then displays readable sensor cards, summary cards, insights, and a shortcut to the assistant page.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  // Main accent color used in icons, badges, and charts.
  static const softBlue = Color(0xFF4A90E2);

  // Main dark navy used in headings and strong text.
  static const navy = Color(0xFF0D1B2A);

  // Light blue card background often used for neutral/safe information.
  static const lightBlueBg = Color(0xFFEAF3FF);

  // Light red background used behind emergency cards.
  static const lightRedBg = Color(0xFFFFE9E9);

  // Light green background used behind safe/normal cards.
  static const lightGreenBg = Color(0xFFEAF7EE);

  // Light yellow background used behind warning cards.
  static const lightYellowBg = Color(0xFFFFF4D6);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}


// _DashboardScreenState
// Main widget/class definition for this part of the app.


// State class that holds live values, controllers, and UI logic for the screen.
class _DashboardScreenState extends State<DashboardScreen> {
  
    // Firebase database references used to read or update live data.
    // db listens to the sensors branch.
    // systemDb listens to the system branch for values like alarmOn.
  final DatabaseReference db = FirebaseDatabase.instance.ref('sensors');
  final DatabaseReference systemDb = FirebaseDatabase.instance.ref('system');

  // Stores the last timestamp when motion was seen.
  // This is important because the app does not only care whether
  // motion is currently detected, but also how long it has been absent.
  int _lastMotionSeenMs = 0;

  // Stores the start time of a pressure event.
  // This is used to calculate how long pressure has been continuously active.
  int _pressureStartMs = 0;

  // Stores the last sync timestamp shown to the user.
  // It is updated whenever sensor snapshots change or fresher timestamps appear.
  int _lastSyncMs = 0;

  // Stores a compact fingerprint of the last sensor snapshot.
  // This makes it easy to tell if anything meaningful changed.
  String _lastSnapshotKey = '';

  // Main build method that returns the widget tree for the screen.
  @override
  Widget build(BuildContext context) {
    // First stream listens to all live sensor data.
    return StreamBuilder<DatabaseEvent>(
      stream: db.onValue,
      builder: (context, snapshot) {

        // Second stream listens to the system branch.
        // This includes values such as alarm state.
        return StreamBuilder<DatabaseEvent>(
          stream: systemDb.onValue,
          builder: (context, systemSnapshot) {

            // Third stream ticks every second.
            // This is very important because some UI values
            // depend on elapsed time, like: no motion for 1 minute, pressure for 1 minute, sync freshness text
            // Without this periodic rebuild, those timers would not update
            // unless the database value changed again.
            return StreamBuilder<int>(
              stream: Stream<int>.periodic(
                const Duration(seconds: 1),
                (count) => count,
              ), //Stream.periodic
              builder: (context, _) {
                // Default values used before live data is parsed.
                bool motionDetected = false;
                String door = "closed";
                bool vibrationDetected = false;
                double temperature = 36.8;
                bool pressureDetected = false;
                bool alarmOn = false;
                bool cameraOnline = true;

                // Timestamp used for temperature range duration logic.
                int temperatureStateMs = 0;

                // Maps for raw sensor/system sections.
                // These are later passed to the assistant context too.
                Map<String, dynamic> motionMap = {};
                Map<String, dynamic> doorMap = {};
                Map<String, dynamic> vibrationMap = {};
                Map<String, dynamic> temperatureMap = {};
                Map<String, dynamic> pressure1Map = {};
                Map<String, dynamic> pressure2Map = {};
                Map<String, dynamic> cameraMap = {};
                Map<String, dynamic> systemMap = {};

                // Parse sensor data when available.
                if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                  final raw = snapshot.data!.snapshot.value as Map;
                  final sensors = Map<String, dynamic>.from(raw);

                  // Safely extract each sensor block.
                  // If a block is missing or malformed, fall back to empty map so the screen does not crash.
                  motionMap = sensors['motion'] is Map
                      ? Map<String, dynamic>.from(sensors['motion'])
                      : <String, dynamic>{};

                  doorMap = sensors['door'] is Map
                      ? Map<String, dynamic>.from(sensors['door'])
                      : <String, dynamic>{};

                  vibrationMap = sensors['vibration'] is Map
                      ? Map<String, dynamic>.from(sensors['vibration'])
                      : <String, dynamic>{};

                  temperatureMap = sensors['temperature'] is Map
                      ? Map<String, dynamic>.from(sensors['temperature'])
                      : <String, dynamic>{};

                  pressure1Map = sensors['pressure1'] is Map
                      ? Map<String, dynamic>.from(sensors['pressure1'])
                      : <String, dynamic>{};

                  pressure2Map = sensors['pressure2'] is Map
                      ? Map<String, dynamic>.from(sensors['pressure2'])
                      : <String, dynamic>{};

                  cameraMap = sensors['camera'] is Map
                      ? Map<String, dynamic>.from(sensors['camera'])
                      : <String, dynamic>{};

                  // Normalize motion status and convert it into a bool.
                  final motionStatus =
                      (motionMap['status'] ?? '').toString().toLowerCase();
                  motionDetected = motionStatus == 'detected';

                  // Read raw door status.
                  final rawDoorStatus =
                      (doorMap['status'] ?? 'closed').toString().toLowerCase();

                  // Convert the raw door state into the app's expected meaning.
                  // This logic intentionally flips some values because of how the physical sensor wiring/logic is currently represented.
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

                  // Normalize vibration status and convert to boolean.
                  final vibrationStatus =
                      (vibrationMap['status'] ?? '').toString().toLowerCase();
                  vibrationDetected = vibrationStatus == 'detected';

                  // Read temperature from whichever field is available.
                  // Different sensor writes may use different keys,so this method tries several options.
                  temperature = _asDouble(
                    temperatureMap['celsius'] ??
                        temperatureMap['value'] ??
                        temperatureMap['bodyTemp'],
                    fallback: 36.8,
                  );

                  // Pressure is active if either pressure sensor says "pressed".
                  final p1Status =
                      (pressure1Map['status'] ?? '').toString().toLowerCase();
                  final p2Status =
                      (pressure2Map['status'] ?? '').toString().toLowerCase();
                  pressureDetected = p1Status == 'pressed' || p2Status == 'pressed';

                  // Determine camera online state from its latest timestamp.
                  final int cameraLastSeen = _asInt(
                    cameraMap['lastSeen'] ??
                        cameraMap['lastUpdated'] ??
                        cameraMap['timestamp'],
                  );

                  final int cameraNowMs = DateTime.now().millisecondsSinceEpoch;

                  // Camera is considered online only if it reported recently.
                  // Here the threshold is 10 seconds.
                  cameraOnline =
                      cameraLastSeen > 0 && (cameraNowMs - cameraLastSeen) <= 10000;

                  final int nowMs = DateTime.now().millisecondsSinceEpoch;

                  // Best effort timestamp for motion activity.
                  final int motionTimestamp = _asInt(
                    motionMap['lastDetected'] ??
                        motionMap['detectedAt'] ??
                        motionMap['timestamp'],
                  );

                  // Keep track of when motion was last seen.
                  if (motionDetected) {
                    _lastMotionSeenMs = motionTimestamp > 0 ? motionTimestamp : nowMs;
                  } else {
                    // If motion is not currently detected, preserve the old timestamp unless it was never set.
                    if (_lastMotionSeenMs == 0 && motionTimestamp > 0) {
                      _lastMotionSeenMs = motionTimestamp;
                    }
                  }

                  // Manage pressure start timestamp.
                  // This allows the app to measure how long pressure lasted.
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
                    // Reset timer when pressure is no longer active.
                    _pressureStartMs = 0;
                  }

                  // Timestamp used to know how long temperature has stayed abnormal.
                  temperatureStateMs = _asInt(
                    temperatureMap['lastDetected'] ?? temperatureMap['lastUpdated'],
                  );

                  // Build a compact fingerprint string from the most important values.
                  // This is used to detect whether the sensor snapshot changed.
                  final String snapshotKey = [
                    motionStatus,
                    rawDoorStatus,
                    vibrationStatus,
                    temperature.toStringAsFixed(1),
                    p1Status,
                    p2Status,
                    cameraOnline.toString(),
                  ].join('|');

                  // If this is the first snapshot, store it and set sync time.
                  if (_lastSnapshotKey.isEmpty) {
                    _lastSnapshotKey = snapshotKey;
                    _lastSyncMs = nowMs;
                  } else if (_lastSnapshotKey != snapshotKey) {
                    /// If snapshot changed, refresh last sync time.
                    _lastSnapshotKey = snapshotKey;
                    _lastSyncMs = nowMs;
                  }

                  // Find the freshest sensor update timestamp among all major sensor nodes.
                  final int sensorTimestamp = _maxInt(
                    _asInt(motionMap['lastUpdated']),
                    _maxInt(
                      _asInt(doorMap['lastUpdated']),
                      _maxInt(
                        _asInt(vibrationMap['lastUpdated']),
                        _maxInt(
                          _asInt(temperatureMap['lastUpdated']),
                          _maxInt(
                            _asInt(pressure1Map['lastUpdated']),
                            _maxInt(
                              _asInt(pressure2Map['lastUpdated']),
                              _asInt(cameraMap['lastUpdated']),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );

                  // If this timestamp is newer, use it as the sync time.
                  if (sensorTimestamp > _lastSyncMs) {
                    _lastSyncMs = sensorTimestamp;
                  }
                }

                // Parse system data when available.
                if (systemSnapshot.hasData &&
                    systemSnapshot.data!.snapshot.value != null) {
                  final rawSystem = systemSnapshot.data!.snapshot.value as Map;
                  systemMap = Map<String, dynamic>.from(rawSystem);

                  // Alarm state is part of overall emergency logic.
                  alarmOn = _asBool(systemMap['alarmOn']);
                }

                final now = DateTime.now();

                // Time since motion was last seen.
                final int noMotionMinutes = _lastMotionSeenMs > 0
                    ? now
                        .difference(DateTime.fromMillisecondsSinceEpoch(_lastMotionSeenMs))
                        .inMinutes
                    : 0;

                // Motion logic: yellow is not used here right now, red becomes true if no motion lasted at least 1 minute.
                final bool motionYellow = false;
                final bool motionRed =
                    !motionDetected && _lastMotionSeenMs > 0 && noMotionMinutes >= 1;

                // Door open means emergency.
                final bool doorRed = door == "open";

                // Any vibration detected means emergency.
                final bool vibrationRed = vibrationDetected;

                // Temperature range logic.
                final bool highTemperature = temperature > 38.0;
                final bool lowTemperature = temperature < 36.0;
                final bool tempOutOfRange = highTemperature || lowTemperature;

                // Duration of abnormal temperature state.
                final int tempOutMinutes = temperatureStateMs > 0
                    ? now
                        .difference(
                          DateTime.fromMillisecondsSinceEpoch(temperatureStateMs),
                        )
                        .inMinutes
                    : 0;

                // Temperature warning before 3 minutes,
                // then emergency after 3 minutes.
                final bool tempYellow =
                    tempOutOfRange && temperatureStateMs > 0 && tempOutMinutes < 3;

                final bool tempRed =
                    tempOutOfRange && temperatureStateMs > 0 && tempOutMinutes >= 3;

                // Duration of pressure event.
                final int pressureMinutes = _pressureStartMs > 0
                    ? now
                        .difference(
                          DateTime.fromMillisecondsSinceEpoch(_pressureStartMs),
                        )
                        .inMinutes
                    : 0;

                // Pressure warning is not used right now.
                // Pressure emergency becomes true after 1 minute.
                final bool pressureYellow = false;
                final bool pressureRed =
                    pressureDetected && _pressureStartMs > 0 && pressureMinutes >= 1;

                // Friendly UI text values for cards.
                final String motionText = motionDetected ? "Moving" : "No Motion";
                final String doorText = door == "open" ? "Open" : "Closed";
                final String pressureText =
                    pressureDetected ? "Pressure Detected" : "No Pressure";

                // Wrap each sensor state in a reusable label+color object
                // to simplify UI building.
                final _StatusInfo motionInfo = motionRed
                    ? const _StatusInfo("Emergency", Colors.red)
                    : motionYellow
                        ? const _StatusInfo("Warning", Colors.orange)
                        : const _StatusInfo("Normal", Colors.green);

                final _StatusInfo doorInfo = doorRed
                    ? const _StatusInfo("Emergency", Colors.red)
                    : const _StatusInfo("Normal", Colors.green);

                final _StatusInfo vibrationInfo = vibrationRed
                    ? const _StatusInfo("Emergency", Colors.red)
                    : const _StatusInfo("Normal", Colors.green);

                final _StatusInfo tempInfo = tempRed
                    ? const _StatusInfo("Emergency", Colors.red)
                    : tempYellow
                        ? const _StatusInfo("Warning", Colors.orange)
                        : const _StatusInfo("Normal", Colors.green);

                final _StatusInfo pressureInfo = pressureRed
                    ? const _StatusInfo("Emergency", Colors.red)
                    : pressureYellow
                        ? const _StatusInfo("Warning", Colors.orange)
                        : const _StatusInfo("Normal", Colors.green);

                // Overall dashboard status is emergency if any red condition exists.
                final bool hasRed =
                    alarmOn || motionRed || doorRed || vibrationRed || tempRed || pressureRed;

                // Overall warning state if no red exists but yellow does.
                final bool hasYellow =
                    motionYellow || tempYellow || pressureYellow;

                // Final overall status text.
                final String overallStatus = hasRed
                    ? "Attention Needed"
                    : hasYellow
                        ? "Warning"
                        : "Safe";

                // Colors/backgrounds/badges used by summary UI cards.
                final Color overallColor = hasRed
                    ? Colors.red
                    : hasYellow
                        ? Colors.orange
                        : Colors.green;

                final Color overallBg = hasRed
                    ? DashboardScreen.lightRedBg
                    : hasYellow
                        ? DashboardScreen.lightYellowBg
                        : DashboardScreen.lightGreenBg;

                final String overallBadge = hasRed
                    ? "Emergency"
                    : hasYellow
                        ? "Warning"
                        : "OK";

                // Human-readable notes used in sensor cards and assistant context.
                final String motionNote = motionRed
                    ? "No motion has been detected for one minute."
                    : "Motion is within normal condition.";

                final String doorNote = doorRed
                    ? "Front door is open and needs attention."
                    : "Door is closed normally.";

                final String vibrationNote = vibrationRed
                    ? "Vibration detected and needs immediate attention."
                    : "No abnormal vibration condition.";

                final String tempCondition = highTemperature
                    ? "Above 38°C"
                    : lowTemperature
                        ? "Below 36°C"
                        : "Normal range";

                final String tempNote = tempRed
                    ? "Temperature stayed outside the normal range for 3 minutes."
                    : tempYellow
                        ? "Temperature is outside the normal range."
                        : "Temperature is within normal range.";

                final String pressureNote = pressureRed
                    ? "Pressure has continued for one minute."
                    : "Pressure is within normal condition.";

                // Sync status is presented both as relative text and a labeled badge.
                final _StatusInfo syncInfo = _buildSyncInfo(_lastSyncMs);
                final String lastSyncText = _formatRelative(_lastSyncMs);

                // Activity levels used for progress bars in the insights section.
                // These are visual summaries, not raw sensor values.
                final double motionLevel = motionRed
                    ? 0.95
                    : motionDetected
                        ? 0.90
                        : 0.22;

                final double doorLevel = doorRed ? 0.95 : 0.18;
                final double vibrationLevel = vibrationRed ? 0.95 : 0.18;
                final double temperatureLevel = tempRed
                    ? 0.95
                    : tempYellow
                        ? 0.65
                        : 0.22;
                final double pressureLevel = pressureRed
                    ? 0.95
                    : pressureDetected
                        ? 0.65
                        : 0.18;

                // Build chart bars for the motion diagram.
                final List<double> motionChartData = _buildMotionRealtimeBars(
                  motionDetected: motionDetected,
                  lastMotionMs: _lastMotionSeenMs,
                  now: now,
                );

                // Context object passed to the assistant page.
                // This makes the assistant aware of current dashboard state without needing to read the UI directly.
                final Map<String, dynamic> liveAssistantContext = {
                  "page": "dashboard",
                  "overall": {
                    "status": overallStatus,
                    "badge": overallBadge,
                    "hasRed": hasRed,
                    "hasYellow": hasYellow,
                    "alarmOn": alarmOn,
                  },
                  "sensors": {
                    "motion": {
                      "detected": motionDetected,
                      "statusText": motionText,
                      "noMotionMinutes": noMotionMinutes,
                      "note": motionNote,
                      "raw": motionMap,
                    },
                    "door": {
                      "state": door,
                      "statusText": doorText,
                      "note": doorNote,
                      "raw": doorMap,
                    },
                    "vibration": {
                      "detected": vibrationDetected,
                      "note": vibrationNote,
                      "raw": vibrationMap,
                    },
                    "temperature": {
                      "value": temperature,
                      "condition": tempCondition,
                      "high": highTemperature,
                      "low": lowTemperature,
                      "warning": tempYellow,
                      "emergency": tempRed,
                      "note": tempNote,
                      "raw": temperatureMap,
                    },
                    "pressure": {
                      "detected": pressureDetected,
                      "minutes": pressureMinutes,
                      "note": pressureNote,
                      "raw1": pressure1Map,
                      "raw2": pressure2Map,
                    },
                    "camera": {
                      "online": cameraOnline,
                      "raw": cameraMap,
                    },
                  },
                  "system": {
                    "alarmOn": alarmOn,
                    "lastSyncMs": _lastSyncMs,
                    "lastSyncText": lastSyncText,
                    "syncLabel": syncInfo.label,
                    "raw": systemMap,
                  },
                };

                return Scaffold(
                  body: Stack(
                    children: [
                      // Main dashboard scroll area.
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                         // Sensors section header.
                            const Text(
                              "Sensors",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: DashboardScreen.navy,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // First row: Motion + Door.
                            Row(
                              children: [
                                Expanded(
                                  child: _sensorCard(
                                    title: "Motion",
                                    icon: Icons.motion_photos_on,
                                    color: motionInfo.color,
                                    value: motionText,
                                    badge: motionInfo.label,
                                    statLabel: "Last Movement",
                                    statValue: _formatRelative(_lastMotionSeenMs),
                                    note: motionNote,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _sensorCard(
                                    title: "Door",
                                    icon: Icons.door_front_door,
                                    color: doorInfo.color,
                                    value: doorText,
                                    badge: doorInfo.label,
                                    statLabel: "State",
                                    statValue: doorText,
                                    note: doorNote,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Second row: Vibration + Temperature.
                            Row(
                              children: [
                                Expanded(
                                  child: _sensorCard(
                                    title: "Vibration",
                                    icon: Icons.vibration,
                                    color: vibrationInfo.color,
                                    value: vibrationDetected
                                        ? "Vibration Detected"
                                        : "No Vibration",
                                    badge: vibrationInfo.label,
                                    statLabel: "State",
                                    statValue: vibrationDetected ? "Detected" : "Inactive",
                                    note: vibrationNote,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _sensorCard(
                                    title: "Temperature",
                                    icon: Icons.thermostat,
                                    color: tempInfo.color,
                                    value: "${temperature.toStringAsFixed(1)} °C",
                                    badge: tempInfo.label,
                                    statLabel: "Condition",
                                    statValue: tempCondition,
                                    note: tempNote,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Pressure card spans full width.
                            _sensorCard(
                              title: "Pressure",
                              icon: Icons.airline_seat_recline_normal,
                              color: pressureInfo.color,
                              value: pressureText,
                              badge: pressureInfo.label,
                              statLabel: "",
                              statValue: "",
                              note: pressureNote,
                              showStat: false,
                            ),
                            const SizedBox(height: 12),

                            // Summary cards: Overall Status + Last Sync.
                            Row(
                              children: [
                                Expanded(
                                  child: _smallSensorCard(
                                    title: "Overall Status",
                                    icon: Icons.verified_user_outlined,
                                    value: overallStatus,
                                    badgeText: overallBadge,
                                    badgeColor: overallColor,
                                    customBackground: overallBg,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _smallSensorCard(
                                    title: "Last Sync",
                                    icon: Icons.sync,
                                    value: lastSyncText,
                                    badgeText: syncInfo.label,
                                    badgeColor: syncInfo.color,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                          // Sensor insights section header.
                            const Text(
                              "Sensor Insights",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: DashboardScreen.navy,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Insight container holds mini status bars and motion chart.
                            _card(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Status & Activity",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: DashboardScreen.navy,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    "Quick visual summary of the main sensors.",
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Mini progress-based summaries.
                                  _miniStatusCard(
                                    title: "Motion",
                                    stateText: motionInfo.label,
                                    color: motionInfo.color,
                                    level: motionLevel,
                                    icon: Icons.motion_photos_on,
                                  ),
                                  const SizedBox(height: 10),
                                  _miniStatusCard(
                                    title: "Door",
                                    stateText: doorInfo.label,
                                    color: doorInfo.color,
                                    level: doorLevel,
                                    icon: Icons.door_front_door,
                                  ),
                                  const SizedBox(height: 10),
                                  _miniStatusCard(
                                    title: "Vibration",
                                    stateText: vibrationInfo.label,
                                    color: vibrationInfo.color,
                                    level: vibrationLevel,
                                    icon: Icons.vibration,
                                  ),
                                  const SizedBox(height: 10),
                                  _miniStatusCard(
                                    title: "Temperature",
                                    stateText: tempInfo.label,
                                    color: tempInfo.color,
                                    level: temperatureLevel,
                                    icon: Icons.thermostat,
                                  ),
                                  const SizedBox(height: 10),
                                  _miniStatusCard(
                                    title: "Pressure",
                                    stateText: pressureInfo.label,
                                    color: pressureInfo.color,
                                    level: pressureLevel,
                                    icon: Icons.airline_seat_recline_normal,
                                  ),
                                  const SizedBox(height: 18),

                                  // Motion activity chart area.
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFD),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.black.withOpacity(0.05),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                    // Motion activity chart area
                                        const Text(
                                          "Motion Activity Diagram",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: DashboardScreen.navy,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          "Tall bar = more motion   •   Short bar = less motion",
                                          style: TextStyle(
                                            color: Colors.black54,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        SizedBox(
                                          height: 210,
                                          child: _SimpleBarChart(
                                            values: motionChartData,
                                            labels: const [
                                              "Old",
                                              "",
                                              "",
                                              "",
                                              "",
                                              "",
                                              "",
                                              "Now",
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 90),
                          ],
                        ),
                      ),

                      // Floating assistant button in the bottom-right corner.
                      Positioned(
                        right: 16,
                        bottom: 20,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(30),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AssistantPage(
                                    motion: motionDetected,
                                    door: door,
                                    vibration: vibrationDetected,
                                    temperature: temperature,
                                    systemStatus: overallStatus,
                                    motionNote: motionNote,
                                    doorNote: doorNote,
                                    vibrationNote: vibrationNote,
                                    temperatureNote: tempNote,
                                    noMotionMinutes: noMotionMinutes,
                                    pressureDetected: pressureDetected,
                                    pressureNote: pressureNote,
                                    pressureMinutes: pressureMinutes,
                                    alarmOn: alarmOn,
                                    cameraOnline: cameraOnline,
                                    lastSyncText: lastSyncText,
                                    currentPage: "dashboard",
                                    liveContext: liveAssistantContext,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: DashboardScreen.softBlue,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    blurRadius: 14,
                                    offset: const Offset(0, 8),
                                    color: Colors.black.withOpacity(0.18),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.smart_toy_outlined,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }


  // Helper function used to convert, format, or prepare data for display.
  static int _asInt(dynamic value) {
    // Converts int/double/string-like input to int safely.
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  // Helper function used to convert, format, or prepare data for display.
  static int _maxInt(int a, int b) {
  // Simple helper to get the larger of two ints.
    return a > b ? a : b;
  }


  // Helper function used to convert, format, or prepare data for display.
  static int _firstPositiveInt(List<dynamic> values) {
  // Returns the first value that successfully converts to a positive integer.
    for (final value in values) {
      final int parsed = _asInt(value);
      if (parsed > 0) return parsed;
    }
    return 0;
  }


  // Helper function used to convert, format, or prepare data for display.
  static double _asDouble(dynamic value, {double fallback = 0.0}) {
  // Converts value to double safely.
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }


  // Helper function used to convert, format, or prepare data for display.
  static bool _asBool(dynamic value) {
    // Converts several common Firebase representations into bool.
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
  static _StatusInfo _buildSyncInfo(int timestampMs) {
    // Builds a readable sync label and matching color.
    // No Sync: no timestamp yet
    // Realtime: less than 1 minute old
    //  Recent: up to 5 minutes old
    //  Delayed: older than 5 minutes
    if (timestampMs == 0) {
      return const _StatusInfo("No Sync", Colors.red);
    }

    final now = DateTime.now();
    final time = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return const _StatusInfo("Realtime", DashboardScreen.softBlue);
    }
    if (diff.inMinutes <= 5) {
      return const _StatusInfo("Recent", Colors.orange);
    }
    return const _StatusInfo("Delayed", Colors.red);
  }


  // Helper function used to convert, format, or prepare data for display.
  static String _formatRelative(int timestampMs) {
    // Converts timestamp into a user-friendly relative time string.
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


  // Helper function used to convert, format, or prepare data for display.
  static List<double> _buildMotionRealtimeBars({
    required bool motionDetected,
    required int lastMotionMs,
    required DateTime now,
  }) {
    // Builds a simplified bar chart pattern for motion activity.
// This is visual-only logic: active motion shows tall recent bars, no recent motion shows lower bars, older motion shows gradually smaller bars
    if (motionDetected) {
      return [0.25, 0.40, 0.55, 0.70, 0.82, 0.92, 0.86, 0.96];
    }

    if (lastMotionMs == 0) {
      return [0.10, 0.10, 0.08, 0.08, 0.06, 0.06, 0.05, 0.05];
    }

    final minutesAgo =
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastMotionMs)).inMinutes;

    if (minutesAgo < 1) {
      return [0.72, 0.64, 0.56, 0.46, 0.36, 0.28, 0.22, 0.16];
    } else {
      return [0.28, 0.22, 0.18, 0.14, 0.12, 0.10, 0.08, 0.06];
    }
  }
// Internal helper method for the screen logic.
// Basic reusable container card style for grouped content.
// Reusable card container used across multiple settings/profile sections.
  static Widget _card({required Widget child}) {
    // Generic white rounded card with soft shadow.
    // Used to wrap grouped dashboard content.
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            color: Color(0x11000000),
            offset: Offset(0, 6),
          )
        ],
      ),
      child: child,
    );
  }


 // Internal helper method for the screen logic.
  // Small summary card used for quick status information.
  static Widget _smallSensorCard({
    required String title,
    required String value,
    required IconData icon,
    required String badgeText,
    required Color badgeColor,
    Color? customBackground,
  }) {
    // Small dashboard card used for compact summary info like: overall status, last sync
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: customBackground ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            color: Color(0x11000000),
            offset: Offset(0, 6),
          )
        ],
      ),
      child: Row(
        children: [
          // Left icon block.
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: DashboardScreen.lightBlueBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: DashboardScreen.softBlue),
          ),
          const SizedBox(width: 12),

          // M ain title and value text.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: DashboardScreen.navy,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),

          // Right-side colored badge.
          _chip(badgeText, badgeColor),
        ],
      ),
    );
  }


// Internal helper method for the screen logic.
// Reusable sensor card used to display one sensor with details.
  static Widget _sensorCard({
    required String title,
    required IconData icon,
    required Color color,
    required String value,
    required String badge,
    required String statLabel,
    required String statValue,
    required String note,
    bool showStat = true,
  }) {
// Full-size sensor card showing: icon and title, main value, colored state badge, optional stat row, explanatory note
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            color: Color(0x11000000),
            offset: Offset(0, 6),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: icon + sensor name.
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: DashboardScreen.navy,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Main sensor value.
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: DashboardScreen.navy,
            ),
          ),
          const SizedBox(height: 8),

          // Status badge.
          _chip(badge, color),

          // Optional stat line for additional context.
          if (showStat) ...[
            const SizedBox(height: 8),
            Text(
              "$statLabel: $statValue",
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Explanatory note for the user.
          Text(
            note,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }


// Internal helper method for the screen logic.
// Compact mini card used inside the insights section.
  static Widget _miniStatusCard({
    required String title,
    required String stateText,
    required Color color,
    required double level,
    required IconData icon,
  }) {
    // Compact row used in the insights section.
    // Shows a sensor icon, name, animated progress bar, and the current label such as Normal/Warning/Emergency.
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.black.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          // Left icon.
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),

          // Sensor title.
          SizedBox(
            width: 88,
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: DashboardScreen.navy,
              ),
            ),
          ),

          // Animated progress bar representing relative activity/importance.
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: level.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 500),
                builder: (context, animatedValue, child) {
                  return LinearProgressIndicator(
                    value: animatedValue,
                    minHeight: 10,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Right-aligned state text.
          SizedBox(
            width: 78,
            child: Text(
              stateText,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }


// Internal helper method for the screen logic.
  static Widget _chip(String text, Color color) {
    // Reusable rounded badge/chip for status labels.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

// Small helper model that pairs a label with a color.
// Used across the dashboard to keep status presentation consistent.
class _StatusInfo {
  final String label;
  final Color color;

  const _StatusInfo(this.label, this.color);
}


// _SimpleBarChart
// Main widget/class definition for this part of the app.
// Simple custom bar chart used for the motion activity diagram.
class _SimpleBarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;

  const _SimpleBarChart({
    required this.values,
    required this.labels,
  });


  // Main build method that returns the widget tree for the screen.
  @override
  Widget build(BuildContext context) {
    // Find the largest value so the bars can be normalized.
    final maxValue =
        values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: values.map((value) {
              // Normalize each bar height relative to the maximum value.
              final normalized = maxValue == 0 ? 0.0 : value / maxValue;

              // Convert normalized value into actual pixel height.
              final targetHeight = 130 * normalized.clamp(0.05, 1.0);

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: targetHeight),
                      duration: const Duration(milliseconds: 500),
                      builder: (context, animatedHeight, child) {
                        return Container(
                          height: animatedHeight,
                          decoration: BoxDecoration(
                            color: DashboardScreen.softBlue.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),

        // Labels shown under the bars.
        Row(
          children: List.generate(values.length, (index) {
            final text = index < labels.length ? labels[index] : '';
            return Expanded(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ), // TextStyle
              ),
            );
          }), // List.generate
        ),
      ],
    );
  }
}