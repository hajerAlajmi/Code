 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main_shell.dart';
 
// Sign up screen for creating a new user account.
// This screen collects personal details, validates the input, creates the Firebase Authentication account, then stores additional profile data inside Firestore.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
 
 
 
  @override
 
  State<SignUpScreen> createState() => _SignUpScreenState();
 
}
 
 
 
class _SignUpScreenState extends State<SignUpScreen> {
// Main accent color used for buttons and highlighted UI elements.
  static const Color softBlue = Color(0xFF4A90E2);
// Dark navy color used in headers and section titles.
  static const Color navy = Color(0xFF0D1B2A);
 
 // Global key used to access and validate the entire form.
 // This lets us call validate() on all fields at once before submitting.
  final _signKey = GlobalKey<FormState>();
 
 // Controllers for text input fields.
 // These allow direct access to the current typed values and also let us properly dispose memory later.
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _signUsername = TextEditingController();
  final _signEmail = TextEditingController();
  final _signPass = TextEditingController();
  final _signConfirm = TextEditingController();
  final _phone = TextEditingController();
 
 
// Controls password visibility for the password field.
  bool _signObscure = true;
// Controls password visibility for the confirm password field.
  bool _confirmObscure = true;
// Shows a loading overlay while sign-up is being processed.
// This prevents duplicate submissions and gives visual feedback that the app is currently working.
  bool _isLoading = false;
 
 
// Available country options with their dialing codes.
// The selected country affects both the shown dial code and the phone number validation length.
  final List<Map<String, String>> _countries = const [
    {"name": "Kuwait", "code": "+965"},
    {"name": "UAE", "code": "+971"},
    {"name": "Oman", "code": "+968"},
    {"name": "Saudi Arabia", "code": "+966"},
    {"name": "Qatar", "code": "+974"},
    {"name": "Bahrain", "code": "+973"},
  ];
 
 
// Maximum valid local phone digits for each supported country.
// This is used both in the input formatter and in validation so the user cannot enter too many digits for the chosen country.
  final Map<String, int> _countryPhoneMaxDigits = const {
    "Kuwait": 8,
    "UAE": 9,
    "Oman": 8,
    "Saudi Arabia": 9,
    "Qatar": 8,
    "Bahrain": 8,
  };
 
 
// Currently selected country name.
  String _countryName = "Kuwait";
// Currently selected country code.
  String _countryCode = "+965";
 
 
// Stores the selected date of birth.
// Nullable because the user may not have picked a date yet.
  DateTime? _dob;
// Default selected gender.
  String _gender = "Female";
 
 
// Whether the user wants to receive email notifications.
  bool _notifyEmail = true;
// Whether the user wants to receive mobile notifications.
  bool _notifyMobile = true;
 
 
// Firebase Authentication instance used to create user accounts.
  final _auth = FirebaseAuth.instance;
// Firestore instance used to save extra user profile data.
  final _firestore = FirebaseFirestore.instance;
 
 
// Returns the currently allowed phone digit count based on the selected country.
// If for some reason the country is not found, it safely falls back to 8 digits.
  int get _currentPhoneMaxDigits =>
      _countryPhoneMaxDigits[_countryName] ?? 8;
 
 
 
  @override
 
  void dispose() {
// Dispose all text controllers to prevent memory leaks.
// This is an important cleanup step for StatefulWidgets that use TextEditingController.
    _firstName.dispose();
    _lastName.dispose();
    _signUsername.dispose();
    _signEmail.dispose();
    _signPass.dispose();
    _signConfirm.dispose();
    _phone.dispose();
    super.dispose();
  }
 
 
 
  @override
 
  Widget build(BuildContext context) {
// Main screen layout.
// Uses a Stack so the loading overlay can appear above the form without replacing the actual screen content.
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Scrollable content to avoid overflow on smaller screens.
            SingleChildScrollView(
              child: Column(
                children: [
                // Top decorative/sign-up header section.
                  _header(),
 
 
                // Main white container that holds the form fields.
                Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.all(20),
                    child: _signUpForm(),
                  ),
                ],
              ),
            ),
 
 
            // Full-screen loading overlay shown during sign-up requests.
            if (_isLoading)
              Container(
                color: Colors.black12,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
 
 
 
  Widget _header() {
// Top banner of the sign-up screen.
// Uses the app's navy color and a large icon to visually indicate that this page is for account creation.
    return Container(
      height: 220,
      width: double.infinity,
      color: navy,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: const [
          Icon(Icons.person_add_alt_1, size: 100, color: Colors.white),
          SizedBox(height: 40),
        ],
      ),
    );
  }
 
 
 
  Widget _signUpForm() {
// Main sign-up form.
// This contains all user inputs, validators, dropdowns, toggles, and the submit button.
    return Form(
      key: _signKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // Form title.
        const Text(
            "Create Account",
            style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: navy,
            ),
          ),
          const SizedBox(height: 20),
 
 
        // First name field.
        // Required so every account has a proper personal identity.
          TextFormField(
            controller: _firstName,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.person),
              hintText: "First Name",
              border: UnderlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? "Required" : null,
          ),
          const SizedBox(height: 15),
 
          // Last name field.
          // Also required and later combined with first name to produce the fullName stored in Firestore.
          TextFormField(
            controller: _lastName,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.person_outline),
              hintText: "Last Name",
              border: UnderlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? "Required" : null,
          ),
          const SizedBox(height: 15),
 
          // Username field.
          // The input is validated to allow letters, numbers,dots, and underscores only.
          TextFormField(
            controller: _signUsername,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.alternate_email),
              hintText: "Username",
              border: UnderlineInputBorder(),
            ),
            validator: (v) {
              final s = (v ?? "").trim().toLowerCase();
              // Empty usernames are rejected immediately.
              if (s.isEmpty) return "Required";
              // Prevents invalid username characters and very short usernames.
              if (!_isValidUsername(s)) {
                return "Only letters, numbers, . and _";
              }
              return null;
            },
          ),
          const SizedBox(height: 15),
 
 
          // Email input field.
          // Uses a basic email format validator before Firebase is called.
          TextFormField(
            controller: _signEmail,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.mail),
              hintText: "Email",
              border: UnderlineInputBorder(),
            ),
            validator: (v) {
              final s = (v ?? "").trim();
              if (s.isEmpty) return "Required";
              // Stops obviously invalid email formats early.
              if (!_isValidEmail(s)) return "Invalid email format ❌";
              return null;
            },
          ),
          const SizedBox(height: 15),
 
 
          // Password field.
          // Obscured by default, with an eye icon to toggle visibility.
          TextFormField(
            controller: _signPass,
            obscureText: _signObscure,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock),
              hintText: "Password",
              border: const UnderlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _signObscure ? Icons.visibility_off : Icons.visibility,
                ),
                // Toggles password visibility for better usability.
                onPressed: () => setState(() => _signObscure = !_signObscure),
              ),
            ),
            validator: (v) {
              final s = v ?? "";
              if (s.isEmpty) return "Required";
              // Enforces minimum password strength:
              // at least 8 characters, letters, and digits.
              if (!_isStrongPassword(s)) return "Min 8 + letters + digits ❌";
              return null;
            },
          ),
          const SizedBox(height: 15),
 
 
          // Confirm password field.
          // Must exactly match the original password field.
          TextFormField(
            controller: _signConfirm,
            obscureText: _confirmObscure,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_outline),
              hintText: "Confirm Password",
              border: const UnderlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _confirmObscure ? Icons.visibility_off : Icons.visibility,
                ),
                // Toggles confirm password visibility separately.
                onPressed: () =>
                    setState(() => _confirmObscure = !_confirmObscure),
              ),
            ),
            validator: (v) {
              if ((v ?? "").isEmpty) return "Required";
              // Ensures both password entries match exactly.
              if (v != _signPass.text) return "Passwords do not match ❌";
              return null;
            },
          ),
          const SizedBox(height: 22),
 
 
 
          // Section title for phone number input.
          const Text(
            "Mobile Number",
            style: TextStyle(fontWeight: FontWeight.bold, color: navy),
          ),
          const SizedBox(height: 8),
 
          // Phone input row:
          // left = country code dropdown
          // right = local number input
          Row(
            children: [
              Expanded(flex: 3, child: _countryCodeDropdown()),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
 
                  // Input formatters restrict the input in real time:
                  // digits only
                  // max length based on selected country
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(_currentPhoneMaxDigits),
                  ],
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.phone),
                    hintText: "Phone number",
                    border: UnderlineInputBorder(),
                  ),
                  validator: (v) {
                    final s = (v ?? "").trim();
 
                    // Field cannot be left empty.
                    if (s.isEmpty) return "Required";
 
                    // Only digits are allowed.
                    if (!RegExp(r'^\d+$').hasMatch(s)) {
                      return "Digits only";
                    }
 
                    // Exact length must match the selected country rules.
                    if (s.length != _currentPhoneMaxDigits) {
                      return "$_countryName number must be $_currentPhoneMaxDigits digits";
                    }
 
                 // Kuwait-specific validation:
                 // local numbers must start with 9, 6, or 5.
                 if (_countryName == "Kuwait") {
                 if (!RegExp(r'^[965]').hasMatch(s)) {
                   return "Kuwait numbers must start with 9, 6, or 5";
                   }
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
 
          // Date of birth section title.
          const Text(
            "Date of Birth",
            style: TextStyle(fontWeight: FontWeight.bold, color: navy),
          ),
          const SizedBox(height: 8),
 
          // Custom date picker field.
          // Tapping this container opens the date picker.
          InkWell(
            onTap: _pickDob,
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cake_outlined, color: Colors.black54),
                  const SizedBox(width: 10),
 
                  // Shows placeholder text until a date is selected.
                  Text(_dob == null ? "Select date" : _formatDob(_dob!)),
                  const Spacer(),
                  const Icon(Icons.calendar_month, color: Colors.black54),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
 
          // Gender section title.
          const Text(
            "Gender",
            style: TextStyle(fontWeight: FontWeight.bold, color: navy),
          ),
          const SizedBox(height: 8),
 
          // Reusable gender dropdown widget.
          _genderDropdown(),
          const SizedBox(height: 12),
 
          // Email notification preference card.
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: softBlue.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Receive Email Notifications"),
              value: _notifyEmail,
              // Updates the saved preference in local state.
              onChanged: (v) => setState(() => _notifyEmail = v),
              activeColor: softBlue,
            ),
          ),
 
          // Mobile notification preference card.
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: softBlue.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Receive Mobile Notifications"),
              value: _notifyMobile,
              // Updates the saved preference in local state.
              onChanged: (v) => setState(() => _notifyMobile = v),
              activeColor: softBlue,
            ),
          ),
          const SizedBox(height: 10),
 
          // Main sign-up button.
          // Triggers validation, Firebase Auth account creation and Firestore user document creation.
          Center(
            child: SizedBox(
              width: 160,
              height: 42,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: softBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _onSignUp,
                child: const Text(
                  "Sign Up",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
 
          // Navigation text for users who already have an account.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Already have an account? "),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Login"),
              ),
            ],
          ),
        ],
      ),
    );
  }
 
 
 
  Future<void> _onSignUp() async {
    // Stop immediately if any form field fails validation.
    if (!(_signKey.currentState?.validate() ?? false)) return;
 
    // Date of birth is validated outside TextFormField
    // because it is selected through a custom widget.
    if (_dob == null) {
      _snack("Date of birth required ❌");
      return;
    }
 
 
    // Show loading overlay while network/database work is happening.
    setState(() => _isLoading = true);
 
 
 
    try {
      // Normalize and collect all values before sending to Firebase.
      final email = _signEmail.text.trim().toLowerCase();
      final password = _signPass.text;
      final username = _signUsername.text.trim();
      final usernameLower = username.toLowerCase();
      final phone = _phone.text.trim();
 
      // Final stored phone = country code + local number.
      final fullPhone = '$_countryCode$phone';
 
      // Check if username already exists in Firestore.
      // Using a lowercase version avoids duplicates
      final usernameQuery = await _firestore
          .collection('users')
          .where('usernameLower', isEqualTo: usernameLower)
          .limit(1)
          .get();
 
 
      if (usernameQuery.docs.isNotEmpty) {
        _snack("Username already exists ❌");
        if (mounted) setState(() => _isLoading = false);
        return;
      }
 
 
      // Check if phone number already exists.
      // This helps prevent multiple accounts using the same phone number.
      final phoneQuery = await _firestore
          .collection('users')
          .where('phone', isEqualTo: fullPhone)
          .limit(1)
          .get();
 
 
 
      if (phoneQuery.docs.isNotEmpty) {
        _snack("Phone number already exists ❌");
        if (mounted) setState(() => _isLoading = false);
        return;
      }
 
 
      // Create the actual Firebase Authentication account.
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
 
      // Grab the generated Firebase user ID.
      final uid = cred.user!.uid;
 
 
      // Save extra user profile information in Firestore.
      // Firebase Auth stores basic auth credentials, while Firestore stores the custom profile fields.
      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'username': username,
        'usernameLower': usernameLower,
        'email': email,
        'emailLower': email,
        'firstName': _firstName.text.trim(),
        'lastName': _lastName.text.trim(),
 
        // Precomputed full name for convenience in later screens.
        'fullName': '${_firstName.text.trim()} ${_lastName.text.trim()}',
 
        'phone': fullPhone,
        'countryName': _countryName,
        'countryCode': _countryCode,
 
        // Date stored in ISO format so it stays database-friendly and sortable.
        'dob': _dob!.toIso8601String(),
 
        'gender': _gender,
 
        // User-selected notification preferences.
        'emailAlerts': _notifyEmail,
        'mobileAlerts': _notifyMobile,
 
        // Default system settings enabled for new users.
        'emergencyAlerts': true,
        'soundAlarm': true,
        'callEmergencyContact': true,
 
        // Server-generated timestamp is more reliable than device time.
        'createdAt': FieldValue.serverTimestamp(),
      });
 
 
      // Inform the user of success.
      _snack("Account created ✅");
 
 
      // Extra safety check before using context after async work.
      if (!mounted) return;
 
      // Navigate to the main app and remove previous routes so the user cannot go back to sign-up using back button.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainShell()),
        (route) => false,
      );
 
    } on FirebaseAuthException catch (e) {
      // Convert Firebase auth error codes into clearer user-friendly messages.
      _snack(_authErrorMessage(e));
    } catch (_) {
      // Generic fallback error for unexpected failures.
      _snack("Sign up failed ❌");
    } finally {
      // Always turn off the loading overlay, whether sign-up succeeds or fails.
      if (mounted) setState(() => _isLoading = false);
    }
  }
 
 
 
  Widget _countryCodeDropdown() {
    // Country selector widget.
    // Updates both country name and country code, and also trims the current phone input if it becomes too long for the newly selected country.
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: "$_countryName $_countryCode",
          isExpanded: true,
          items: _countries
              .map(
                (c) => DropdownMenuItem<String>(
                  value: "${c["name"]} ${c["code"]}",
                  child: Text("${c["name"]} ${c["code"]}"),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v == null) return;
 
            // Split selection to isolate country code from full displayed text.
            final parts = v.split(" ");
            final code = parts.last;
            final name = v.substring(0, v.length - code.length).trim();
 
            setState(() {
              _countryName = name;
              _countryCode = code;
 
              // If the existing phone input is longer than the new country's limit, trim it immediately so the field remains valid.
              final maxDigits = _currentPhoneMaxDigits;
              if (_phone.text.length > maxDigits) {
                _phone.text = _phone.text.substring(0, maxDigits);
                // Move cursor to the end after trimming text.
                _phone.selection = TextSelection.fromPosition(
                  TextPosition(offset: _phone.text.length),
                );
              }
            });
          },
        ),
      ),
    );
  }
 
 
 
  Widget _genderDropdown() {
    // Simple gender dropdown widget.
    // Keeps this part separate for cleaner build method organization.
    const items = ["Female", "Male", "Other"];
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _gender,
          isExpanded: true,
          items: items
              .map((g) => DropdownMenuItem(value: g, child: Text(g)))
              .toList(),
          // Updates selected gender in state.
          onChanged: (v) => setState(() => _gender = v!),
        ),
      ),
    );
  }
 
 
 
  Future<void> _pickDob() async {
    // Opens a material date picker for selecting date of birth.
    // Default initial date assumes an 18-year-old user, which is a practical and user-friendly starting point.
    final now = DateTime.now();
 
    final picked = await showDatePicker(
 
      context: context,
 
      initialDate: DateTime(now.year - 18, now.month, now.day),
 
      firstDate: DateTime(1900, 1, 1),
 
      lastDate: now,
 
    );
    // Save the selected date only if the user did not cancel.
    if (picked != null) {
      setState(() => _dob = picked);
    }
  }
 
 
 
  String _formatDob(DateTime d) {
    // Formats date of birth as dd/mm/yyyy for display in the UI.
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return "$dd/$mm/$yyyy";
  }
 
 
 
  bool _isValidEmail(String s) =>
      // Basic regex for email structure validation.
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s.trim());
 
 
 
  bool _isValidUsername(String s) =>
      // Allows letters, digits, dot, and underscore.
      // Also requires at least 3 characters.
      RegExp(r'^[a-zA-Z0-9._]{3,}$').hasMatch(s.trim());
 
 
 
  bool _isStrongPassword(String s) {
    // Minimum length check.
    if (s.length < 8) return false;
 
    // Password must contain at least one letter.
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(s);
 
    // Password must contain at least one digit.
    final hasDigit = RegExp(r'\d').hasMatch(s);
 
    // Both conditions must be true.
    return hasLetter && hasDigit;
  }
 
 
 
  String _authErrorMessage(FirebaseAuthException e) {
    // Maps Firebase auth error codes to cleaner messages for users.
    switch (e.code) {
      case 'email-already-in-use':
        return "Email already exists ❌";
      case 'invalid-email':
        return "Invalid email ❌";
      case 'weak-password':
        return "Password is too weak ❌";
      case 'too-many-requests':
        return "Too many attempts. Try again later.";
      default:
        return e.message ?? "Something went wrong ❌";
    }
  }
 
  void _snack(String msg) {
    // Small helper to show SnackBar messages safely.
    // The mounted check avoids using context if the widget
    // was already removed from the widget tree.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
}