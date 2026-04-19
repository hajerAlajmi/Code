import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'new_password_screen.dart';

// Screen where the user enters the reset code
// that was sent to their email address.
// This page is part of the password reset flow: user requests reset code, user enters code here, if code is correct, user is taken to create a new password
class EnterCodeScreen extends StatefulWidget {
  //The email address that the reset code was sent to.
  // It is passed from the previous screen so this screen knows which account/code pair should be verified.
  final String email;

  const EnterCodeScreen({
    super.key,
    required this.email,
  });

  @override
  State<EnterCodeScreen> createState() => _EnterCodeScreenState();
}

class _EnterCodeScreenState extends State<EnterCodeScreen> {
  // Main accent color used for the primary button.
  static const Color softBlue = Color(0xFF4A90E2);

  // Dark navy color used in the app bar.
  static const Color navy = Color(0xFF0D1B2A);

  // Controller for the code input field.
  // This lets the app read the exact code typed by the user.
  final TextEditingController _code = TextEditingController();

  // Controls whether the loading overlay is shown.
  // This prevents repeated taps and gives feedback while verification or resend is in progress.
  bool _isLoading = false;

  // Timer used for the countdown until code expiration.
  Timer? _timer;

  // Number of seconds remaining before the current code expires.
  // Starts at 120 seconds = 2 minutes.
  int _secondsLeft = 120;

  @override
  void initState() {
    super.initState();

    // Start the expiration countdown as soon as the screen opens.
    _startTimer();
  }

// Starts or restarts the countdown timer.
// This is used: when the page first loads, after the user requests a new code
  void _startTimer() {
    // Cancel any old timer first so multiple timers do not run together.
    _timer?.cancel();

  // Reset timer back to 2 minutes.
    _secondsLeft = 120;

    // Decrease the timer every second.
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        // When time reaches zero, stop the timer
        // and update the UI to show expiration.
        timer.cancel();
        if (mounted) {
          setState(() {
            _secondsLeft = 0;
          });
        }
      } else {
        // Otherwise keep counting down by one second.
        if (mounted) {
          setState(() {
            _secondsLeft--;
          });
        }
      }
    });
  }

  /// Returns the countdown in mm:ss format.
  String get _formattedTime {
    final minutes = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsLeft % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  void dispose() {
    // Stop the timer when leaving the screen to avoid unnecessary background work.
    _timer?.cancel();

    // Dispose text controller to prevent memory leaks.
    _code.dispose();
    super.dispose();
  }

  // Verifies the code entered by the user using Firebase Cloud Functions.
  // If the code is valid, the app moves to the new password screen.
  Future<void> verifyCode() async {
  // Read and clean the entered code.
    final enteredCode = _code.text.trim();

    // Prevent verification if the code already expired.
    if (_secondsLeft == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Code expired. Please resend code")),
      );
      return;
    }

    // Prevent empty submissions.
    if (enteredCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter the code")),
      );
      return;
    }

    // Show loading overlay while talking to the backend.
    setState(() => _isLoading = true);

    try {
      // Create callable reference for the backend function
      // that checks whether the reset code is valid.
      final callable =
          FirebaseFunctions.instance.httpsCallable('verifyResetCode');

      // Send both the email and entered code to the backend.
  // The backend checks whether: the code belongs to this email, the code exists, the code is still valid / unused
      await callable.call({
        'email': widget.email,
        'code': enteredCode,
      });

      // Stop if widget is no longer active.
      if (!mounted) return;

      // If verification succeeds, move to the screen where the user can choose a new password.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NewPasswordScreen(email: widget.email),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      // Handle errors returned directly from the Cloud Function.
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Wrong code")),
      );
    } catch (_) {
      // Handle any other unexpected error
      // such as network or general verification failure.
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Verification failed")),
      );
    } finally {
      // Always remove the loading overlay after request finishes.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Requests a brand new reset code from the backend.
  // If successful, the countdown timer restarts.
  Future<void> resendCode() async {
    // Show loading overlay while the new code is being requested.
    setState(() => _isLoading = true);

    try {
      // Create callable reference for the function
      // that sends a new reset code email.
      final callable =
          FirebaseFunctions.instance.httpsCallable('sendResetCode');

      // Send the user's email so the backend knows where to send the new code.
      await callable.call({
        'email': widget.email,
      });

      // Restart countdown because a fresh code was just sent.
      _startTimer();

      if (!mounted) return;

      // Inform the user that a new code was sent successfully.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("New code sent")),
      );
    } catch (_) {
      // Show fallback error if resending fails.
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to resend code")),
      );
    } finally {
      // Remove loading overlay whether success or failure.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Main UI of the code verification screen.
    return Scaffold(
      appBar: AppBar(
        title: const Text("Enter Code"),

        // Use app theme colors for consistent look.
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Main content area.
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
         // Show which email the code was sent to, so the user knows they are verifying the correct account.
                Text(
                  "Code sent to: ${widget.email}",
                  style: const TextStyle(fontSize: 16),
                ),

                const SizedBox(height: 10),

                // Display live countdown or expired state.
                Text(
                  _secondsLeft > 0
                      ? "Code expires in $_formattedTime"
                      : "Code expired",
                  style: TextStyle(
                    fontSize: 15,

                    // Switch text color to red when expired for clarity.
                    color: _secondsLeft > 0 ? Colors.black54 : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 20),

                // Input field for the 6-digit reset code.
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: "Enter 6-digit code",
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 20),

                // Main verification button.
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: verifyCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: softBlue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Verify Code"),
                  ),
                ),

                const SizedBox(height: 10),

                // Secondary action for requesting another code.
                TextButton(
                  onPressed: resendCode,
                  child: const Text("Resend Code"),
                )
              ],
            ),
          ),

          // Loading overlay shown during verification/resend requests.
          if (_isLoading)
            Container(
              color: Colors.black12,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            )
        ],
      ),
    );
  }
}