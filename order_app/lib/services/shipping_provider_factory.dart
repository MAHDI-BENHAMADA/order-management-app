import 'package:shared_preferences/shared_preferences.dart';
import '../models/shipping_provider.dart';
import '../models/order.dart';
import 'ecotrack_service.dart';
import 'yalidine_service.dart';
import 'yalitec_service.dart';
import 'procolis_service.dart';

/// Factory for managing shipping provider services
/// Handles service initialization and routing based on selected provider
class ShippingProviderFactory {
  static ShippingProvider? _selectedProvider;
  static SharedPreferences? _prefs;

  /// Initialize the factory with SharedPreferences
  static Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    final providerId = _prefs?.getString('selected_provider') ?? '48hr';
    _selectedProvider = ShippingProvider.fromId(providerId);
    print('✅ ShippingProviderFactory initialized with provider: ${_selectedProvider?.displayName}');
  }

  /// Set the selected provider (updates both memory and persistent storage)
  static Future<void> setSelectedProvider(ShippingProvider provider) async {
    _selectedProvider = provider;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString('selected_provider', provider.id);
    print('✅ Selected provider changed to: ${provider.displayName}');
  }

  /// Get the currently selected provider
  static ShippingProvider getSelectedProvider() {
    _selectedProvider ??= ShippingProvider.e48hr;
    return _selectedProvider!;
  }

  /// Initialize the service for the selected provider with the given API token
  static void initializeServiceForProvider(
    ShippingProvider provider,
    String apiToken,
  ) {
    switch (provider.integrationType) {
      case 'ecotrack':
        EcoTrackService.setBaseUrl(provider.getBaseUrl());
        EcoTrackService.setApiToken(apiToken);
        print('✅ EcoTrackService initialized for provider: ${provider.displayName}');
        break;

      case 'yalidine':
        YalidineService.setApiToken(apiToken);
        print('✅ YalidineService initialized for provider: ${provider.displayName}');
        break;

      case 'yalitec':
        YalitecService.setApiToken(apiToken);
        print('✅ YalitecService initialized for provider: ${provider.displayName}');
        break;

      case 'procolis':
        ProcolisService.setApiToken(apiToken);
        print('✅ ProcolisService initialized for provider: ${provider.displayName}');
        break;

      default:
        throw Exception('Unknown provider integration type: ${provider.integrationType}');
    }
  }

  /// Create a shipment using the currently selected provider
  /// This is the main entry point for shipping orders
  static Future<String?> createShipmentWithSelectedProvider(
    AppOrder order,
    String apiToken,
  ) async {
    final provider = getSelectedProvider();
    
    // Ensure the service is initialized for this provider
    initializeServiceForProvider(provider, apiToken);

    print('📦 Creating shipment with ${provider.displayName} for order: ${order.name}');

    try {
      switch (provider.integrationType) {
        case 'ecotrack':
          return await EcoTrackService.createParcel(order);

        case 'yalidine':
          return await YalidineService.createShipment(order);

        case 'yalitec':
          return await YalitecService.createShipment(order);

        case 'procolis':
          return await ProcolisService.createShipment(order);

        default:
          throw Exception('Unknown provider integration type: ${provider.integrationType}');
      }
    } catch (e) {
      print('❌ Shipment creation failed with ${provider.displayName}: $e');
      rethrow;
    }
  }

  /// Get all providers grouped by integration type
  static Map<String, List<ShippingProvider>> getProvidersByIntegration() {
    final grouped = <String, List<ShippingProvider>>{};
    
    for (final provider in ShippingProvider.values) {
      if (!grouped.containsKey(provider.integrationType)) {
        grouped[provider.integrationType] = [];
      }
      grouped[provider.integrationType]!.add(provider);
    }
    
    return grouped;
  }

  /// Get a list of all providers sorted by integration type
  static List<ShippingProvider> getAllProviders() {
    return ShippingProvider.values;
  }

  /// Get providers by specific integration type
  static List<ShippingProvider> getProvidersByType(String integrationType) {
    return ShippingProvider.values
        .where((p) => p.integrationType == integrationType)
        .toList();
  }
}
