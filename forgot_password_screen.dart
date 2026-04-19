import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'enter_code_screen.dart';

// Screen used to start the password reset flow.
// The user enters their email here, and if the email format is valid, the app requests a verification code from the backend.
// After that, the user is taken to the next screen, where they can enter the received code.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  // Main accent color used for the primary action button.
  static const Color softBlue = Color(0xFF4A90E2);

  // Dark navy color used for the app bar and main heading text.
  static const Color navy = Color(0xFF0D1B2A);

  // Global form key used to validate the whole form before submitting.
  // This allows the screen to check whether the email field is valid before calling the backend function.
  final _formKey = GlobalKey<FormState>();

  // Controller for the email input field.
  // This gives direct access to the typed email valuemand also needs to be disposed later.
  final TextEditingController _emailController = TextEditingController();

  // Controls whether the loading overlay is shown.
  // This is useful while waiting for the backend to send the reset code, so the user cannot repeatedly press the button.
  bool _isLoading = false;

  @override
  void dispose() {
    // Dispose the controller to avoid memory leaks when this screen is removed.
    _emailController.dispose();
    super.dispose();
  }

  // Validates email format using a simple regex pattern.
  // This catches obvious invalid emails before sending the request to Firebase Cloud Functions.
  bool _isValidEmail(String s) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s.trim());
  }

  // Sends the reset code request to the backend.
  // Steps: validate the form, normalize the email, call the Cloud Function, show success message, navigate to the code entry screen
  Future<void> _sendCode() async {
    // Stop immediately if the form is invalid.
    // This prevents unnecessary backend calls when the email field is empty or malformed.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Show loading overlay during the request.
    setState(() => _isLoading = true);

    try {
      // Read the typed email, trim spaces, and convert it to lowercase.
      // Lowercasing helps keep email handling consistent because emails are generally treated case-insensitively.
      final email = _emailController.text.trim().toLowerCase();

      // Create a callable reference to the backend function responsible for generating and sending the reset code.
      final callable =
          FirebaseFunctions.instance.httpsCallable('sendResetCode');

      // Send the email to the backend.
      // The backend will usually: generate a verification code, store or validate it, send it to the user's email
      await callable.call({
        'email': email,
      });

      // Do not continue if the widget is no longer mounted.
      if (!mounted) return;

      // Inform the user that the verification code was sent.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Verification code sent to your email")),
      );

      // Move to the next step of the flow:the screen where the user enters the received code.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EnterCodeScreen(email: email),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      // Handle errors returned from the Cloud Function itself.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Failed to send code")),
      );
    } catch (_) {
      // Handle any unexpected error outside the function-specific exception, such as connectivity issues or other runtime problems.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Something went wrong")),
      );
    } finally {
      // Always remove loading state after the operation finishes, whether it succeeds or fails.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Main UI for requesting a password reset code.
    return Scaffold(
      appBar: AppBar(
        title: const Text("Forgot Password"),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Main form content.
          // Stack is used so the loading overlay can appear above this content.
          Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main heading.
                  const Text(
                    "Forgot your password?",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Small explanatory text telling the user what this page does.
                  const Text(
                    "Enter your email to receive a verification code.",
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 24),

                  // Email input field.
                  // Uses TextFormField so it can participate in form validation.
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: "Enter your email",
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      // Clean the value before validating.
                      final email = value?.trim() ?? '';

                      // Email field cannot be empty.
                      if (email.isEmpty) return "Email is required";

                      // Email must match a valid format.
                      if (!_isValidEmail(email)) return "Enter a valid email";

                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Main submit button.
                  // Calls _sendCode to start the password reset process.
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _sendCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: softBlue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("Send Verification Code"),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Loading overlay shown while waiting for backend response.
          // This gives feedback and prevents repeated taps.
          if (_isLoading)
            Container(
              color: Colors.black12,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}