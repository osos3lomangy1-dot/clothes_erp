import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../firebase_options.dart';

class FirebaseService {
  static bool _persistenceEnabled = false;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      if (!_persistenceEnabled) {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
        );
        _persistenceEnabled = true;
      }
    } catch (e) {
      debugPrint('Firebase Initialization Error: $e');
      rethrow; // Rethrow to see the error in the console clearly
    }
  }
}
