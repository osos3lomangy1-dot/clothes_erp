// lib/core/firebase/firebase_service.dart
class FirebaseService {
  static Future<void> init() async {
    // Firebase intentionally removed on Windows (C++ SDK crashes).
    // No-op for backward compatibility.
  }
}
