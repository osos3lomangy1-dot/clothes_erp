import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';
import '../config/app_config.dart';
import '../utils/logging.dart';

class FirebaseService {
  static bool _persistenceEnabled = false;

  static Future<void> init() async {
    if (!kEnableFirebase) {
      Logging.info('🛡️ [Safe Mode] Firebase initialization skipped (ENABLE_FIREBASE=false)');
      return;
    }

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
      Logging.info('Firebase initialized successfully');
    } catch (e) {
      Logging.error('Firebase Initialization Error: $e');
      // Do not rethrow in production/desktop to prevent fatal native crashes
    }
  }
}
