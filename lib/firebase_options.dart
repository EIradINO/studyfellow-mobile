// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAyjUhh_jfw5a_R1TluzfGweX1Jsymawnw',
    appId: '1:122688802398:web:147930a41036f814ffaecf',
    messagingSenderId: '122688802398',
    projectId: 'studyfellow-42d35',
    authDomain: 'studyfellow-42d35.firebaseapp.com',
    storageBucket: 'studyfellow-42d35.firebasestorage.app',
    measurementId: 'G-VHXRDQ6GTR',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDT_thGnvUFkWmTuexWGEvEq170-K-FdDs',
    appId: '1:122688802398:android:74fb59f05ef8e867ffaecf',
    messagingSenderId: '122688802398',
    projectId: 'studyfellow-42d35',
    storageBucket: 'studyfellow-42d35.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDlmwA94UtSMPDnt1sW-62jHru7ZW2UmKA',
    appId: '1:122688802398:ios:00474176647bd11effaecf',
    messagingSenderId: '122688802398',
    projectId: 'studyfellow-42d35',
    storageBucket: 'studyfellow-42d35.firebasestorage.app',
    iosBundleId: 'com.example.studyfellowFlutter',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDlmwA94UtSMPDnt1sW-62jHru7ZW2UmKA',
    appId: '1:122688802398:ios:00474176647bd11effaecf',
    messagingSenderId: '122688802398',
    projectId: 'studyfellow-42d35',
    storageBucket: 'studyfellow-42d35.firebasestorage.app',
    iosBundleId: 'com.example.studyfellowFlutter',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAyjUhh_jfw5a_R1TluzfGweX1Jsymawnw',
    appId: '1:122688802398:web:9b746ca042daea7cffaecf',
    messagingSenderId: '122688802398',
    projectId: 'studyfellow-42d35',
    authDomain: 'studyfellow-42d35.firebaseapp.com',
    storageBucket: 'studyfellow-42d35.firebasestorage.app',
    measurementId: 'G-T6DRMR1HQB',
  );

}