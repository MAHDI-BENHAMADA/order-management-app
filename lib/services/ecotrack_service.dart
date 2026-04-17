import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/order.dart';

class EcoTrackService {
  static const String baseUrl = 'https://api.ecotrack.dz/v1';
  static String? _apiToken;

  static void setApiToken(String token) {
    _apiToken = token;
  }

  static Future<String?> createParcel(AppOrder order) async {
    if (_apiToken == null) {
      throw Exception('EcoTrack API Token not set');
    }

    try {
      final address = order.address.isEmpty 
          ? '${order.wilaya} - المركز' 
          : order.address;

      final payload = {
        'client_name': order.name,
        'client_phone': order.phone,
        'wilaya': order.wilaya,
        'commune': order.commune.isNotEmpty ? order.commune : 'المركز',
        'address': address,
        'content': order.product.isNotEmpty ? order.product : 'طلب',
        'amount': order.price.isNotEmpty ? int.tryParse(order.price) ?? 0 : 0,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/shipment/create'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiToken',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['tracking_number'] ?? data['reference_id'] ?? data['id'];
      } else {
        throw Exception('EcoTrack API Error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('EcoTrack Parcel Error: $e');
    }
  }
}
