// Imports
// Packages and project files used by this screen.
import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


// CameraScreen
// Main widget/class definition for this part of the app.

// This screen is responsible for showing the live camera area, checking motion/alarm-related live values,
// and providing quick actions like sounding the alarm
// or calling the emergency contact.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  // Shared theme color used for buttons, icons, and highlights.
  static const softBlue = Color(0xFF4A90E2);
  // Shared navy color used for headings and strong UI accents.
  static const navy = Color(0xFF0D1B2A);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

// _CameraScreenState
// Main widget/class definition for this part of the app.

// State class that holds live values, controllers, and UI logic for the screen.
class _CameraScreenState extends State<CameraScreen> {
   // Firebase database references used to read or update live data.
 
 
  // _rootDb is used when writing general data like events or system updates.
  // _sensorsDb listens to live sensor values.
  // _systemDb listens to system state such as alarm status.
  final DatabaseReference _rootDb = FirebaseDatabase.instance.ref();
  final DatabaseReference _sensorsDb = FirebaseDatabase.instance.ref('sensors');
  final DatabaseReference _systemDb = FirebaseDatabase.instance.ref('system');
    // Current logged-in user.

  // This is used to load personal settings and emergency contact information.
  final User? user = FirebaseAuth.instance.currentUser;

// Holds the latest user settings loaded from Firestore.
 
  // These settings control behavior such as:
  // whether sound alarm is enabled
  // whether emergency calling is allowed
  Map<String, dynamic> _userSettings = {};


  // Helper getter to read whether sounding the alarm is enabled.
  // Defaults to true if the setting does not exist yet.
  bool get _soundAlarmEnabled => _userSettings['soundAlarm'] ?? true;
  
   // Helper getter to read whether emergency calling is enabled.
  // Defaults to true if the setting does not exist yet.
  bool get _callEmergencyEnabled =>
      _userSettings['callEmergencyContact'] ?? true;

// Base URL for the ESP32 camera.
// This IP is the local network address of the camera device.(static)
  static const String cameraBaseUrl = 'http://192.168.8.165';

// URL used to request the latest captured frame from the camera.
// This is refreshed repeatedly to simulate a live feed.
  static const String cameraCaptureUrl = '$cameraBaseUrl/capture';


 // Unique view type used by HtmlElementView.
// Flutter web requires a registered platform view type
// when embedding raw HTML elements.
  late final String _viewType;
  
   // Keeps track of already registered platform view types.
  // This prevents duplicate registrations, which would cause errors.
  static final Set<String> _registeredViewTypes = <String>{};

  // Underlying HTML image element that displays the latest camera frame.
  html.ImageElement? _cameraImage;

   // HTML container that wraps the image element.
  // This is what gets returned to Flutter's HtmlElementView.
  html.DivElement? _cameraContainer;
  
    // Timers used for periodic refresh or live updates.
    // Refreshes the camera frame periodically so the feed keeps updating.
  Timer? _refreshTimer;

// Stores the last timestamp when motion was detected.
// Used to calculate no-motion duration and alert logic.
  int _lastMotionSeenMs = 0;

 // Country code map used when building the emergency phone number.
// The saved emergency phone in Firestore may only contain the local number,
  // so the country code is added before dialing.
  final Map<String, String> countryCodes = {
    "Kuwait": "+965",
    "UAE": "+971",
    "Saudi Arabia": "+966",
    "Oman": "+968",
    "Qatar": "+974",
    "Bahrain": "+973",
  };

  // Runs once when this screen starts and prepares initial state.
  @override
  void initState() {
    super.initState();
   // Build a unique platform view type so each screen instance has its own id.
    _viewType =
        'esp32-camera-capture-view-${DateTime.now().millisecondsSinceEpoch}';
    _registerCameraView();
     // Start periodic frame refresh so the camera stays live.
    _startCameraRefresh();
  }

  // Releases resources here to avoid memory leaks.
  @override
  void dispose() {

      // Timers used for periodic refresh or live updates.
      // Stop refreshing camera frames when leaving the screen.
    _refreshTimer?.cancel();
    super.dispose();
  }

// Returns a stream of the current user's Firestore settings document.
// This allows the camera page to react live if settings change,
// such as disabling calling or sound alarm.
  Stream<DocumentSnapshot<Map<String, dynamic>>> _userSettingsStream() {
    if (user == null) {
      return const Stream.empty();
    }

  // Listen to the logged-in user's document in Firestore.
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .snapshots();
  }

  // Internal helper method for the screen logic.
  void _registerCameraView() {
  // Prevent duplicate registration of the same platform view type.
    if (_registeredViewTypes.contains(_viewType)) return;

 // Create the HTML image element that will display the camera frame.
// objectFit = cover makes the frame fill the container nicely.
    _cameraImage = html.ImageElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.border = 'none'
      ..style.display = 'block'
      ..style.backgroundColor = 'black';

// Create the outer HTML container that wraps the image.
// This container is what Flutter will embed on the page.
    _cameraContainer = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.overflow = 'hidden'
      ..style.backgroundColor = 'black'
      ..style.border = 'none'
      ..children.add(_cameraImage!);

// Register the HTML view factory with Flutter web.
// When Flutter asks for this view type, return the camera container.
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      return _cameraContainer!;
    });
  // Mark this view type as registered so it is not registered again.
    _registeredViewTypes.add(_viewType);
  }

  // Internal helper method for the screen logic.
  void _startCameraRefresh() {
  // Load one frame immediately so the user sees something right away.
    _loadLatestFrame();


  // Timers used for periodic refresh or live updates.
  // Cancel any previous timer before starting a new one.
    _refreshTimer?.cancel();
    // Refresh the camera frame every 700 ms.
    // This does not create true video streaming, but creates a repeated updated image feed.
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      _loadLatestFrame();
    });
  }


  // Internal helper method for the screen logic.
  void _loadLatestFrame() {
  // Add a timestamp query parameter so the browser does not cache the image.
  // Each request becomes unique, forcing a fresh frame to load.
    final ts = DateTime.now().millisecondsSinceEpoch;
    _cameraImage?.src = '$cameraCaptureUrl?t=$ts';
  }


  // Main build method that returns the widget tree for the screen.
  @override
  Widget build(BuildContext context) {
  // First stream: listen to user settings from Firestore.
  // This updates action behavior live when settings change.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userSettingsStream(),
      builder: (context, userSettingsSnapshot) {
            // Save the latest settings map, or empty map if none exists yet.
        _userSettings = userSettingsSnapshot.data?.data() ?? {};

      // Second stream: listen to live sensor updates from Realtime Database.
        return StreamBuilder<DatabaseEvent>(
          stream: _sensorsDb.onValue,
          builder: (context, sensorsSnapshot) {
                // Third stream: listen to live system updates like alarm state.
            return StreamBuilder<DatabaseEvent>(
              stream: _systemDb.onValue,
              builder: (context, systemSnapshot) {
               // Fourth stream: periodic rebuild every second.
                // This is used so elapsed-time logic like "no motion for 1 minute"
                // updates on screen even if no fresh database value arrives.  
                return StreamBuilder<int>(
                  stream: Stream<int>.periodic(
                    const Duration(seconds: 1),
                    (count) => count,
                  ), // Stream.periodic
                  builder: (context, _) {
                    bool motionDetected = false;
                    bool alarmOn = false;
                    // Read sensor data if available.
                    if (sensorsSnapshot.hasData &&
                        sensorsSnapshot.data!.snapshot.value != null) {
                      final raw = sensorsSnapshot.data!.snapshot.value as Map;
                      final sensors = Map<String, dynamic>.from(raw);

                      // Extract motion sensor map safely.
                      final motionMap = sensors['motion'] is Map
                          ? Map<String, dynamic>.from(sensors['motion'])
                          : <String, dynamic>{};
                      // Normalize motion status text.
                      final motionStatus =
                          (motionMap['status'] ?? '').toString().toLowerCase();

                      // Motion is considered active only when status == detected.
                      motionDetected = motionStatus == 'detected';

                      final int nowMs = DateTime.now().millisecondsSinceEpoch;

                      // Try reading the most useful timestamp field for motion.
                      final int motionTimestamp = _asInt(
                        motionMap['lastDetected'] ??
                            motionMap['detectedAt'] ??
                            motionMap['timestamp'],
                      );

                      // If motion is active now, update the "last seen motion" timestamp.
                      if (motionDetected) {
                        _lastMotionSeenMs =
                            motionTimestamp > 0 ? motionTimestamp : nowMs;
                      } else {
                        // If motion is not active, keep the last motion time.
                        // But initialize it once if it was empty and a timestamp exists.
                        if (_lastMotionSeenMs == 0 && motionTimestamp > 0) {
                          _lastMotionSeenMs = motionTimestamp;
                        }
                      }
                    }
                    // Read system data if available.
                    if (systemSnapshot.hasData &&
                        systemSnapshot.data!.snapshot.value != null) {
                      final rawSystem = systemSnapshot.data!.snapshot.value as Map;
                      final system = Map<String, dynamic>.from(rawSystem);
                      // Convert alarm state into a clean bool.
                      alarmOn = _asBool(system['alarmOn']);
                    }

                    final now = DateTime.now();
                    // Calculate how many whole minutes have passed since motion was last seen.
                    final int noMotionMinutes = _lastMotionSeenMs > 0
                        ? now
                            .difference(
                              DateTime.fromMillisecondsSinceEpoch(
                                _lastMotionSeenMs,
                              ),
                            )
                            .inMinutes
                        : 0;
                    // Define no-motion alert rule.
          // Alert becomes true if: motion is not currently detected, there was a previous motion timestamp, at least 1 minute has passed
                    final bool noMotionAlert = !motionDetected &&
                        _lastMotionSeenMs > 0 &&
                        noMotionMinutes >= 1;
                   // Overall alert for this page:
                   // either manual/system alarm is on
                  // or no-motion alert condition is active.
                    final bool isAlert = alarmOn || noMotionAlert;

                    return Scaffold(
                      body: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          // Left side: camera display area.
                            Expanded(
                              flex: 2,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Stack(
                                  children: [
                                  // Full camera view clipped into rounded corners.
                                    Positioned.fill(
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.all(
                                          Radius.circular(16),
                                        ),
                                        child: HtmlElementView(
                                          key: ValueKey(_viewType),
                                          viewType: _viewType,
                                        ),
                                      ),
                                    ),
                            // Top-left live status badge.
                                    Positioned(
                                      top: 12,
                                      left: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isAlert
                                              ? Colors.red
                                              : Colors.green,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          isAlert
                                              ? "LIVE • ALERT"
                                              : "LIVE • SAFE",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                      // Bottom left motion summary text over the camera.
                                    Positioned(
                                      bottom: 12,
                                      left: 12,
                                      child: Text(
                                        motionDetected
                                            ? "Motion detected in frame"
                                            : noMotionAlert
                                                ? "No motion for 1+ minute"
                                                : "No activity detected",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                    // Right side: monitoring summary and action buttons.
                            Expanded(
                              flex: 1,
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 8),                            
                                  // Right side monitoring summary area.
                                    const Text(
                                      "Live Monitoring",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: CameraScreen.navy,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // Motion status summary card.
                                    // Shows detected / no motion / no motion one min.
                                    _statusCard(
                                      title: "Motion",
                                      value: motionDetected
                                          ? "Detected"
                                          : noMotionAlert
                                              ? "No Motion one min"
                                              : "No Motion",
                                      color: isAlert
                                          ? Colors.red
                                          : Colors.green,
                                      icon: Icons.directions_walk,
                                    ),
                                    const SizedBox(height: 12),
                                     // Action buttons row:
                                    // left = alarm action , right = call emergency contact
                                    Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                             // If alarm is already on, stop it.
                                            // Otherwise trigger it.
                                            onTap: alarmOn
                                                ? _stopAlarm
                                                : _triggerAlarm,
                                            child: _actionButton(
                                              alarmOn
                                                  ? "Stop Alarm"
                                                  : "Sound Alarm",
                                              alarmOn
                                                  ? Icons.stop_circle_outlined
                                                  : Icons.notifications_active,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: _callEmergencyContact,
                                            child: _actionButton(
                                              "Call",
                                              Icons.phone,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
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


  // Internal helper method for the screen logic.
  // Reusable status card widget for compact sensor summaries.
  static Widget _statusCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
  // Reusable compact card that displays: an icon, a short title, a stronger status value
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            color: Color(0x11000000),
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
        // Small colored icon box on the left.
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12)),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D1B2A),
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
  // Reusable action button used for alarm and call actions.
  static Widget _actionButton(String text, IconData icon) {
    // Reusable button-like widget used on the camera page.
    // It is wrapped by GestureDetector outside this method so the tap behavior can be assigned separately.
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: CameraScreen.softBlue, size: 18),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: CameraScreen.navy,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper function used to convert, format, or prepare data for display.
  static bool _asBool(dynamic value) {
   
    // Safely converts different data types into a boolean.
    // Useful because Firebase values may come as bool, int, or string.
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
        // Safely converts values like int, double, or text to int.
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }


  // Helper function used to convert, format, or prepare data for display.
  static String _formatClock(DateTime time) {
       // Converts DateTime into a 12-hour clock string such as 3:07 PM.
    final hour =
        time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }


  // Handles an action, backend update, or user request for this screen.
  Future<void> _addEvent({
    required String title,
    required String message,
    required String type,
    required String priority,
  }) async {
        // Create a timestamp for the event.
    final now = DateTime.now();

// Push a new event into the events list in Realtime Database.
// This keeps a record of actions like alarm triggered/stopped.
    await _rootDb.child('events').push().set({
      'title': title,
      'message': message,
      'time': _formatClock(now),
      'type': type,
      'priority': priority,
      'timestamp': now.millisecondsSinceEpoch,
    });
    // Also update the system's lastUpdate timestamp.
    await _rootDb.child('system').update({
      'lastUpdate': now.millisecondsSinceEpoch,
    });
  }


  // Handles an action, backend update, or user request for this screen.
  Future<void> _callEmergencyContact() async {
    // Respect the user's settings:
    // if calling is disabled, do not proceed.
    if (!_callEmergencyEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency calling is disabled in Settings'),
        ),
      );
      return;
    }
    // A signed-in user is required to read emergency contact info.
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logged in user')),
      );
      return;
    }

    try {
            // Load user profile from Firestore.
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      final data = doc.data() ?? {};

      // Read emergency contact country and local phone number.
      final emergencyCountry =
          (data['emergencyContactCountry'] ?? 'Kuwait').toString();
      final emergencyPhone =
          (data['emergencyContactPhone'] ?? '').toString().trim();

      // Resolve country dial code from the lookup map.
      final emergencyCode = countryCodes[emergencyCountry] ?? '+965';

      // If no phone is saved, show a message and stop.
      if (emergencyPhone.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No emergency contact number saved in Settings'),
          ),
        );
        return;
      }

      final fullNumber = '$emergencyCode$emergencyPhone';
      final Uri phoneUri = Uri(scheme: 'tel', path: fullNumber);

      // Open the phone dial action if supported on the device/platform.
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open phone call')),
        );
      }
    } catch (e) {
            // Show any unexpected Firestore or launch error.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reading emergency contact: $e')),
      );
    }
  }


  // Handles an action, backend update, or user request for this screen.
  Future<void> _triggerAlarm() async {
        // Capture the current time so all related writes share the same moment.
    final now = DateTime.now();

    try {
            // Update the system node so the app knows alarm is active.
      await _rootDb.child('system').update({
        'alarmOn': true,
        'dashboardStatus': 'alert',
        'latestAlert': _soundAlarmEnabled
            ? 'Alarm is currently active'
            : 'Alarm triggered (sound disabled in settings)',
        'lastUpdate': now.millisecondsSinceEpoch,
      });
      // Add a separate event entry for history/logging.
      await _addEvent(
        title: 'Alarm Triggered',
        message: _soundAlarmEnabled
            ? 'Alarm was triggered manually'
            : 'Alarm triggered manually with sound disabled in settings',
        type: 'alarm',
        priority: 'high',
      );

      // Let the user know the action succeeded.
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
            // Show error if database update fails.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error triggering alarm: $e')),
      );
    }
  }


  // Handles an action, backend update, or user request for this screen.
  Future<void> _stopAlarm() async {
        // Timestamp used for consistent update/event logging.
    final now = DateTime.now();

    try {
            // Reset the system alarm state back to safe.
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

      // Show confirmation to the user.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarm stopped')),
      );
    } catch (e) {
            // Show error if alarm stop fails.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error stopping alarm: $e')),
      );
    }
  }
}