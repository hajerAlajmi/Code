// Imports
// Packages and project files used by this screen.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/google_auth_service.dart';
import 'package:my_app/screens/forgot_password_screen.dart';
import 'package:my_app/screens/main_shell.dart';
import 'package:my_app/screens/signup_screen.dart';
 
 
// LoginScreen
// Main widget/class definition for this part of the app.
// This screen handles the main login flow of the application.
// It allows the user to: log in using email, log in using username, sign in with Google, navigate to forgot password,navigate to sign up
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
 
  @override
  State<LoginScreen> createState() => _LoginScreenState();
 
}
 
// _LoginScreenState
// Main widget/class definition for this part of the app.
// State class that holds live values, controllers, and UI logic for the screen.
class _LoginScreenState extends State<LoginScreen> {
 
// Color theme used across this screen to keep the UI consistent.
  static const Color softBlue = Color(0xFF4A90E2);
  static const Color navy = Color(0xFF0D1B2A);

  // Service used to handle Google sign-in logic outside this screen.
  // Keeping Google auth in a separate service makes the UI code cleaner and separates authentication logic from presentation.
  final GoogleAuthService _googleAuth = GoogleAuthService();
 
 
 // Text controllers used by form fields and input boxes.
  // _loginKey is used to validate the whole form.
  // _loginUserOrEmail stores the typed email or username.
  // _loginPass stores the typed password.
  final _loginKey = GlobalKey<FormState>();
  final _loginUserOrEmail = TextEditingController();
  final _loginPass = TextEditingController();
 
 // Controls whether the password field is currently hidden.
 bool _loginObscure = true;

 // Shows a loading overlay while authentication is in progress.
 bool _isLoading = false;

 // Firebase Authentication instance used for email/password sign-in.
 final FirebaseAuth _auth = FirebaseAuth.instance;

 // Firestore instance used to look up a user's email
 // when they try to sign in using username instead of email.
 final FirebaseFirestore _firestore = FirebaseFirestore.instance;
 
 
// Releases resources here to avoid memory leaks.
  @override
 void dispose() {
   // Dispose the text controllers when the screen is removed so they do not keep unused resources in memory.
   _loginUserOrEmail.dispose();
   _loginPass.dispose();
  super.dispose();
 }
 
// Internal helper method for the screen logic.
  Future<void> _signInWithGoogle() async {
    // Show loading overlay before starting Google sign-in.
    setState(() => _isLoading = true);

    try {
      // Ask the Google auth service to perform sign-in.
      // This may open a Google account picker depending on the platform.
 final userCredential = await _googleAuth.signInWithGoogle();

      // If sign-in succeeded and returned a credential, navigate into the main app shell.
      if (userCredential != null) {
        if (!mounted) return;
 
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
 
      }
 
    } catch (e) {
 
      // Show a generic error if Google sign-in fails for any reason.
      _snack("Google sign-in failed ❌");
 
    } finally {
 
      // Always stop loading once the attempt is finished.
      if (mounted) {
 
        setState(() => _isLoading = false);
 
      }
 
    }
 
  }
 
 
// Main build method that returns the widget tree for the screen.
  @override
 
  Widget build(BuildContext context) {
 
    return Scaffold(
 
      backgroundColor: Colors.white,
 
      body: SafeArea(
 
        child: Stack(
 
          children: [
 
            // Main scrollable content.
            // SingleChildScrollView prevents overflow on small screens when the keyboard opens or screen height is limited.
            SingleChildScrollView(
 
              child: Column(
 
                children: [
 
                  // Top header section with icon and theme color.
                  _header(),
 
                  Container(
 
                    width: double.infinity,
 
                    color: Colors.white,
 
                    padding: const EdgeInsets.all(20),
 
                    // Main login form section.
                    child: _loginForm(),
 
                  ),
 
                ],
 
              ),
 
            ),
 
            // Loading overlay shown while login is processing.
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
 
// Internal helper method for the screen logic.
// Top banner/header section shown at the top of the screen.
  Widget _header() {
 
    return Container(
 
      height: 220,
 
      width: double.infinity,
 
      color: navy,
 
      child: Column(
 
        mainAxisAlignment: MainAxisAlignment.end,
 
        children: const [
 
           Icon(Icons.shield_outlined, size: 100, color: Colors.white),
 
          const SizedBox(height: 40),        
 
        ],
 
      ),
 
    );
 
  }
 
 
// Internal helper method for the screen logic.
// Login form section with fields and action buttons.
  Widget _loginForm() {
 
    return Form(
 
      key: _loginKey,
 
      child: Column(
 
        crossAxisAlignment: CrossAxisAlignment.start,
 
        children: [
 
          // Login title.
          const Text(
 
            "Login",
 
            style: TextStyle(
 
              fontSize: 22,
 
              fontWeight: FontWeight.bold,
 
              color: navy,
 
            ),
 
          ),
 
          const SizedBox(height: 20),
 
          // Email or username field.
          // This screen accepts either:direct email, username that will later be converted into email using Firestore
          TextFormField(
 
            controller: _loginUserOrEmail,
 
            decoration: const InputDecoration(
 
              prefixIcon: Icon(Icons.person),
 
              hintText: "Email or Username",
 
              border: UnderlineInputBorder(),
 
            ),
 
            validator: (v) {
 
              final s = (v ?? "").trim();
 
              if (s.isEmpty) return "Required";
 
 
 
              // If the value contains '@', treat it like an email and validate format.
              if (s.contains("@")) {
 
                if (!_isValidEmail(s)) return "Invalid email format";
 
              } else {
 
                // Otherwise treat it like a username and validate allowed format.
                if (!_isValidUsername(s)) return "Invalid username";
 
              }
 
              return null;
 
            },
 
          ),
 
          const SizedBox(height: 15),
 
          // Password field with show/hide toggle.
          TextFormField(
 
            controller: _loginPass,
 
            obscureText: _loginObscure,
 
            decoration: InputDecoration(
 
              prefixIcon: const Icon(Icons.lock),
 
              hintText: "Password",
 
              border: const UnderlineInputBorder(),
 
              suffixIcon: IconButton(
 
                icon: Icon(
 
                  _loginObscure ? Icons.visibility_off : Icons.visibility,
 
                ),
 
                onPressed: () {
 
                  /// Toggle password visibility for easier typing.
                  setState(() => _loginObscure = !_loginObscure);
 
                },
 
              ),
 
            ),
 
            validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
 
          ),
 
          const SizedBox(height: 10),
 
          // Forgot password link.
          Align(
 
            alignment: Alignment.centerRight,
 
            child: TextButton(
 
              onPressed: _forgotPassword,
 
              child: const Text("Forgot Password?"),
 
            ),
 
          ),
 
          const SizedBox(height: 8),
 
          // Main login button.
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
 
                onPressed: _onLogin,
 
                child: const Text(
 
                  "Login",
 
                  style: TextStyle(fontWeight: FontWeight.bold),
 
                ),
 
              ),
 
            ),
 
          ),
 
          const SizedBox(height: 22),
 
          // Divider between email/password login and social options.
          _dividerText("or continue with"),
 
          const SizedBox(height: 14),
 
          // Apple sign-in button placeholder.
          // The UI exists, but the actual Apple sign-in flow has not been implemented yet.
          SizedBox(
 
            width: double.infinity,
 
            height: 50,
 
            child: OutlinedButton.icon(
 
              onPressed: () => _snack("Apple sign-in not added yet"),
 
              icon: const Icon(Icons.apple),
 
              label: const Text("Continue with Apple"),
 
            ),
 
          ),
 
          const SizedBox(height: 12),
 
          // Google sign-in button.
          SizedBox(
 
            width: double.infinity,
 
            height: 50,
 
            child: OutlinedButton.icon(
 
              onPressed: _signInWithGoogle,
 
              icon: const Icon(Icons.g_mobiledata),
 
              label: const Text("Continue with Google"),
 
            ),
 
          ),
 
          const SizedBox(height: 22),
 
          // Navigation row for users who do not yet have an account.
          Row(
 
            mainAxisAlignment: MainAxisAlignment.center,
 
            children: [
 
              const Text("Don’t have an account? "),
 
              TextButton(
 
                onPressed: () {
 
                  Navigator.push(
 
                    context,
 
                    MaterialPageRoute(builder: (_) => const SignUpScreen()),
 
                  );
 
                },
 
                child: const Text("Sign Up"),
 
              ),
 
            ],
 
          ),
 
        ],
 
      ),
 
    );
 
  }
 
 
// Internal helper method for the screen logic.
  Future<void> _onLogin() async {
 
    // Validate form before attempting sign-in.
    if (!(_loginKey.currentState?.validate() ?? false)) return;
 
 
 
    // Show loading overlay while login is being processed.
    setState(() => _isLoading = true);
 
 
 
    try {
 
      // Read typed identifier and password.
      final id = _loginUserOrEmail.text.trim();
 
      final password = _loginPass.text;
 
 
 
      // Assume the user typed an email unless proven otherwise.
      String emailToUse = id;
 
 
 
      // If the input is not an email, treat it as username and resolve the matching email from Firestore.
      if (!id.contains('@')) {
 
        emailToUse = await _findEmailFromUsername(id);
 
      }
 
 
 
      // Authenticate using Firebase Authentication.
      await _auth.signInWithEmailAndPassword(
 
        email: emailToUse,
 
        password: password,
 
      );
 
 
 
      if (!mounted) return;
 
 
 
      // Navigate into the main app once login succeeds.
      Navigator.pushReplacement(
 
        context,
 
        MaterialPageRoute(builder: (_) => const MainShell()),
 
      );
 
    } on FirebaseAuthException catch (e) {
 
      // Convert Firebase auth error codes into cleaner user-facing messages.
      _snack(_authErrorMessage(e));
 
    } catch (e) {
 
      // Fallback error for unexpected failures.
      _snack("Login failed ❌");
 
    } finally {
 
      // Always stop loading when the request ends.
      if (mounted) setState(() => _isLoading = false);
 
    }
 
  }
 
 
// Internal helper method for the screen logic.
  Future<String> _findEmailFromUsername(String usernameInput) async {
 
    // Clean the typed username.
    final typedUsername = usernameInput.trim();
 
    // Lowercase version is used as a second attempt in case the stored username is normalized differently.
    final lowerUsername = typedUsername.toLowerCase();
 
 
 
    // First attempt: exact username lookup as typed.
    QuerySnapshot<Map<String, dynamic>> query = await _firestore
 
        .collection('users')
 
        .where('username', isEqualTo: typedUsername)
 
        .limit(1)
 
        .get();
 
 
 
    // Second attempt: lowercase lookup if exact match fails.
    if (query.docs.isEmpty) {
 
      query = await _firestore
 
          .collection('users')
 
          .where('username', isEqualTo: lowerUsername)
 
          .limit(1)
 
          .get();
 
    }
 
 
 
  // If still no user is found, throw a FirebaseAuth-style exception so the rest of the login flow can handle it consistently.
    if (query.docs.isEmpty) {
 
      throw FirebaseAuthException(
 
        code: 'user-not-found',
 
        message: 'Username not found',
 
      );
 
    }
 
 
 
    final data = query.docs.first.data();
 
 
 
    // Ensure the matched user document actually contains an email.
    if (!data.containsKey('email') || data['email'] == null) {
 
      throw FirebaseAuthException(
 
        code: 'user-not-found',
 
        message: 'No email found for this username',
 
      );
 
    }
 
 
 
    // Return the email that will be used for Firebase sign-in.
    return data['email'].toString();
 
  }
 
 
// Internal helper method for the screen logic.
  Future<void> _forgotPassword() async {
 
  // Safety check before navigation.
    if (!mounted) return;
 
    Navigator.push(
 
      context,
 
      MaterialPageRoute(
 
        builder: (_) => const ForgotPasswordScreen(),
 
      ),
 
    );
 
  }
 
 
// Internal helper method for the screen logic.
  Widget _dividerText(String text) {
 
    // Small helper widget that draws a divider line, label text in the middle, and another divider line after it.
    return Row(
 
      children: [
 
        const Expanded(child: Divider()),
 
        Padding(
 
          padding: const EdgeInsets.symmetric(horizontal: 10),
 
          child: Text(text, style: const TextStyle(color: Colors.black54)),
 
        ),
 
        const Expanded(child: Divider()),
 
      ],
 
    );
 
  }
 
 
// Internal helper method for the screen logic.
  bool _isValidEmail(String s) {
 
    // Basic email format validation.
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s.trim());
 
  }
 
 
// Internal helper method for the screen logic.
  bool _isValidUsername(String s) {
 
    // Username validation:
    return RegExp(r'^[a-zA-Z0-9._]{3,}$').hasMatch(s.trim());
 
  }
 
 
// Internal helper method for the screen logic.
  String _authErrorMessage(FirebaseAuthException e) {
 
    // Maps technical Firebase error codes into cleaner messages for the user.
    switch (e.code) {
 
      case 'invalid-email':
 
        return "Invalid email ❌";
 
      case 'user-not-found':
 
        return "Account not found ❌";
 
      case 'wrong-password':
 
      case 'invalid-credential':
 
        return "Wrong email/username or password ❌";
 
      case 'too-many-requests':
 
        return "Too many attempts. Try again later ❌";
 
      default:
 
        return e.message ?? "Something went wrong ❌";
 
    }
 
  }
 
 
// Internal helper method for the screen logic.
  void _snack(String msg) {
 
    // Show a quick SnackBar message if the widget is still mounted.
    if (!mounted) return;
 
    ScaffoldMessenger.of(context).showSnackBar(
 
      SnackBar(content: Text(msg)),
 
    );
 
  }
 
}