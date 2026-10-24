import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../features/auth/data/models/user_model.dart';

class FirebaseSetup {
  /// Use this to manually create an admin user in Firestore if you get the
  /// "User data not found" error.
  /// Call this from main.dart once with your Auth UID.
  static Future<void> setupAdmin(String uid, String email, String name) async {
    try {
      final firestore = FirebaseFirestore.instance;

      final adminUser = UserModel(
        id: uid,
        name: name,
        email: email,
        role: 'admin',
        isActive: true,
        createdAt: DateTime.now(),
      );

      await firestore
          .collection('users')
          .doc(uid)
          .set(adminUser.toFirestore());

      debugPrint('Admin user setup successfully in Firestore for UID: $uid');
    } catch (e) {
      debugPrint('Error setting up admin user: $e');
    }
  }
}
