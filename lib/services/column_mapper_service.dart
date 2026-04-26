/// Maps Google Sheet column headers to semantic field keys dynamically.
/// Supports Arabic, French, and English column names.
class ColumnMapperService {
  // ---------------------------------------------------------------------------
  // Keyword lists for each semantic field (lower-case, no accents)
  // ---------------------------------------------------------------------------

  static const _nameKeywords = [
    'nom', 'name', 'full name', 'nom complet', 'client',
    'اسم', 'الاسم', 'nom client', 'customer', 'fullname',
  ];

  static const _firstNameKeywords = [
    'prenom', 'prénom', 'first name', 'firstname', 'given name',
  ];

  static const _phoneKeywords = [
    'tel', 'telephone', 'téléphone', 'phone', 'mobile', 'gsm',
    'هاتف', 'الهاتف', 'رقم', 'numero', 'numéro', 'number', 'phone number',
    'portable', 'contact',
  ];

  static const _wilayaKeywords = [
    'wilaya', 'ولاية', 'province', 'region', 'région', 'governorate',
    'wilaya_id', 'code wilaya', 'departement', 'département',
  ];

  static const _communeKeywords = [
    'commune', 'بلدية', 'city', 'ville', 'municipality', 'localite',
    'localité', 'داira', 'daira', 'دائرة', 'town', 'district',
  ];

  static const _statusKeywords = [
    'status', 'statut', 'etat', 'état', 'حالة', 'confirmation',
    'confirmed', 'order status', 'livraison', 'delivery status',
    'situation', 'رسالة',
  ];

  static const _dateKeywords = [
    'date', 'تاريخ', 'order date', 'created', 'created at',
    'date commande', 'date order',
  ];

  static const _addressKeywords = [
    'adresse', 'address', 'عنوان', 'العنوان', 'detailed address',
    'adresse detaillee', 'adresse détaillée', 'full address',
  ];

  static const _productKeywords = [
    'produit', 'product', 'article', 'منتج', 'المنتج', 'item',
    'designation', 'désignation', 'goods',
  ];

  static const _priceKeywords = [
    'prix', 'price', 'montant', 'amount', 'سعر', 'السعر', 'cost',
    'tarif', 'total', 'valeur', 'cod', 'cash',
  ];

  static const _trackingKeywords = [
    'tracking', 'suivi', 'barcode', 'code suivi', 'numero suivi',
    'numéro suivi', 'reference', 'référence', 'رقم تتبع', 'تتبع',
    'tracking number', 'trackingNumber',
  ];

  static const _timeKeywords = [
    'time', 'heure', 'وقت', 'hour', 'timestamp',
  ];

  // ---------------------------------------------------------------------------
  // Normalization helper
  // ---------------------------------------------------------------------------

  static String _normalize(String s) {
    // Lower-case
    String result = s.toLowerCase().trim();
    // Remove Arabic diacritics (harakat)
    result = result.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    // Normalise common French accents to ASCII
    const accents = {
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'à': 'a', 'â': 'a', 'ä': 'a',
      'ù': 'u', 'û': 'u', 'ü': 'u',
      'î': 'i', 'ï': 'i',
      'ô': 'o', 'ö': 'o',
      'ç': 'c',
    };
    accents.forEach((k, v) => result = result.replaceAll(k, v));
    // Collapse multiple spaces
    result = result.replaceAll(RegExp(r'\s+'), ' ');
    return result;
  }

  // ---------------------------------------------------------------------------
  // Score-based single-field matcher
  // ---------------------------------------------------------------------------

  static double _score(String normalizedHeader, List<String> keywords) {
    for (final kw in keywords) {
      if (normalizedHeader == kw) return 2.0; // exact match
      if (normalizedHeader.contains(kw) || kw.contains(normalizedHeader)) {
        return 1.0; // partial match
      }
    }
    return 0.0;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Takes a list of raw header strings (in column order A, B, C…)
  /// and returns a map from column letter → semantic field key.
  ///
  /// Possible field keys: 'name', 'firstName', 'phone', 'wilaya', 'commune',
  ///   'status', 'date', 'address', 'product', 'price', 'tracking', 'time', null.
  static Map<String, String?> mapHeaders(List<String> headers) {
    final bool hasPrenom = _headerListContains(headers, _firstNameKeywords);

    // Each entry: [column letter, header, normalised header]
    final cols = <Map<String, String>>[];
    for (int i = 0; i < headers.length; i++) {
      cols.add({
        'letter': _columnLetter(i),
        'raw': headers[i],
        'norm': _normalize(headers[i]),
      });
    }

    // Ordered list of (fieldKey, keywordList, allowMultiple)
    // We resolve in priority order, marking columns as used.
    final fields = <Map<String, dynamic>>[
      {'key': 'date',      'kw': _dateKeywords},
      {'key': 'time',      'kw': _timeKeywords},
      {'key': 'firstName', 'kw': _firstNameKeywords, 'skip': !hasPrenom},
      {'key': 'name',      'kw': _nameKeywords},
      {'key': 'wilaya',    'kw': _wilayaKeywords},
      {'key': 'phone',     'kw': _phoneKeywords},
      {'key': 'status',    'kw': _statusKeywords},
      {'key': 'commune',   'kw': _communeKeywords},
      {'key': 'address',   'kw': _addressKeywords},
      {'key': 'product',   'kw': _productKeywords},
      {'key': 'price',     'kw': _priceKeywords},
      {'key': 'tracking',  'kw': _trackingKeywords},
    ];

    final Map<String, String?> result = {};
    final usedLetters = <String>{};

    // Initialise all columns to null
    for (final col in cols) {
      result[col['letter']!] = null;
    }

    for (final field in fields) {
      if (field['skip'] == true) continue;

      final String fieldKey = field['key'] as String;
      final List<String> kw = field['kw'] as List<String>;

      String? bestLetter;
      double bestScore = 0.0;

      for (final col in cols) {
        final letter = col['letter']!;
        if (usedLetters.contains(letter)) continue;

        final s = _score(col['norm']!, kw);
        if (s > bestScore) {
          bestScore = s;
          bestLetter = letter;
        }
      }

      if (bestLetter != null && bestScore > 0) {
        result[bestLetter] = fieldKey;
        usedLetters.add(bestLetter);
      }
    }

    return result;
  }

  /// Convenience: given rows (including header row at index 0) and the mapping,
  /// converts a data row into a field→value Map ready for AppOrder.fromJson.
  static Map<String, dynamic> rowToOrderMap({
    required List<dynamic> dataRow,
    required Map<String, String?> columnMap,
    required int sheetRowNumber,
    required Map<String, String?> columnMapping, // same as columnMap, for clarity
  }) {
    final result = <String, dynamic>{
      'row': sheetRowNumber,
      'date': '',
      'time': '',
      'name': '',
      'wilaya': '',
      'phone': '',
      'status': 'جديد',
      'commune': '',
      'address': '',
      'product': '',
      'price': '',
      'trackingNumber': null,
    };

    columnMap.forEach((letter, fieldKey) {
      if (fieldKey == null) return;
      final colIndex = _letterToIndex(letter);
      if (colIndex >= dataRow.length) return;
      final value = dataRow[colIndex].toString().trim();

      switch (fieldKey) {
        case 'name':
          if (result['name'].isEmpty) result['name'] = value;
          break;
        case 'firstName':
          // Prepend firstName to name (will be combined later if both exist)
          result['firstName'] = value;
          break;
        case 'date':
          result['date'] = value;
          break;
        case 'time':
          result['time'] = value;
          break;
        case 'phone':
          result['phone'] = value;
          break;
        case 'wilaya':
          result['wilaya'] = value;
          break;
        case 'commune':
          result['commune'] = value;
          break;
        case 'status':
          result['status'] = value.isNotEmpty ? value : 'جديد';
          break;
        case 'address':
          result['address'] = value;
          break;
        case 'product':
          result['product'] = value;
          break;
        case 'price':
          result['price'] = value;
          break;
        case 'tracking':
          result['trackingNumber'] = value.isNotEmpty ? value : null;
          break;
      }
    });

    // Combine firstName + name if both exist
    final firstName = result.remove('firstName') as String? ?? '';
    if (firstName.isNotEmpty && result['name'] != null) {
      result['name'] = '$firstName ${result['name']}'.trim();
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static bool _headerListContains(List<String> headers, List<String> keywords) {
    for (final h in headers) {
      final norm = _normalize(h);
      if (keywords.any((kw) => norm == kw || norm.contains(kw))) return true;
    }
    return false;
  }

  /// Convert 0-based index to Excel-style column letter (A, B, … Z, AA, …)
  static String _columnLetter(int index) {
    String result = '';
    int n = index;
    do {
      result = String.fromCharCode(65 + (n % 26)) + result;
      n = (n ~/ 26) - 1;
    } while (n >= 0);
    return result;
  }

  /// Convert Excel column letter back to 0-based index
  static int _letterToIndex(String letter) {
    int index = 0;
    for (int i = 0; i < letter.length; i++) {
      index = index * 26 + (letter.codeUnitAt(i) - 64);
    }
    return index - 1;
  }
}
