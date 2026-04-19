import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// Service class responsible for handling Google authentication logic.
// This keeps authentication-related code separated from UI, making the app cleaner and easier to maintain.
class GoogleAuthService {
  // FirebaseAuth instance used to perform authentication operations.
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Signs in the user using Google authentication.
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Check if the app is running on Web.
      // Google sign-in using popup is supported directly on Flutter Web, but NOT handled here for mobile (Android/iOS).
      if (kIsWeb) {
        // Create a GoogleAuthProvider instance.
        // This defines Google as the authentication method.
        final googleProvider = GoogleAuthProvider();

        // Trigger Google sign-in popup.
        // This opens a browser popup where the user selects their Google account.
        return await _auth.signInWithPopup(googleProvider);
      }

      // If not running on Web, return null.
      // (Mobile implementation would normally use google_sign_in package,but it is intentionally not included here.)
      return null;
    } catch (e) {
      // Catch any error during the sign-in process.
      // debugPrint is used instead of print to avoid cluttering logs in release mode.
      debugPrint("Google sign in error: $e");

      // Return null to indicate failure.
      return null;
    }
  }
}