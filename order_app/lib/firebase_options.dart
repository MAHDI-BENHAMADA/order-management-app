import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDLb0vyzWf3QDlQhHmmsMOkwEfbvVuv2iA',
    appId: '1:909066568788:android:861236afe68864d61399c1',
    messagingSenderId: '909066568788',
    projectId: 'order-management-d9f96',
    storageBucket: 'order-management-d9f96.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCn18BQrBudBzI7nzuTdWRwKmyA20s-lSI',
    appId: '1:909066568788:web:51eaa3beb846a46e1399c1',
    messagingSenderId: '909066568788',
    projectId: 'order-management-d9f96',
    authDomain: 'order-management-d9f96.firebaseapp.com',
    storageBucket: 'order-management-d9f96.firebasestorage.app',
  );

}