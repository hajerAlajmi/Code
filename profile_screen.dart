import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';

import 'login_screen.dart';

// Profile screen for showing and editing: caregiver information, monitored person information, system/device status
// This page reads user profile data from Firestore and live sensor/device data from Realtime Database.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Shared theme colors used throughout this screen.
  static const softBlue = Color(0xFF4A90E2);
  static const navy = Color(0xFF0D1B2A);
  static const darkLabel = Color(0xFF555555);
  static const placeholderGray = Color(0xFF8A8A8A);

  // Currently logged-in Firebase user.
  // This is required to read and update the correct Firestore user document.
  final User? user = FirebaseAuth.instance.currentUser;

  // Controls whether the loading overlay is visible.
  bool isLoading = false;

  // Realtime Database reference for live sensor status.
  final DatabaseReference sensorsRef = FirebaseDatabase.instance.ref('sensors');

  // Stores the last detected sync timestamp shown in the System section.
  int _lastSyncMs = 0;

  // Stores a compact snapshot fingerprint to detect changes in sensor state.
  String _lastSnapshotKey = '';

  final Map<String, List<String>> countryRegions = {
    "Kuwait": [
      "Asimah",
      "Hawalli",
      "Farwaniya",
      "Ahmadi",
      "Jahra",
      "Mubarak Al-Kabeer",
    ],
    "UAE": [
      "Dubai",
      "Abu Dhabi",
      "Sharjah",
      "Ajman",
      "Al Ain",
      "Ras Al Khaimah",
    ],
    "Saudi Arabia": [
      "Riyadh",
      "Jeddah",
      "Makkah",
      "Madinah",
      "Dammam",
      "Khobar",
    ],
    "Oman": [
      "Muscat",
      "Salalah",
      "Sohar",
      "Nizwa",
      "Sur",
      "Barka",
    ],
    "Qatar": [
      "Doha",
      "Al Rayyan",
      "Al Wakrah",
      "Lusail",
      "Umm Salal",
      "Al Khor",
    ],
    "Bahrain": [
      "Manama",
      "Muharraq",
      "Riffa",
      "Isa Town",
      "Sitra",
      "Hamad Town",
    ],
  };

  final Map<String, String> countryCodes = {
    "Kuwait": "+965",
    "UAE": "+971",
    "Saudi Arabia": "+966",
    "Oman": "+968",
    "Qatar": "+974",
    "Bahrain": "+973",
  };

  @override
  Widget build(BuildContext context) {
    // If there is no signed-in user, this page cannot load profile data.
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("No logged in user")),
      );
    }

    // Listen to the current user's Firestore document in real time,so profile changes immediately appear without manual refresh.
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .snapshots(),
      builder: (context, snapshot) {
        // Show loader while waiting for the first Firestore result.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Extract Firestore data safely as a map.
        final data = snapshot.data?.data() as Map<String, dynamic>?;

        // Build caregiver display fields.
        final caregiverFirstName =
            (data?['firstName'] ?? data?['name'] ?? "").toString().trim();
        final caregiverLastName =
            (data?['lastName'] ?? "").toString().trim();
        final caregiverFullName =
            "$caregiverFirstName $caregiverLastName".trim();

        // Build monitored person display fields.
        final patientFirstName =
            (data?['patientFirstName'] ?? "").toString().trim();
        final patientLastName =
            (data?['patientLastName'] ?? "").toString().trim();
        final patientFullName =
            "$patientFirstName $patientLastName".trim();

        final patientDob = (data?['patientDob'] ?? "").toString().trim();
        final patientGender =
            (data?['patientGender'] ?? "").toString().trim();

        // Read saved patient country and region.
        final rawPatientCountry =
            (data?['patientCountry'] ?? "").toString().trim();
        final rawPatientRegion =
            (data?['patientRegion'] ?? "").toString().trim();

        // Validate country against the allowed dropdown options.
        // If the saved value is invalid/missing, default to Kuwait.
        final patientCountry = countryRegions.containsKey(rawPatientCountry)
            ? rawPatientCountry
            : "Kuwait";

        // Validate region against the selected country's allowed regions.
        final regionList = countryRegions[patientCountry]!;
        final patientRegion = regionList.contains(rawPatientRegion)
            ? rawPatientRegion
            : regionList.first;

        // Build a readable location string from region and country.
        final patientLocation =
            rawPatientCountry.isEmpty && rawPatientRegion.isEmpty
                ? ""
                : rawPatientRegion.isEmpty
                    ? rawPatientCountry
                    : rawPatientCountry.isEmpty
                        ? rawPatientRegion
                        : "$rawPatientRegion, $rawPatientCountry";

        final patientFullAddress =
            (data?['patientFullAddress'] ?? "").toString().trim();

        final patientNotes =
            (data?['patientNotes'] ?? "").toString().trim();

        // Emergency contact information.
        final emergencyName =
            (data?['emergencyContactName'] ?? "").toString().trim();
        final emergencyPhone =
            (data?['emergencyContactPhone'] ?? "").toString().trim();
        final emergencyCode = countryCodes[patientCountry] ?? "+965";
        final emergencyContact = emergencyName.isEmpty && emergencyPhone.isEmpty
            ? ""
            : "$emergencyName • $emergencyCode $emergencyPhone";

        // Display placeholders when fields are empty.
        final caregiverDisplay =
            caregiverFullName.isEmpty ? "Not set" : caregiverFullName;
        final patientDisplay =
            patientFullName.isEmpty ? "Not set" : patientFullName;

        final firstNameDisplay =
            patientFirstName.isEmpty ? "Not set" : patientFirstName;
        final lastNameDisplay =
            patientLastName.isEmpty ? "Not set" : patientLastName;
        final genderDisplay =
            patientGender.isEmpty ? "Not set" : patientGender;
        final birthdateDisplay =
            patientDob.isEmpty ? "Not set" : patientDob;
        final locationDisplay =
            patientLocation.isEmpty ? "Not set" : patientLocation;
        final addressDisplay =
            patientFullAddress.isEmpty ? "Not set" : patientFullAddress;
        final notesDisplay =
            patientNotes.isEmpty ? "No notes added" : patientNotes;
        final emergencyDisplay =
            emergencyContact.isEmpty ? "Not set" : emergencyContact;

        return Scaffold(
          body: Stack(
            children: [
              // Main scrollable profile content.
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// Caregiver section header.
                    _sectionTitle("Caregiver"),
                    const SizedBox(height: 10),

                    // Caregiver info card with edit action.
                    _card(
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF3FF),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.person,
                              color: softBlue,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Caregiver Name",
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  caregiverDisplay,
                                  style: TextStyle(
                                    color: caregiverDisplay == "Not set"
                                        ? placeholderGray
                                        : navy,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Opens dialog to edit caregiver first/last name.
                          IconButton(
                            onPressed: () {
                              _editCaregiverInfo(
                                currentFirstName: caregiverFirstName,
                                currentLastName: caregiverLastName,
                              );
                            },
                            icon: const Icon(Icons.edit, color: navy),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // This empty title call keeps your exact original layout as-is.
                    _sectionTitle(""),
                    const SizedBox(height: 10),

                    // Monitored person / patient card with editable fields.
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF3FF),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.favorite_outline,
                                  color: softBlue,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  patientDisplay,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: patientDisplay == "Not set"
                                        ? placeholderGray
                                        : navy,
                                  ),
                                ),
                              ),

                              // Opens the patient edit dialog with all current values prefilled.
                              TextButton(
                                onPressed: () {
                                  _editPatientInfo(
                                    currentFirstName: patientFirstName,
                                    currentLastName: patientLastName,
                                    currentDob: patientDob,
                                    currentGender: patientGender,
                                    currentCountry: patientCountry,
                                    currentRegion: patientRegion,
                                    currentFullAddress: patientFullAddress,
                                    currentNotes: patientNotes,
                                    currentEmergencyName: emergencyName,
                                    currentEmergencyPhone: emergencyPhone,
                                  );
                                },
                                child: const Text("Edit"),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Individual information rows.
                          _infoRow("First Name", firstNameDisplay),
                          const SizedBox(height: 10),
                          _infoRow("Last Name", lastNameDisplay),
                          const SizedBox(height: 10),
                          _infoRow("Gender", genderDisplay),
                          const SizedBox(height: 10),
                          _infoRow("Birthdate", birthdateDisplay),
                          const SizedBox(height: 10),
                          _infoRow("Location", locationDisplay),
                          const SizedBox(height: 10),
                          _infoRow("Full Address", addressDisplay),
                          const SizedBox(height: 10),
                          _infoRow("Medical Notes", notesDisplay),
                          const SizedBox(height: 10),
                          _infoRow("Emergency Contact", emergencyDisplay),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // System section header.
                    _sectionTitle("System"),
                    const SizedBox(height: 6),
                    const Text(
                      "This section shows the device and sensor status.",
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Live sensor/device status from Realtime Database.
                    StreamBuilder<DatabaseEvent>(
                      stream: sensorsRef.onValue,
                      builder: (context, sensorSnapshot) {
                        int sensorsOnline = 0;
                        int sensorsTotal = 0;

                        if (sensorSnapshot.hasData &&
                            sensorSnapshot.data!.snapshot.value != null) {
                          final raw = sensorSnapshot.data!.snapshot.value as Map;
                          final sensors = Map<String, dynamic>.from(raw);

                          // Safely extract relevant sensor maps.
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

                          // Count total and online sensors.
                          sensors.forEach((key, value) {
                            if (value is Map) {
                              final sensorData = Map<dynamic, dynamic>.from(value);
                              sensorsTotal++;
                              if (sensorData['online'] == true) {
                                sensorsOnline++;
                              }
                            }
                          });

                          // Extract normalized sensor states used only to decide whether the snapshot changed.
                          final motionStatus =
                              (motionMap['status'] ?? '').toString().toLowerCase();

                          final rawDoorStatus = (doorMap['status'] ?? 'closed')
                              .toString()
                              .toLowerCase();

                          final vibrationStatus =
                              (vibrationMap['status'] ?? '').toString().toLowerCase();

                          final temperature = _asDouble(
                            temperatureMap['celsius'] ??
                                temperatureMap['value'] ??
                                temperatureMap['bodyTemp'],
                            fallback: 36.8,
                          );

                          final p1Status = (pressure1Map['status'] ?? '')
                              .toString()
                              .toLowerCase();
                          final p2Status = (pressure2Map['status'] ?? '')
                              .toString()
                              .toLowerCase();

                          final int nowMs = DateTime.now().millisecondsSinceEpoch;

                          final int motionTimestamp = _asInt(
                            motionMap['lastDetected'] ??
                                motionMap['detectedAt'] ??
                                motionMap['timestamp'],
                          );

                          // Compact fingerprint of current sensor state. If it changes, update the sync timestamp.
                          final String snapshotKey = [
                            motionStatus,
                            rawDoorStatus,
                            vibrationStatus,
                            temperature.toStringAsFixed(1),
                            p1Status,
                            p2Status,
                            motionTimestamp.toString(),
                          ].join('|');

                          if (_lastSnapshotKey.isEmpty) {
                            _lastSnapshotKey = snapshotKey;
                            _lastSyncMs = nowMs;
                          } else if (_lastSnapshotKey != snapshotKey) {
                            _lastSnapshotKey = snapshotKey;
                            _lastSyncMs = nowMs;
                          }

                          // Best available latest sensor timestamp.
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

                        // Rebuild every second so "Last Sync" relative time updates live.
                        return StreamBuilder<int>(
                          stream: Stream<int>.periodic(
                            const Duration(seconds: 1),
                            (count) => count,
                          ),
                          builder: (context, _) {
                            return Row(
                              children: [
                                Expanded(
                                  child: _statusCard(
                                    title: "Sensors",
                                    value: "$sensorsOnline / $sensorsTotal Online",
                                    icon: Icons.sensors,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _statusCard(
                                    title: "Last Sync",
                                    value: _formatRelative(_lastSyncMs),
                                    icon: Icons.sync,
                                    color: softBlue,
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 10),
                  ],
                ),
              ),

              // Loading overlay shown during profile updates or logout.
              if (isLoading)
                Container(
                  color: Colors.black.withOpacity(0.15),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        );
      },
    );
  }

  // Writes updated user data into Firestore.
  // Uses merge:true so it updates only provided fields without removing the rest of the document.
  Future<void> _updateUserData(Map<String, dynamic> newData) async {
    if (user == null) return;

    setState(() => isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
        'email': user!.email,
        ...newData,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Updated successfully")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  // Opens a dialog for editing caregiver first and last name.
  Future<void> _editCaregiverInfo({
    required String currentFirstName,
    required String currentLastName,
  }) async {
    final firstNameController = TextEditingController(text: currentFirstName);
    final lastNameController = TextEditingController(text: currentLastName);

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Edit Caregiver Info"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstNameController,
                decoration: const InputDecoration(labelText: "First Name"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: lastNameController,
                decoration: const InputDecoration(labelText: "Last Name"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _updateUserData({
                  'firstName': firstNameController.text.trim(),
                  'lastName': lastNameController.text.trim(),
                });
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  // Opens the main dialog for editing monitored person information.
  Future<void> _editPatientInfo({
    required String currentFirstName,
    required String currentLastName,
    required String currentDob,
    required String currentGender,
    required String currentCountry,
    required String currentRegion,
    required String currentFullAddress,
    required String currentNotes,
    required String currentEmergencyName,
    required String currentEmergencyPhone,
  }) async {
    final firstNameController = TextEditingController(text: currentFirstName);
    final lastNameController = TextEditingController(text: currentLastName);
    final fullAddressController =
        TextEditingController(text: currentFullAddress);
    final notesController = TextEditingController(text: currentNotes);
    final emergencyNameController =
        TextEditingController(text: currentEmergencyName);
    final emergencyPhoneController =
        TextEditingController(text: currentEmergencyPhone);
    final formKey = GlobalKey<FormState>();

    final List<String> genderOptions = ["Male", "Female"];

    DateTime selectedDob = _parseDob(currentDob);

    // Ensure saved gender is one of the allowed options.
    String selectedGender = genderOptions.contains(currentGender)
        ? currentGender
        : genderOptions.first;

    // Ensure saved country is valid.
    String selectedCountry = countryRegions.containsKey(currentCountry)
        ? currentCountry
        : "Kuwait";

    // Ensure saved region belongs to the selected country.
    String selectedRegion = countryRegions[selectedCountry]!.contains(currentRegion)
        ? currentRegion
        : countryRegions[selectedCountry]!.first;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentRegions = countryRegions[selectedCountry]!;
            final emergencyCode = countryCodes[selectedCountry] ?? "+965";
            final isKuwait = selectedCountry == "Kuwait";

            // If the selected region becomes invalid after changing country, fall back to the first region of that country.
            if (!currentRegions.contains(selectedRegion)) {
              selectedRegion = currentRegions.first;
            }

            return AlertDialog(
              title: const Text("Edit Monitored Person"),
              content: SizedBox(
                width: 420,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: firstNameController,
                          decoration: const InputDecoration(
                            labelText: "First Name",
                          ),
                        ),
                        const SizedBox(height: 10),

                        TextField(
                          controller: lastNameController,
                          decoration: const InputDecoration(
                            labelText: "Last Name",
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Custom birthdate picker field.
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDob,
                              firstDate: DateTime(1900),
                              lastDate: DateTime.now(),
                            );

                            if (picked != null) {
                              setDialogState(() {
                                selectedDob = picked;
                              });
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: "Birthdate",
                              border: OutlineInputBorder(),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDob(selectedDob)),
                                const Icon(Icons.calendar_today, size: 18),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Gender dropdown.
                        DropdownButtonFormField<String>(
                          value: selectedGender,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: "Gender",
                          ),
                          items: genderOptions.map((gender) {
                            return DropdownMenuItem<String>(
                              value: gender,
                              child: Text(gender),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                selectedGender = value;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 10),

                        // Country dropdown.
                        DropdownButtonFormField<String>(
                          value: selectedCountry,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: "Country",
                          ),
                          items: countryRegions.keys.map((country) {
                            return DropdownMenuItem<String>(
                              value: country,
                              child: Text(country),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                selectedCountry = value;
                                selectedRegion = countryRegions[value]!.first;

                                // Kuwait phone numbers are limited to 8 digits, so trim the existing number if needed.
                                if (value == "Kuwait" &&
                                    emergencyPhoneController.text.length > 8) {
                                  emergencyPhoneController.text =
                                      emergencyPhoneController.text.substring(0, 8);
                                }
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 10),

                        // Region/city dropdown, dependent on selected country.
                        DropdownButtonFormField<String>(
                          value: selectedRegion,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: "Region / City",
                          ),
                          items: currentRegions.map((region) {
                            return DropdownMenuItem<String>(
                              value: region,
                              child: Text(region),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                selectedRegion = value;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 10),

                        TextField(
                          controller: fullAddressController,
                          decoration: const InputDecoration(
                            labelText: "Full Address",
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 10),

                        TextField(
                          controller: notesController,
                          decoration: const InputDecoration(
                            labelText: "Medical Notes",
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 10),

                        TextField(
                          controller: emergencyNameController,
                          decoration: const InputDecoration(
                            labelText: "Emergency Contact Name",
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Emergency contact phone field with validation.
                        TextFormField(
                          controller: emergencyPhoneController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(isKuwait ? 8 : 15),
                          ],
                          decoration: InputDecoration(
                            labelText: "Emergency Contact Phone",
                            prefixText: "$emergencyCode ",
                            counterText: "",
                          ),
                          maxLength: isKuwait ? 8 : 15,
                          validator: (v) {
                            final s = (v ?? "").trim();

                            if (s.isEmpty) return "Required";

                            if (isKuwait) {
                              if (!RegExp(r'^[965]').hasMatch(s)) {
                                return "Must start with 9, 6, or 5";
                              }
                              if (s.length != 8) {
                                return "Kuwait number must be 8 digits";
                              }
                            }

                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;

                    Navigator.pop(context);

                    await _updateUserData({
                      'patientFirstName': firstNameController.text.trim(),
                      'patientLastName': lastNameController.text.trim(),
                      'patientDob': _formatDob(selectedDob),
                      'patientGender': selectedGender,
                      'patientCountry': selectedCountry,
                      'patientRegion': selectedRegion,
                      'patientFullAddress': fullAddressController.text.trim(),
                      'patientNotes': notesController.text.trim(),
                      'emergencyContactCountry': selectedCountry,
                      'emergencyContactName': emergencyNameController.text.trim(),
                      'emergencyContactPhone': emergencyPhoneController.text.trim(),
                    });
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Parses a dd/mm/yyyy string into a DateTime. Falls back to 01/01/1974 if parsing fails.
  DateTime _parseDob(String dob) {
    try {
      final parts = dob.split('/');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return DateTime(1974, 1, 1);
  }

  // Formats a DateTime into dd/mm/yyyy.
  String _formatDob(DateTime dob) {
    final day = dob.day.toString().padLeft(2, '0');
    final month = dob.month.toString().padLeft(2, '0');
    final year = dob.year.toString();
    return "$day/$month/$year";
  }

  // Formats only the hour and minute as HH:MM.
  String _formatTimeOnly(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  // Converts a timestamp into a relative label
  String _formatRelative(int timestampMs) {
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

  // Safely converts a dynamic value into int.
  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  // Returns the first positive integer found in the provided list.
  static int _firstPositiveInt(List<dynamic> values) {
    for (final value in values) {
      final int parsed = _asInt(value);
      if (parsed > 0) return parsed;
    }
    return 0;
  }

  // Safely converts a dynamic value into double.
  static double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  // Signs the user out and returns them to the login screen.
  Future<void> _logout() async {
    setState(() => isLoading = true);

    try {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Logout failed: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  // Reusable section title widget.
  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: navy,
      ),
    );
  }

  // Reusable white card container with rounded corners and shadow.
  Widget _card({required Widget child}) {
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

  // Reusable row for displaying a label and value in the patient info card.
  Widget _infoRow(String label, String value) {
    final bool isPlaceholder = value == "Not set" || value == "No notes added";

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              color: darkLabel,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: isPlaceholder ? placeholderGray : navy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // Reusable system status card used for: sensors online count, last sync time
  Widget _statusCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
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
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
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
                    color: navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}