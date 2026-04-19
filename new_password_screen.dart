import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

// Screen where the user creates a new password after their reset code has already been verified.
// This is the final step in the custom password reset flow: user requests a reset code, user verifies the code, user sets a new password here
class NewPasswordScreen extends StatefulWidget {
  // Email address of the account whose password is being reset.
  // This is passed from the previous screen so the backend knows which account to update.
  final String email;

  const NewPasswordScreen({
    super.key,
    required this.email,
  });

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  // Main accent color used for the primary button.
  static const Color softBlue = Color(0xFF4A90E2);

  // Dark navy color used in the app bar.
  static const Color navy = Color(0xFF0D1B2A);

  // Controller for the new password field.
  // This stores the first password entry typed by the user.
  final TextEditingController _password = TextEditingController();

  // Controller for the confirm password field.
  // This stores the repeated password entry so the app can compare both values.
  final TextEditingController _confirm = TextEditingController();

  // Controls whether a loading overlay is visible.
  // This is useful while waiting for the backend to complete the password reset request.
  bool _isLoading = false;

  @override
  void dispose() {
    // Dispose both controllers when the screen is removed to avoid memory leaks.
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // Sends the new password to the backend so the account password can be updated.
  // This method also performs local validation before calling the backend: fields must not be empty, password must be at least 6 characters, password and confirm password must match
  Future<void> resetPassword() async {
    // Read and trim the entered passwords.
    final pass = _password.text.trim();
    final confirm = _confirm.text.trim();

    // Reject empty input.
    if (pass.isEmpty || confirm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter password")),
      );
      return;
    }

    // Enforce minimum password length before sending to backend.
    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password must be at least 6 characters")),
      );
      return;
    }

    // Ensure both entered passwords match exactly.
    if (pass != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Passwords do not match")),
      );
      return;
    }

    // Show loading overlay while backend request is running.
    setState(() => _isLoading = true);

    try {
      // Create a callable reference to the backend function
      // responsible for updating the password.
      final callable =
          FirebaseFunctions.instance.httpsCallable('resetPasswordWithCode');

      // Send the email and new password to the backend.
      // The backend is expected to verify reset flow state, update the account password, reject invalid or expired reset attempts
      await callable.call({
        'email': widget.email,
        'newPassword': pass,
      });

      if (!mounted) return;

      // Show success feedback when password reset is completed.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password reset successfully")),
      );

      // Return the user back to the first route, which is usually the login screen.
      // This makes sense because after changing the password, the user should typically log in again with the new one.
      Navigator.popUntil(context, (route) => route.isFirst);
    } on FirebaseFunctionsException catch (e) {
      // Handle Cloud Function specific errors, such as invalid reset state or backend rejection.
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Failed to reset password")),
      );
    } catch (_) {
      // Handle any unexpected error, such as network issues or unknown failures.
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Something went wrong")),
      );
    } finally {
      // Always remove loading state after the request finishes.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Main UI for entering a new password.
    return Scaffold(
      appBar: AppBar(
        title: const Text("New Password"),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Main form-like content.
          // Stack is used so the loading overlay can appear above this content.
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Shows which account is being updated, so the user knows they are resetting the correct email.
                Text(
                  "Reset password for: ${widget.email}",
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),

                // New password field.
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: "New password",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                // Confirm password field.
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: "Confirm password",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                // Primary submit button for resetting the password.
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: resetPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: softBlue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Reset Password"),
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay shown while waiting for the backend response.
          if (_isLoading)
            Container(
              color: Colors.black12,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}