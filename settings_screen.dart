// Imports
// Packages and project files used by this screen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_screen.dart';


// SettingsScreen
// Main widget/class definition for this part of the app.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}


// _SettingsScreenState
// Main widget/class definition for this part of the app.

// State class that holds live values, controllers, and UI logic for the screen.
class _SettingsScreenState extends State<SettingsScreen> {
  // Shared theme colors used throughout this screen.
  static const softBlue = Color(0xFF4A90E2);
  static const navy = Color(0xFF0D1B2A);
  static const bg = Color(0xFFF7F9FC);

  // Current logged-in user.
  // This is required for reading and updating the correct Firestore document.
  final User? user = FirebaseAuth.instance.currentUser;

  // Controls loading overlay while an async settings action is running.
  bool isLoading = false;

  // Country calling codes used for account phone and emergency contact phone.
  final Map<String, String> countryCodes = {
    "Kuwait": "+965",
    "UAE": "+971",
    "Saudi Arabia": "+966",
    "Oman": "+968",
    "Qatar": "+974",
    "Bahrain": "+973",
  };

  // Maximum allowed phone digits by country.
  // Used for validation and input length control.
  final Map<String, int> countryPhoneMaxDigits = {
    "Kuwait": 8,
    "UAE": 9,
    "Saudi Arabia": 9,
    "Oman": 8,
    "Qatar": 8,
    "Bahrain": 8,
  };

  // Main build method that returns the widget tree for the screen.
  @override
  Widget build(BuildContext context) {
    // If there is no logged-in user, settings cannot be loaded.
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("No logged in user")),
      );
    }

    // Listen to the current user's Firestore document in real time.
    // This keeps the settings screen synced with latest saved values.
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .snapshots(),
      builder: (context, snapshot) {
        // Show loading until the first Firestore snapshot is available.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: bg,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Extract Firestore data safely as a map.
        final data = snapshot.data?.data() as Map<String, dynamic>?;

        // Account section values.
        final username = (data?['username'] ?? "username").toString().trim();

        final email = (data?['email'] ?? user!.email ?? "").toString().trim();

        // Resolve current account country and phone code.
        // If saved country is invalid, default to Kuwait.
        final accountCountry = countryCodes.containsKey(data?['countryName'])
            ? data!['countryName'].toString()
            : "Kuwait";

        final accountCountryCode =
            (data?['countryCode'] ?? countryCodes[accountCountry] ?? "+965")
                .toString();

        // Stored phone may include full country code, so local number is extracted for editing.
        final storedPhone =
            (data?['phone'] ?? user!.phoneNumber ?? "").toString().trim();
        final localPhone = _extractLocalPhone(
          fullPhone: storedPhone,
          countryCode: accountCountryCode,
        );

        final phoneDisplay = localPhone.isEmpty
            ? accountCountryCode
            : "$accountCountryCode $localPhone";

        // Emergency contact values.
        final emergencyCountry =
            countryCodes.containsKey(data?['emergencyContactCountry'])
                ? data!['emergencyContactCountry'].toString()
                : "Kuwait";
        final emergencyName =
            (data?['emergencyContactName'] ?? "").toString();
        final emergencyPhone =
            (data?['emergencyContactPhone'] ?? "").toString();
        final emergencyCode = countryCodes[emergencyCountry] ?? "+965";
        final emergencyDisplay =
            "$emergencyCountry ($emergencyCode) • $emergencyPhone";

        // Alarm and notification preferences.
        final soundAlarm = data?['soundAlarm'] ?? true;
        final callEmergencyContact = data?['callEmergencyContact'] ?? true;

        final emailAlerts = data?['emailAlerts'] ?? true;
        final mobileAlerts = data?['mobileAlerts'] ?? true;
        final emergencyAlerts = data?['emergencyAlerts'] ?? true;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: navy,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              "Settings",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            centerTitle: false,
          ),
          body: Stack(
            children: [
              // Main settings content.
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Account section
                    _sectionTitle("Account"),
                    const SizedBox(height: 10),
                    _card(
                      child: Column(
                        children: [
                          _tile(
                            icon: Icons.alternate_email,
                            title: "Username",
                            subtitle: username,
                            onTap: () {
                              _editUsername(currentUsername: username);
                            },
                          ),
                          const Divider(height: 1),
                          _tile(
                            icon: Icons.email_outlined,
                            title: "Email",
                            subtitle: email.isEmpty ? "No email" : email,
                            onTap: () {
                              _changeEmail(currentEmail: email);
                            },
                          ),
                          const Divider(height: 1),
                          _tile(
                            icon: Icons.phone_outlined,
                            title: "Phone Number",
                            subtitle: phoneDisplay,
                            onTap: () {
                              _editPhoneNumber(
                                currentCountry: accountCountry,
                                currentPhone: localPhone,
                              );
                            },
                          ),
                          const Divider(height: 1),
                          _tile(
                            icon: Icons.lock_outline,
                            title: "Change Password",
                            subtitle: "Update your account password",
                            onTap: _changePassword,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Emergency contact section
                    _sectionTitle("Emergency Contact"),
                    const SizedBox(height: 10),
                    _card(
                      child: Column(
                        children: [
                          _tile(
                            icon: Icons.person_outline,
                            title: "Contact Name",
                            subtitle: emergencyName,
                            onTap: () {
                              _editEmergencyContact(
                                currentCountry: emergencyCountry,
                                currentName: emergencyName,
                                currentPhone: emergencyPhone,
                              );
                            },
                          ),
                          const Divider(height: 1),
                          _tile(
                            icon: Icons.call_outlined,
                            title: "Phone Number",
                            subtitle: emergencyDisplay,
                            onTap: () {
                              _editEmergencyContact(
                                currentCountry: emergencyCountry,
                                currentName: emergencyName,
                                currentPhone: emergencyPhone,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Alarm section
                    _sectionTitle("Alarm"),
                    const SizedBox(height: 10),
                    _card(
                      child: Column(
                        children: [
                          _switchTile(
                            icon: Icons.volume_up_outlined,
                            title: "Sound Alarm",
                            subtitle: "Play alarm sound during emergency",
                            value: soundAlarm,
                            onChanged: (value) async {
                              await _updateUserData({'soundAlarm': value});
                            },
                          ),
                          const Divider(height: 1),
                          _switchTile(
                            icon: Icons.phone_in_talk_outlined,
                            title: "Call Emergency Contact",
                            subtitle:
                                "Use saved contact for prototype emergency action",
                            value: callEmergencyContact,
                            onChanged: (value) async {
                              await _updateUserData(
                                {'callEmergencyContact': value},
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Notifications section
                    _sectionTitle("Notifications"),
                    const SizedBox(height: 10),
                    _card(
                      child: Column(
                        children: [
                          _switchTile(
                            icon: Icons.email_outlined,
                            title: "Email Alerts",
                            subtitle: "Receive alerts by email",
                            value: emailAlerts,
                            onChanged: (value) async {
                              await _updateUserData({'emailAlerts': value});
                            },
                          ),
                          const Divider(height: 1),
                          _switchTile(
                            icon: Icons.sms_outlined,
                            title: "Mobile Alerts",
                            subtitle: "Receive alerts by phone",
                            value: mobileAlerts,
                            onChanged: (value) async {
                              await _updateUserData({'mobileAlerts': value});
                            },
                          ),
                          const Divider(height: 1),
                          _switchTile(
                            icon: Icons.warning_amber_outlined,
                            title: "Emergency Alerts",
                            subtitle: "Prioritize urgent notifications",
                            value: emergencyAlerts,
                            onChanged: (value) async {
                              await _updateUserData({'emergencyAlerts': value});
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // About section
                    _sectionTitle("About"),
                    const SizedBox(height: 10),
                    _card(
                      child: _tile(
                        icon: Icons.info_outline,
                        title: "About Safe Home Monitor",
                        subtitle: "Guidelines, features, and how the app works",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AboutSystemScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Security section
                    _sectionTitle("Security"),
                    const SizedBox(height: 10),
                    _card(
                      child: Column(
                        children: [
                          _tile(
                            icon: Icons.logout,
                            title: "Log Out",
                            subtitle: "Sign out from your account",
                            onTap: _logout,
                          ),
                          const Divider(height: 1),
                          _tile(
                            icon: Icons.delete_outline,
                            title: "Delete Account",
                            subtitle: "Permanently remove this account",
                            onTap: _deleteAccount,
                            iconColor: Colors.red,
                            titleColor: Colors.red,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Global loading overlay shown during async actions.
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

  // Handles an action, backend update, or user request for this screen.
  Future<void> _updateUserData(Map<String, dynamic> newData) async {
    // Cannot update if there is no user.
    if (user == null) return;

    setState(() => isLoading = true);

    try {
      // Merge only the changed fields into the user's Firestore document.
      // The current email is preserved unless a new email is explicitly supplied.
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
        ...newData,
        'email': newData['email'] ?? user!.email,
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


  // Internal helper method for the screen logic.
  String _extractLocalPhone({
    required String fullPhone,
    required String countryCode,
  }) {
    // Remove spaces and trim.
    String cleaned = fullPhone.replaceAll(' ', '').trim();

    // If the stored phone already begins with the country code,
    // strip the prefix so only the local number remains.
    if (cleaned.startsWith(countryCode)) {
      cleaned = cleaned.substring(countryCode.length);
    }

    return cleaned;
  }

  // Internal helper method for the screen logic.
  bool _isValidEmail(String email) {
    // Basic email format validation used before sending email change requests.
    final emailRegex = RegExp(
      r'^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }


  // Internal helper method for the screen logic.
  bool _isValidUsername(String username) {
    // Username rules: 3 to 20 characters, letters, numbers, dot, underscore only
    final usernameRegex = RegExp(r'^[a-zA-Z0-9._]{3,20}$');
    return usernameRegex.hasMatch(username);
  }


  // Internal helper method for the screen logic.
  Future<bool> _isUsernameTaken(String username) async {
    // Check if the normalized username already exists in Firestore for another user account.
    final normalized = username.trim().toLowerCase();

    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('usernameLower', isEqualTo: normalized)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return false;
    return query.docs.first.id != user!.uid;
  }

  // Internal helper method for the screen logic.
  Future<bool> _isEmailTaken(String email) async {
    // Check if the normalized email already exists in Firestore for another user account.
    final normalized = email.trim().toLowerCase();

    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('emailLower', isEqualTo: normalized)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return false;
    return query.docs.first.id != user!.uid;
  }

  // Opens a dialog or handles a user action related to editing/changing data.
  Future<void> _editUsername({required String currentUsername}) async {
  
    // Text controllers used by form fields and input boxes.
    final controller = TextEditingController(text: currentUsername);

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
        // Dialog for editing the username.
          title: const Text("Edit Username"),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: "Username",
                hintText: "letters, numbers, . and _ only",
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
                final newUsername = controller.text.trim();

                // Validation: non-empty
                if (newUsername.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please enter a username")),
                  );
                  return;
                }

                // Validation: allowed format
                if (!_isValidUsername(newUsername)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Username must be 3-20 characters and use only letters, numbers, . or _",
                      ),
                    ),
                  );
                  return;
                }

                // Validation: uniqueness
                final taken = await _isUsernameTaken(newUsername);
                if (taken) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Username already exists")),
                  );
                  return;
                }

                if (!mounted) return;
                Navigator.pop(context);

                // Save both display username and lowercase normalized version.
                await _updateUserData({
                  'username': newUsername,
                  'usernameLower': newUsername.toLowerCase(),
                });
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }


  // Opens a dialog or handles a user action related to editing/changing data.
  Future<void> _changeEmail({required String currentEmail}) async {
    
    // Text controllers used by form fields and input boxes.
    final emailController = TextEditingController(text: currentEmail);

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
        // Dialog for changing the email address.
          title: const Text("Change Email"),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "New Email",
                  ),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "A verification code will be sent to the new email.",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final newEmail = emailController.text.trim().toLowerCase();

                // Validation: non-empty
                if (newEmail.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please enter an email")),
                  );
                  return;
                }

                // Validation: email format
                if (!_isValidEmail(newEmail)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please enter a valid email")),
                  );
                  return;
                }

                // Validation: uniqueness
                final taken = await _isEmailTaken(newEmail);
                if (taken) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Email already exists")),
                  );
                  return;
                }

                try {
                  setState(() => isLoading = true);

                  // Send verification code to the new email.
                  final callable =
                      FirebaseFunctions.instance.httpsCallable('sendResetCode');

                  await callable.call({
                    'email': newEmail,
                  });

                  if (!mounted) return;
                  Navigator.pop(context);

                  // After sending code, open the verification dialog.
                  await _verifyEmailChangeCode(newEmail: newEmail);
                } on FirebaseFunctionsException catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.message ?? "Failed to send code")),
                  );
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Failed to send code")),
                  );
                } finally {
                  if (mounted) setState(() => isLoading = false);
                }
              },
              child: const Text("Send Code"),
            ),
          ],
        );
      },
    );
  }

  // Opens a dialog or handles a user action related to editing/changing data.
  Future<void> _verifyEmailChangeCode({required String newEmail}) async {
    
    // Text controllers used by form fields and input boxes.
    final codeController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool dialogLoading = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> verifyCode() async {
              final code = codeController.text.trim();

              // Validation: code must not be empty
              if (code.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Enter the code")),
                );
                return;
              }

              setDialogState(() => dialogLoading = true);

              try {
                // Verify the code using the backend Cloud Function.
                final verifyCallable =
                    FirebaseFunctions.instance.httpsCallable('verifyResetCode');

                await verifyCallable.call({
                  'email': newEmail,
                  'code': code,
                });

                // Ask Firebase Auth to start verified email update flow.
                await user!.verifyBeforeUpdateEmail(newEmail);

                // Update Firestore user document with new email fields.
                await _updateUserData({
                  'email': newEmail,
                  'emailLower': newEmail,
                });

                if (!mounted) return;
                Navigator.pop(context);

                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text("Email verified and update started successfully"),
                  ),
                );
              } on FirebaseFunctionsException catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text(e.message ?? "Wrong code")),
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Could not update email. You may need to log in again.",
                    ),
                  ),
                );
              } finally {
                if (mounted) {
                  setDialogState(() => dialogLoading = false);
                }
              }
            }

            // Method used by this screen section.
            Future<void> resendCode() async {
              setDialogState(() => dialogLoading = true);

              try {
                // Resend a new verification code to the same new email.
                final resendCallable =
                    FirebaseFunctions.instance.httpsCallable('sendResetCode');

                await resendCallable.call({
                  'email': newEmail,
                });

                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text("New code sent")),
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text("Failed to resend code")),
                );
              } finally {
                if (mounted) {
                  setDialogState(() => dialogLoading = false);
                }
              }
            }

            return AlertDialog(
            // Dialog for entering the verification code sent by email.
              title: const Text("Enter Verification Code"),
              content: SizedBox(
                width: 420,
                child: Stack(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Code sent to: $newEmail",
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: codeController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Verification Code",
                            hintText: "Enter 6-digit code",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: resendCode,
                          child: const Text("Resend Code"),
                        ),
                      ],
                    ),
                    if (dialogLoading)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black12,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: dialogLoading
                      ? null
                      : () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: dialogLoading ? null : verifyCode,
                  child: const Text("Verify"),
                ),
              ],
            );
          },
        );
      },
    );
  }


  // Opens a dialog or handles a user action related to editing/changing data.
  Future<void> _editPhoneNumber({
    required String currentCountry,
    required String currentPhone,
  }) async {
    // Validate initial selected country.
    String selectedCountry = countryCodes.containsKey(currentCountry)
        ? currentCountry
        : "Kuwait";

    // Text controllers used by form fields and input boxes.
    final phoneController = TextEditingController(text: currentPhone);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedCode = countryCodes[selectedCountry] ?? "+965";
            final maxDigits = countryPhoneMaxDigits[selectedCountry] ?? 15;

            // If current text is longer than allowed for selected country, trim it.
            if (phoneController.text.length > maxDigits) {
              phoneController.text =
                  phoneController.text.substring(0, maxDigits);
              phoneController.selection = TextSelection.fromPosition(
                TextPosition(offset: phoneController.text.length),
              );
            }

            return AlertDialog(
         // Dialog for editing the account phone number.
              title: const Text("Edit Phone Number"),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedCountry,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "Country",
                      ),
                      items: countryCodes.keys.map((country) {
                        return DropdownMenuItem<String>(
                          value: country,
                          child: Text(country),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            selectedCountry = value;
                            final newMax =
                                countryPhoneMaxDigits[selectedCountry] ?? 15;
                            if (phoneController.text.length > newMax) {
                              phoneController.text =
                                  phoneController.text.substring(0, newMax);
                              phoneController.selection =
                                  TextSelection.fromPosition(
                                TextPosition(
                                  offset: phoneController.text.length,
                                ),
                              );
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(maxDigits),
                      ],
                      maxLength: maxDigits,
                      decoration: InputDecoration(
                        labelText: "Phone Number",
                        prefixText: "$selectedCode ",
                        counterText: "",
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final localNumber = phoneController.text.trim();

                    // Validation: non-empty
                    if (localNumber.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Please enter a phone number"),
                        ),
                      );
                      return;
                    }

                    // Validation: exact length by country
                    if (localNumber.length != maxDigits) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "$selectedCountry phone number must be $maxDigits digits",
                          ),
                        ),
                      );
                      return;
                    }

                    // Validation: Kuwait numbers must start with 9, 6, or 5
                    if (selectedCountry == "Kuwait" &&
                        !RegExp(r'^[965]').hasMatch(localNumber)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Kuwait numbers must start with 9, 6, or 5",
                          ),
                        ),
                      );
                      return;
                    }

                    if (!mounted) return;
                    Navigator.pop(context);

                    // Save country, code, and full combined phone string.
                    await _updateUserData({
                      'countryName': selectedCountry,
                      'countryCode': selectedCode,
                      'phone': '$selectedCode$localNumber',
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


  // Opens a dialog or handles a user action related to editing/changing data.
  Future<void> _editEmergencyContact({
    required String currentCountry,
    required String currentName,
    required String currentPhone,
  }) async {
    // Text controllers used by form fields and input boxes.
    final nameController = TextEditingController(text: currentName);
    final phoneController = TextEditingController(text: currentPhone);

    String selectedCountry = countryCodes.containsKey(currentCountry)
        ? currentCountry
        : "Kuwait";

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final code = countryCodes[selectedCountry] ?? "+965";
            final maxDigits = countryPhoneMaxDigits[selectedCountry] ?? 15;

            // Keep current phone text within the selected country's digit limit.
            if (phoneController.text.length > maxDigits) {
              phoneController.text = phoneController.text.substring(0, maxDigits);
              phoneController.selection = TextSelection.fromPosition(
                TextPosition(offset: phoneController.text.length),
              );
            }

            return AlertDialog(
            // Dialog for editing emergency contact details.
              title: const Text("Edit Emergency Contact"),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: "Contact Name",
                          hintText: "Enter contact name",
                          hintStyle: TextStyle(color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedCountry,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Country",
                        ),
                        items: countryCodes.keys.map((country) {
                          return DropdownMenuItem(
                            value: country,
                            child: Text(country),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              selectedCountry = value;
                              final newMax =
                                  countryPhoneMaxDigits[selectedCountry] ?? 15;
                              if (phoneController.text.length > newMax) {
                                phoneController.text =
                                    phoneController.text.substring(0, newMax);
                                phoneController.selection =
                                    TextSelection.fromPosition(
                                  TextPosition(
                                    offset: phoneController.text.length,
                                  ),
                                );
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(maxDigits),
                        ],
                        decoration: InputDecoration(
                          labelText: "Phone Number",
                          hintText: "Enter phone number",
                          hintStyle: const TextStyle(color: Colors.grey),
                          prefixText: "$code ",
                        ),
                        maxLength: maxDigits,
                      ),
                    ],
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
                    final trimmedName = nameController.text.trim();
                    final trimmedPhone = phoneController.text.trim();

                    // Validation: contact name required
                    if (trimmedName.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Please enter contact name"),
                        ),
                      );
                      return;
                    }

                    // Validation: exact digit count by country
                    if (trimmedPhone.length != maxDigits) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "$selectedCountry phone number must be $maxDigits digits",
                          ),
                        ),
                      );
                      return;
                    }

                    // Validation: Kuwait numbers must start with 9, 6, or 5
                    if (selectedCountry == "Kuwait" &&
                        !RegExp(r'^[965]').hasMatch(trimmedPhone)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Kuwait numbers must start with 9, 6, or 5",
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(context);
                    await _updateUserData({
                      'emergencyContactCountry': selectedCountry,
                      'emergencyContactName': trimmedName,
                      'emergencyContactPhone': trimmedPhone,
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


  // Opens a dialog or handles a user action related to editing/changing data.
  Future<void> _changePassword() async {
    
    // Text controllers used by form fields and input boxes.
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
        // Dialog for changing the user password.
          title: const Text("Change Password"),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "New Password",
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Confirm Password",
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final newPassword = newPasswordController.text.trim();
                final confirmPassword = confirmPasswordController.text.trim();

                // Validation: all fields required
                if (newPassword.isEmpty || confirmPassword.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please fill all fields")),
                  );
                  return;
                }

                // Validation: password length
                if (newPassword.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Password must be at least 6 characters"),
                    ),
                  );
                  return;
                }

                // Validation: password match
                if (newPassword != confirmPassword) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Passwords do not match")),
                  );
                  return;
                }

                try {
                  // Direct Firebase Auth password update.
                  await user!.updatePassword(newPassword);

                  if (!mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Password changed successfully"),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Could not change password. Log in again, then try.",
                      ),
                    ),
                  );
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  // Internal helper method for the screen logic.
  Future<void> _logout() async {
    setState(() => isLoading = true);

    try {
      // Sign the user out of Firebase Auth.
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // Clear navigation stack and return to login screen.
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


  // Internal helper method for the screen logic.
  Future<void> _deleteAccount() async {
    // Ask for confirmation before permanently deleting the account.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
      // Confirmation dialog before deleting the account.
          title: const Text("Delete Account"),
          content: const Text(
            "Are you sure you want to permanently delete your account?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                "Delete",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true || user == null) return;

    setState(() => isLoading = true);

    try {
      // Delete the Auth user first, then remove the Firestore user document.
      await user!.delete();
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).delete();

      if (!mounted) return;

      // Return to login screen and clear previous routes.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Could not delete account. Log in again, then try.",
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

// Internal helper method for the screen logic.
// Section title widget to keep headings consistent across the screen.
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

// Internal helper method for the screen logic.
// Reusable card container used across multiple settings/profile sections.
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
          ),
        ],
      ),
      child: child,
    );
  }

 // Internal helper method for the screen logic.
// Reusable list tile for tappable settings rows.
  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color titleColor = navy,
    Color iconColor = softBlue,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF3FF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: titleColor,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 12,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }

// Internal helper method for the screen logic.
// Reusable switch tile for toggle-based settings.
  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeColor: softBlue,
      value: value,
      onChanged: onChanged,
      secondary: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF3FF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: softBlue),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: navy,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 12,
        ),
      ),
    );
  }
}


// AboutSystemScreen
// Main widget/class definition for this part of the app.
// This screen explains the purpose, features, behavior, and future direction of the Safe Home Monitor prototype.
class AboutSystemScreen extends StatelessWidget {
  const AboutSystemScreen({super.key});

  static const softBlue = Color(0xFF4A90E2);
  static const navy = Color(0xFF0D1B2A);
  static const bg = Color(0xFFF7F9FC);

// Main build method that returns the widget tree for the screen.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "About Safe Home Monitor",
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                blurRadius: 12,
                color: Color(0x11000000),
                offset: Offset(0, 6),
              ),
            ],
          ),

          // Static content describing the system for the user.
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Safe Home Monitor",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: navy,
                ),
              ),
              SizedBox(height: 12),
              Text(
                "Safe Home Monitor is a smart home safety application created to help caregivers monitor elderly or vulnerable people through a simple connected system. The app combines sensor monitoring, alerts, profile management, and emergency settings in one place.",
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 18),
              Text(
                "Main purpose",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: softBlue,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "The main purpose of the app is to improve safety inside the home by helping a caregiver know when something unusual happens and respond faster.",
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 18),
              Text(
                "What the app includes",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: softBlue,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "1. A profile page for caregiver and monitored person information.\n"
                "2. A system section that shows live sensor activity and last sync time.\n"
                "3. Emergency settings for choosing who should be contacted.\n"
                "4. Alarm and notification controls.\n"
                "5. Account settings such as username, email, phone, and password.",
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 18),
              Text(
                "How monitoring works",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: softBlue,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "The system reads information from home sensors such as motion, door, vibration, pressure, water leak, or other safety-related sensors. Sensor data is updated through Firebase so the caregiver can see changes in near real time.",
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 18),
              Text(
                "Emergency behavior",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: softBlue,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "When the system detects a possible emergency, it can trigger an alarm, send notifications, and use the saved emergency contact. In this prototype, the emergency contact is used to demonstrate the idea instead of directly calling official services such as 112.",
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 18),
              Text(
                "Guidelines for use",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: softBlue,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "1. Keep account and emergency contact information updated.\n"
                "2. Make sure connected sensors are working correctly.\n"
                "3. Enable the notification options you want to use.\n"
                "4. Review the monitored person information regularly.\n"
                "5. Use the settings page to manage account, alerts, and emergency actions.\n"
                "6. Treat this prototype as a concept demonstration that can be extended later into a full real-world emergency system.",
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 18),
              Text(
                "User Instructions",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: softBlue,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "1. Ensure all sensors are properly connected and sending data.\n"
                "2. Complete caregiver and monitored person information in the profile section.\n"
                "3. Set up emergency contacts and notification preferences in settings.\n"
                "4. Regularly check system status and recent alerts.\n"
                "5. Verify that the last sync time is updating to confirm real-time operation.",
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 18),
              Text(
                "AI Assistant Support",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: softBlue,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "The system includes an AI assistant that helps analyze sensor data and highlight important events in real time. It identifies unusual patterns and prioritizes critical alerts, allowing caregivers to quickly understand situations without manually monitoring all sensor activity. This improves response time and overall decision-making.",
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 18),
              Text(
                "Future Improvements",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: softBlue,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "1. More advanced AI for predictive alerts and behavior analysis.\n"
                "2. Integration with additional smart home devices and sensors.\n"
                "3. Automatic emergency service notifications when critical conditions are detected.\n"
                "4. Customizable thresholds for alerts based on user needs.\n",
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "Prototype note",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: softBlue,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "This application is a prototype built to present the concept of a smart monitoring and emergency support system. Some advanced functions may be represented as a demonstration of how the final system could behave in a real deployment.",
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}