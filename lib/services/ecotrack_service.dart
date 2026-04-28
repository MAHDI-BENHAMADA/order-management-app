import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/order.dart';
import '../utils/algeria_location_service.dart';

class EcoTrackService {
  static String _baseUrl = 'https://48hr.ecotrack.dz/api/v1'; // Default provider
  static String? _apiToken;

  /// Set the API token for authentication
  static void setApiToken(String token) {
    _apiToken = token;
  }

  /// Set the base URL for the EcoTrack provider (dynamic provider selection)
  /// Example: 'https://areex.ecotrack.dz/api/v1' for Areex provider
  static void setBaseUrl(String url) {
    _baseUrl = url;
    print('✅ EcoTrack Base URL updated to: $_baseUrl');
  }

  /// Get the current base URL
  static String getBaseUrl() => _baseUrl;

  static Future<bool> validateToken() async {
    if (_apiToken == null) {
      throw Exception('EcoTrack API Token not set');
    }

    try {
      final uri = Uri.parse('$_baseUrl/get/wilayas');

      print('Validating EcoTrack Token via: $uri');

      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $_apiToken',
              'Accept': 'application/json',
            },
          )
          .timeout(
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

  // Fetch all active wilayas from EcoTrack API
  static Future<List<Map<String, dynamic>>> getWilayasFromApi() async {
    if (_apiToken == null) {
      throw Exception('EcoTrack API Token not set');
    }

    try {
      final uri = Uri.parse('$_baseUrl/get/wilayas');

      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $_apiToken',
              'Accept': 'application/json',
            },
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Wilayas request timeout'),
          );

      print('EcoTrack Wilayas Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, dynamic>> result = [];

        // Handle response format
        List<dynamic> wilayasList = [];
        if (data is List) {
          wilayasList = data;
        } else if (data is Map && data['wilayas'] is List) {
          wilayasList = data['wilayas'];
        }

        for (var item in wilayasList) {
          if (item is Map) {
            result.add(item as Map<String, dynamic>);
          }
        }

        print('✅ Fetched ${result.length} wilayas from EcoTrack API');
        return result;
      } else {
        print('Failed to get wilayas: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error getting wilayas from API: $e');
      return [];
    }
  }

  // Fetch communes for a specific wilaya by wilaya_id from EcoTrack API with retry logic
  static Future<List<String>> getCommunesFromApi(int wilayaId) async {
    if (_apiToken == null) {
      throw Exception('EcoTrack API Token not set');
    }

    int retries = 0;
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);

    while (retries < maxRetries) {
      try {
        final uri = Uri.parse('$_baseUrl/get/communes?wilaya_id=$wilayaId');

        final response = await http
            .get(
              uri,
              headers: {
                'Authorization': 'Bearer $_apiToken',
                'Content-Type': 'application/json',
              },
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw Exception('Communes request timeout'),
            );

        print('EcoTrack Communes Response Status: ${response.statusCode}');

        // Handle rate limiting with retry
        if (response.statusCode == 429) {
          retries++;
          if (retries < maxRetries) {
            print('⚠️ Rate limited (429), retrying in ${retryDelay.inSeconds}s (attempt $retries/$maxRetries)');
            await Future.delayed(retryDelay);
            continue;
          } else {
            print('❌ Rate limited after $maxRetries attempts for wilaya $wilayaId');
            return [];
          }
        }

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
            print(
              '✅ Parsed ${result.length} communes for wilaya $wilayaId: ${result.take(5).join(", ")}...',
            );
            return result;
          }

          return [];
        } else {
          print('Failed to get communes: ${response.statusCode}');
          return [];
        }
      } catch (e) {
        print('Error getting communes from API: $e');
        return [];
      }
    }

    return [];
  }

  // Get valid communes for a wilaya
  static Future<List<String>> getCommunes(int wilayaCode) async {
    if (_apiToken == null) {
      throw Exception('EcoTrack API Token not set');
    }

    try {
      final uri = Uri.parse('$_baseUrl/get/communes/$wilayaCode');

      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $_apiToken',
              'Content-Type': 'application/json',
            },
          )
          .timeout(
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
          print(
            '✅ Parsed ${result.length} communes: ${result.take(5).join(", ")}...',
          );
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
      final uri = Uri.parse('$_baseUrl/get/fees');

      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $_apiToken',
              'Content-Type': 'application/json',
            },
          )
          .timeout(
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
      final customerName = order.name.trim();
      if (customerName.isEmpty) {
        throw Exception('EcoTrack: Missing customer name');
      }

      final normalizedWilaya = order.wilaya.trim();
      final wilayaCode = AlgeriaLocationService.getWilayaId(normalizedWilaya);
      if (wilayaCode == null) {
        throw Exception(
          'EcoTrack: Invalid wilaya "$normalizedWilaya". Please select a valid wilaya before shipping.',
        );
      }

      final cleanPhone = order.phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanPhone.isEmpty) {
        throw Exception('EcoTrack: Missing phone number');
      }

      final normalizedPhone =
          cleanPhone.startsWith('213') && cleanPhone.length == 12
          ? '0${cleanPhone.substring(3)}'
          : (cleanPhone.length == 9 ? '0$cleanPhone' : cleanPhone);

      if (!RegExp(r'^0[5-7][0-9]{8}$').hasMatch(normalizedPhone)) {
        throw Exception(
          'EcoTrack: Invalid phone number "$normalizedPhone". Use a valid mobile format.',
        );
      }

      final address = order.address.trim();
      if (address.isEmpty) {
        throw Exception('EcoTrack: Missing address');
      }

      final product = order.product.trim().isNotEmpty
          ? order.product.trim()
          : 'طلب';

      final parsedPrice = int.tryParse(
        order.price.trim().isNotEmpty ? order.price.trim() : '0',
      );
      if (parsedPrice == null || parsedPrice < 0) {
        throw Exception('EcoTrack: Invalid price value "${order.price}"');
      }

      String commune = order.commune.trim();
      if (commune.isEmpty) {
        throw Exception(
          'EcoTrack: Missing commune for wilaya "$normalizedWilaya"',
        );
      }

      // Note: Commune should already be validated by home_screen before calling this
      // But we do a final check just in case
      final validCommunes = await getCommunes(wilayaCode);

      if (validCommunes.isNotEmpty) {
        final exactMatch = validCommunes.firstWhere(
          (c) => c.trim().toLowerCase() == commune.toLowerCase(),
          orElse: () => '',
        );

        if (exactMatch.isNotEmpty) {
          commune = exactMatch.trim();
        } else {
          // Commune not found - this shouldn't happen after validation
          // but send it anyway and let EcoTrack provide detailed feedback
          print('⚠️ Warning: Commune "$commune" not in EcoTrack list, sending anyway');
        }
      }

      // Get shipping fee for this wilaya
      final shippingFee = await getShippingFee(wilayaCode);

      // Parse order price
      final orderPrice = parsedPrice;

      // Total montant = order price + shipping fee
      final totalAmount = orderPrice + shippingFee;

      print(
        'Order Price: $orderPrice, Shipping Fee: $shippingFee, Total: $totalAmount',
      );
      print('Final Commune: "$commune" (Wilaya Code: $wilayaCode)');

      // Build request body as JSON
      final payload = {
        'reference': order.row.toString(),
        'nom_client': customerName,
        'telephone': normalizedPhone,
        'adresse': address,
        'commune':
            commune, // Use validated commune name (guaranteed to be valid)
        'code_wilaya': wilayaCode,
        'montant': totalAmount, // Include shipping fees!
        'produit': product,
        'type': 1, // 1 = Livraison
        'stop_desk': order.stopDesk, // 0 = A domicile, 1 = Stop desk
      };

      final uri = Uri.parse('$_baseUrl/create/order');

      print('EcoTrack Request URL: $uri');
      print('EcoTrack Payload: $payload');

      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $_apiToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(
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
          final message = errorData['message']?.toString() ?? 'Validation error';
          final normalized = message.toLowerCase();
          if (order.stopDesk == 1 &&
              (normalized.contains('stop') ||
                  normalized.contains('desk') ||
                  normalized.contains('point relais') ||
                  normalized.contains('relay') ||
                  normalized.contains('stop_desk'))) {
            throw Exception(
              'هذه البلدية لا تدعم Stop desk. اختر A domicile او غيّر البلدية.',
            );
          }
          throw Exception('EcoTrack: $message');
        } catch (e) {
          throw Exception(
            'EcoTrack: Validation error (422) - ${response.body}',
          );
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
