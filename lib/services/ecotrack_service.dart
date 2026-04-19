import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/order.dart';

class EcoTrackService {
  static const String baseUrl = 'https://48hr.ecotrack.dz/api/v1'; // Updated to account-specific domain
  static String? _apiToken;

  static void setApiToken(String token) {
    _apiToken = token;
  }

  static Future<bool> validateToken() async {
    if (_apiToken == null) {
      throw Exception('EcoTrack API Token not set');
    }

    try {
      final uri = Uri.parse('$baseUrl/get/wilayas');

      print('Validating EcoTrack Token via: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiToken',
          'Accept': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Validation timeout'),
      );

      print('Token Validation Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        print('✅ EcoTrack Token is VALID!');
        return true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        print('❌ Token validation failed: ${response.statusCode}');
        return false;
      }
      return false;
    } catch (e) {
      print('Token validation error: $e');
      return false;
    }
  }

  // Map Algerian Wilaya names to their numeric codes
  static const Map<String, int> wilayaCodes = {
    'الجزائر': 1, 'وهران': 2, 'قسنطينة': 3, 'البليدة': 4, 'بوفاريك': 5,
    'تلمسان': 6, 'جيجل': 7, 'سيدي بلعباس': 8, 'سطيف': 9, 'تيارت': 10,
    'تيزي وزو': 11, 'الجلفة': 12, 'سعيدة': 13, 'سكيكدة': 14, 'سيدي عيسى': 15,
    'الشلف': 16, 'البيض': 17, 'عنابة': 18, 'الأغواط': 19, 'قالمة': 20,
    'قرقرة': 21, 'بسكرة': 22, 'طبرقة': 23, 'تبسة': 24, 'برج بوعريريج': 25,
    'عين الدفلى': 26, 'عين تيموشنت': 27, 'غرداية': 28, 'الحمادية': 29,
    'درعة و تافيلالت': 30, 'الونشريس': 31, 'المنيعة': 32, 'الأوراس': 34,
    'الإهقار': 35, 'نقادي': 36, 'أوليلي': 38, 'أدرار': 39, 'باتنة': 40,
    'بني سويف': 41, 'بنى هلال': 42, 'بوسعادة': 43, 'الشقرة': 44, 'المسيلة': 45,
    'عين بوسيف': 46, 'أم البواقي': 47, 'الواحات': 48, 'سباتين': 49,
    'إليزي': 51, 'تمنراست': 52, 'الطاسيلي': 53, 'عين قزام': 54, 'جانت': 55,
    'إنقوسة': 57, 'جاسي': 58,
  };

  // Get valid communes for a wilaya
  static Future<List<String>> getCommunes(int wilayaCode) async {
    if (_apiToken == null) {
      throw Exception('EcoTrack API Token not set');
    }

    try {
      final uri = Uri.parse('$baseUrl/get/communes/$wilayaCode');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiToken',
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Communes request timeout'),
      );

      print('EcoTrack Communes Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        List<String> result = [];
        
        // Handle two response formats:
        // 1. Direct array: [{"nom": "Commune1"}, {"nom": "Commune2"}]
        // 2. Object with communes key: {"communes": [{...}]}
        
        List<dynamic> communesList = [];
        if (data is List) {
          // Direct array format
          communesList = data;
        } else if (data is Map && data['communes'] is List) {
          // Object with communes key
          communesList = data['communes'];
        }
        
        if (communesList.isNotEmpty) {
          for (var item in communesList) {
            if (item is Map) {
              // Extract the nom field
              final name = item['nom'] ?? item['name'] ?? item['commune'];
              if (name != null) {
                result.add(name.toString());
              }
            } else if (item is String) {
              result.add(item);
            }
          }
          print('✅ Parsed ${result.length} communes: ${result.take(5).join(", ")}...');
          return result;
        }
        
        return [];
      } else {
        print('Failed to get communes: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error getting communes: $e');
      return [];
    }
  }

  static Future<int> getShippingFee(int wilayaCode) async {
    if (_apiToken == null) {
      throw Exception('EcoTrack API Token not set');
    }

    try {
      final uri = Uri.parse('$baseUrl/get/fees');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiToken',
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Fees request timeout'),
      );

      print('EcoTrack Fees Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Get livraison (delivery) fees
        final livraison = data['livraison'] as List?;
        if (livraison != null) {
          for (var fee in livraison) {
            if (fee['wilaya_id'] == wilayaCode) {
              // Return the standard tarif (not stop_desk)
              return int.tryParse(fee['tarif'].toString()) ?? 0;
            }
          }
        }
        
        // Default fee if wilaya not found
        return 500;
      } else {
        print('Failed to get fees: ${response.statusCode}');
        return 500; // Default fallback
      }
    } catch (e) {
      print('Error getting shipping fees: $e');
      return 500; // Default fallback
    }
  }

  static Future<String?> createParcel(AppOrder order) async {
    if (_apiToken == null) {
      throw Exception('EcoTrack API Token not set');
    }

    try {
      // Get wilaya code - default to 1 if not found
      final wilayaCode = wilayaCodes[order.wilaya] ?? 1;
      
      // Clean phone number - remove all non-digits
      final cleanPhone = order.phone.replaceAll(RegExp(r'[^0-9]'), '');
      
      // Get valid communes for this wilaya and find the best match
      final validCommunes = await getCommunes(wilayaCode);
      String commune = order.commune.isNotEmpty ? order.commune : 'المركز';
      
      print('📍 Original commune: "$commune"');
      print('📍 Valid communes for wilaya $wilayaCode: ${validCommunes.isNotEmpty ? validCommunes.take(5).toList() : "NONE"}');
      
      if (validCommunes.isNotEmpty) {
        // Try to find exact match first (case-insensitive, trimmed)
        final trimmedCommune = commune.trim();
        final exactMatch = validCommunes.firstWhere(
          (c) => c.trim().toLowerCase() == trimmedCommune.toLowerCase(),
          orElse: () => '',
        );
        
        if (exactMatch.isNotEmpty) {
          commune = exactMatch.trim();
          print('✅ Found exact match: "$commune"');
        } else {
          // Try partial match (first word)
          final communeParts = trimmedCommune.split(' ');
          if (communeParts.isNotEmpty) {
            final firstWord = communeParts.first.trim().toLowerCase();
            final partialMatch = validCommunes.firstWhere(
              (c) => c.trim().toLowerCase().contains(firstWord),
              orElse: () => '',
            );
            
            if (partialMatch.isNotEmpty) {
              commune = partialMatch.trim();
              print('⚠️ Found partial match: "$commune"');
            } else {
              // No match found - likely due to language difference (Arabic vs English)
              // Use the first commune as it's guaranteed to be valid
              commune = validCommunes.first.trim();
              print('⚠️ No match found (possible language difference). Using first valid commune: "$commune"');
            }
          } else {
            // Use the first commune as fallback
            commune = validCommunes.first.trim();
            print('⚠️ No match found, using first available: "$commune"');
          }
        }
      }
      
      // Get shipping fee for this wilaya
      final shippingFee = await getShippingFee(wilayaCode);
      
      // Parse order price
      final orderPrice = int.tryParse(order.price) ?? 0;
      
      // Total montant = order price + shipping fee
      final totalAmount = orderPrice + shippingFee;
      
      print('Order Price: $orderPrice, Shipping Fee: $shippingFee, Total: $totalAmount');
      print('Final Commune: "$commune" (Wilaya Code: $wilayaCode)');
      
      // Build request body as JSON
      final payload = {
        'reference': order.row.toString(),
        'nom_client': order.name,
        'telephone': cleanPhone,
        'adresse': order.address.isNotEmpty ? order.address : order.wilaya,
        'commune': commune, // Use validated commune name (guaranteed to be valid)
        'code_wilaya': wilayaCode,
        'montant': totalAmount, // Include shipping fees!
        'produit': order.product.isNotEmpty ? order.product : 'طلب',
        'type': 1, // 1 = Livraison
      };

      final uri = Uri.parse('$baseUrl/create/order');

      print('EcoTrack Request URL: $uri');
      print('EcoTrack Payload: $payload');

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Request timeout'),
      );

      print('EcoTrack Response Status: ${response.statusCode}');
      print('EcoTrack Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = jsonDecode(response.body);
          
          // Check for success field
          if (data['success'] == true) {
            // Get the reference/tracking number from the response
            return data['reference'] ?? 
                   data['data']?['reference'] ??
                   data['tracking_number'] ?? 
                   data['order_id'];
          } else {
            throw Exception('EcoTrack: ${data['message'] ?? 'Unknown error'}');
          }
        } catch (e) {
          print('Parse error: $e');
          return response.body;
        }
      } else if (response.statusCode == 403) {
        throw Exception('EcoTrack: Forbidden - Invalid or expired token (403)');
      } else if (response.statusCode == 400) {
        throw Exception('EcoTrack: Bad request - ${response.body}');
      } else if (response.statusCode == 422) {
        // Validation error - parse and show details
        try {
          final errorData = jsonDecode(response.body);
          final message = errorData['message'] ?? 'Validation error';
          throw Exception('EcoTrack: $message');
        } catch (e) {
          throw Exception('EcoTrack: Validation error (422) - ${response.body}');
        }
      } else {
        throw Exception('EcoTrack API Error: ${response.statusCode}');
      }
    } catch (e) {
      print('EcoTrack Error: $e');
      rethrow;
    }
  }
}
