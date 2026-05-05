import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SheetSettingsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'settings';
  static const String _document = 'sheet_defaults';

  /// Save settings to Firestore and local SharedPreferences backup
  static Future<void> saveSettings(
    String spreadsheetId,
    String productName,
    String basePrice, {
    bool dismissed = false,
  }) async {
    try {
      final productKey = '${spreadsheetId}_product';
      final priceKey = '${spreadsheetId}_price';
      final dismissedKey = '${spreadsheetId}_setup_dismissed';

      // 1. Save to Firestore
      await _firestore.collection(_collection).doc(_document).set(
        {
          productKey: productName,
          priceKey: basePrice,
          if (dismissed) dismissedKey: true,
        },
        SetOptions(merge: true),
      );

      // 2. Save local backup
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(productKey, productName);
      await prefs.setString(priceKey, basePrice);
      if (dismissed) await prefs.setBool(dismissedKey, true);

      print('✅ Sheet settings saved to Firestore for $spreadsheetId');
    } catch (e) {
      print('❌ Failed to save sheet settings to Firestore: $e');
      rethrow;
    }
  }

  /// Get settings from Firestore, fallback to local SharedPreferences
  static Future<Map<String, dynamic>> getSettings(String spreadsheetId) async {
    final productKey = '${spreadsheetId}_product';
    final priceKey = '${spreadsheetId}_price';
    final dismissedKey = '${spreadsheetId}_setup_dismissed';

    String defaultProduct = '';
    String defaultPrice = '';
    bool setupDismissed = false;

    try {
      // 1. Fetch from Firestore
      final doc = await _firestore.collection(_collection).doc(_document).get().timeout(const Duration(seconds: 5));
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          defaultProduct = data[productKey]?.toString() ?? '';
          defaultPrice = data[priceKey]?.toString() ?? '';
          setupDismissed = data[dismissedKey] == true;

          // Cache locally
          final prefs = await SharedPreferences.getInstance();
          if (defaultProduct.isNotEmpty) await prefs.setString(productKey, defaultProduct);
          if (defaultPrice.isNotEmpty) await prefs.setString(priceKey, defaultPrice);
          if (setupDismissed) await prefs.setBool(dismissedKey, true);

          return {
            'product': defaultProduct,
            'price': defaultPrice,
            'dismissed': setupDismissed,
          };
        }
      }
    } catch (e) {
      print('⚠️ Failed to fetch sheet settings from Firestore: $e');
    }

    // 2. Fallback to local backup
    final prefs = await SharedPreferences.getInstance();
    defaultProduct = prefs.getString(productKey) ?? prefs.getString('default_product_$spreadsheetId') ?? '';
    defaultPrice = prefs.getString(priceKey) ?? prefs.getString('default_price_$spreadsheetId') ?? '';
    setupDismissed = prefs.getBool(dismissedKey) ?? false;

    return {
      'product': defaultProduct,
      'price': defaultPrice,
      'dismissed': setupDismissed,
    };
  }
}
