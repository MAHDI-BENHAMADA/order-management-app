import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorageService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'settings';
  static const String _document = 'shipping_tokens';

  /// Save a token to Firestore. Also saves a local backup just in case.
  static Future<void> saveToken(String providerId, String token) async {
    try {
      final tokenKey = 'provider_token_$providerId';

      // 1. Save to Firestore
      await _firestore.collection(_collection).doc(_document).set(
        {tokenKey: token},
        SetOptions(merge: true),
      );

      // 2. Save local backup
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(tokenKey, token);
      
      print('✅ Token saved to Firestore for $providerId');
    } catch (e) {
      print('❌ Failed to save token to Firestore: $e');
      rethrow;
    }
  }

  /// Get a token from Firestore. If network fails, falls back to local storage.
  static Future<String?> getToken(String providerId) async {
    final tokenKey = 'provider_token_$providerId';
    String? token;

    try {
      // 1. Try fetching from Firestore
      final doc = await _firestore.collection(_collection).doc(_document).get().timeout(const Duration(seconds: 5));
      if (doc.exists) {
        token = doc.data()?[tokenKey] as String?;
        if (token != null && token.isNotEmpty) {
          // Cache it locally so it works even if offline later
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(tokenKey, token);
          return token;
        }
      }
    } catch (e) {
      print('⚠️ Failed to fetch token from Firestore: $e');
    }

    // 2. Fallback to local SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(tokenKey);
    return token;
  }
}
