import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SheetSettingsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'settings';
  static const String _document = 'sheet_defaults';

  /// Save settings to Firestore and local SharedPreferences backup
  static Future<void> saveSettings(String spreadsheetId, String productName, String basePrice) async {
    try {
      final productKey = '${spreadsheetId}_product';
      final priceKey = '${spreadsheetId}_price';

      // 1. Save to Firestore
      await _firestore.collection(_collection).doc(_document).set(
        {
          productKey: productName,
          priceKey: basePrice,
        },
        SetOptions(merge: true),
      );

      // 2. Save local backup
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(productKey, productName);
      await prefs.setString(priceKey, basePrice);
      
      print('✅ Sheet settings saved to Firestore for $spreadsheetId');
    } catch (e) {
      print('❌ Failed to save sheet settings to Firestore: $e');
      rethrow;
    }
  }

  /// Get settings from Firestore, fallback to local SharedPreferences
  static Future<Map<String, String>> getSettings(String spreadsheetId) async {
    final productKey = '${spreadsheetId}_product';
    final priceKey = '${spreadsheetId}_price';
    
    String defaultProduct = '';
    String defaultPrice = '';

    try {
      // 1. Fetch from Firestore
      final doc = await _firestore.collection(_collection).doc(_document).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          defaultProduct = data[productKey]?.toString() ?? '';
          defaultPrice = data[priceKey]?.toString() ?? '';
          
          // Cache locally
          final prefs = await SharedPreferences.getInstance();
          if (defaultProduct.isNotEmpty) await prefs.setString(productKey, defaultProduct);
          if (defaultPrice.isNotEmpty) await prefs.setString(priceKey, defaultPrice);
          
          return {
            'product': defaultProduct,
            'price': defaultPrice,
          };
        }
      }
    } catch (e) {
      print('⚠️ Failed to fetch sheet settings from Firestore: $e');
    }

    // 2. Fallback to local backup (or old format)
    final prefs = await SharedPreferences.getInstance();
    defaultProduct = prefs.getString(productKey) ?? prefs.getString('default_product_$spreadsheetId') ?? '';
    defaultPrice = prefs.getString(priceKey) ?? prefs.getString('default_price_$spreadsheetId') ?? '';
    
    return {
      'product': defaultProduct,
      'price': defaultPrice,
    };
  }
}
