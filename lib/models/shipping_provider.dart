/// Represents different shipping provider integrations and their configurations
enum ShippingProvider {
  // EcoTrack Integration Providers
  e48hr('48hr', '48Hr Livraison', 'https://48hr.ecotrack.dz/', 'ecotrack'),
  anderson('anderson', 'Anderson Delivery', 'https://anderson.ecotrack.dz/', 'ecotrack'),
  areex('areex', 'Areex', 'https://areex.ecotrack.dz/', 'ecotrack'),
  baConsult('baconsult', 'BA Consult', 'https://bacexpress.ecotrack.dz/', 'ecotrack'),
  conexlog('conexlog', 'Conexlog', 'https://app.conexlog-dz.com/', 'ecotrack'),
  coyoteExpress('coyoteexpress', 'Coyote express', 'https://coyoteexpressdz.ecotrack.dz/', 'ecotrack'),
  dhd('dhd', 'DHD', 'https://dhd.ecotrack.dz/', 'ecotrack'),
  distazero('distazero', 'Distazero', 'https://distazero.ecotrack.dz/', 'ecotrack'),
  fretdirect('fretdirect', 'FRET.Direct', 'https://fret.ecotrack.dz/', 'ecotrack'),
  golivri('golivri', 'GOLIVRI', 'https://golivri.ecotrack.dz/', 'ecotrack'),
  monoHub('monohub', 'Mono Hub', 'https://mono.ecotrack.dz/', 'ecotrack'),
  msmGo('msmgo', 'MSM Go', 'https://msmgo.ecotrack.dz', 'ecotrack'),
  negmarExpress('negmarexpress', 'Negmar Express', 'https://negmar.ecotrack.dz/', 'ecotrack'),
  packers('packers', 'Packers', 'https://packers.ecotrack.dz/', 'ecotrack'),
  prest('prest', 'Prest', 'https://prest.ecotrack.dz/', 'ecotrack'),
  rbLivraison('rblivraison', 'RB Livraison', 'https://rblivraison.ecotrack.dz/', 'ecotrack'),
  rexLivraison('rexlivraison', 'Rex Livraison', 'https://rex.ecotrack.dz/', 'ecotrack'),
  rocketDelivery('rocketdelivery', 'Rocket Delivery', 'https://rocket.ecotrack.dz/', 'ecotrack'),
  salvaDelivery('salvadelivery', 'Salva Delivery', 'https://salvadelivery.ecotrack.dz/', 'ecotrack'),
  speedDelivery('speeddelivery', 'Speed Delivery', 'https://speeddelivery.ecotrack.dz/', 'ecotrack'),
  tslExpress('tslexpress', 'TSL Express', 'https://tsl.ecotrack.dz/', 'ecotrack'),
  worldexpress('worldexpress', 'WorldExpress', 'https://worldexpress.ecotrack.dz/', 'ecotrack'),

  // Yalidine Integration Providers
  yalidine('yalidine', 'Yalidine', 'https://api.yalidine.app', 'yalidine'),

  // Yalitec Integration Providers
  yalitec('yalitec', 'Yalitec', 'https://api.yalitec.me', 'yalitec'),

  // Procolis Integration Providers
  zrExpress('zrexpress', 'ZR Express', 'https://zrexpress.com', 'procolis');

  final String id;
  final String displayName;
  final String apiDomain;
  final String integrationType;

  const ShippingProvider(this.id, this.displayName, this.apiDomain, this.integrationType);

  /// Get the API base URL (with /api/v1 or appropriate endpoint for EcoTrack)
  String getBaseUrl() {
    if (integrationType == 'ecotrack') {
      // EcoTrack providers use /api/v1 endpoint
      if (apiDomain.endsWith('/')) {
        return '${apiDomain}api/v1';
      } else {
        return '${apiDomain}/api/v1';
      }
    }
    // Other providers use their base URL as-is
    return apiDomain;
  }

  /// Parse provider from string ID
  static ShippingProvider fromId(String id) {
    try {
      return ShippingProvider.values.firstWhere(
        (provider) => provider.id.toLowerCase() == id.toLowerCase(),
      );
    } catch (e) {
      // Default to 48hr if not found
      return ShippingProvider.e48hr;
    }
  }

  /// Get all providers by integration type
  static List<ShippingProvider> byIntegration(String integrationType) {
    return ShippingProvider.values
        .where((p) => p.integrationType == integrationType)
        .toList();
  }

  /// Get all EcoTrack providers
  static List<ShippingProvider> get ecotrackProviders =>
      byIntegration('ecotrack');

  /// Get all Yalidine-based providers
  static List<ShippingProvider> get yalidineLikeProviders =>
      byIntegration('yalidine');

  /// Get all Yalitec-based providers
  static List<ShippingProvider> get yalitecProviders =>
      byIntegration('yalitec');

  /// Get all Procolis-based providers
  static List<ShippingProvider> get procolisProviders =>
      byIntegration('procolis');

  /// Get all unique integration types
  static List<String> get integrationTypes {
    final types = <String>{};
    for (var provider in ShippingProvider.values) {
      types.add(provider.integrationType);
    }
    return types.toList();
  }
}
