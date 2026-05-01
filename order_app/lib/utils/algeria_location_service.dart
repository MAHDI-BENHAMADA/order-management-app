import 'dart:convert';
import 'package:flutter/services.dart';
import '../services/ecotrack_service.dart';

class AlgeriaLocationService {
  static bool _loaded = false;

  static final List<String> _wilayas = <String>[];
  static final Map<String, int> _wilayaNameToId = <String, int>{};
  static final Map<String, List<String>> _wilayaToCommunes =
      <String, List<String>>{};

  // Fallback hardcoded wilayas in case API fails
  // Fallback hardcoded wilayas in case API fails
  static const Map<String, int> _fallbackWilayaCodes = {
    '01. أدرار': 1,
    '02. الشلف': 2,
    '03. الأغواط': 3,
    '04. أم البواقي': 4,
    '05. باتنة': 5,
    '06. بجاية': 6,
    '07. بسكرة': 7,
    '08. بشار': 8,
    '09. البليدة': 9,
    '10. البويرة': 10,
    '11. تمنراست': 11,
    '12. تبسة': 12,
    '13. تلمسان': 13,
    '14. تيارت': 14,
    '15. تيزي وزو': 15,
    '16. الجزائر': 16,
    '17. الجلفة': 17,
    '18. جيجل': 18,
    '19. سطيف': 19,
    '20. سعيدة': 20,
    '21. سكيكدة': 21,
    '22. سيدي بلعباس': 22,
    '23. عنابة': 23,
    '24. قالمة': 24,
    '25. قسنطينة': 25,
    '26. المدية': 26,
    '27. مستغانم': 27,
    '28. المسيلة': 28,
    '29. معسكر': 29,
    '30. ورقلة': 30,
    '31. وهران': 31,
    '32. البيض': 32,
    '33. إليزي': 33,
    '34. برج بوعريريج': 34,
    '35. بومرداس': 35,
    '36. الطارف': 36,
    '37. تندوف': 37,
    '38. تيسمسيلت': 38,
    '39. الوادي': 39,
    '40. خنشلة': 40,
    '41. سوق أهراس': 41,
    '42. تيبازة': 42,
    '43. ميلة': 43,
    '44. عين الدفلى': 44,
    '45. النعامة': 45,
    '46. عين تموشنت': 46,
    '47. غرداية': 47,
    '48. غليزان': 48,
    '49. تميمون': 49,
    '50. برج باجي مختار': 50,
    '51. أولاد جلال': 51,
    '52. بني عباس': 52,
    '53. عين صالح': 53,
    '54. عين قزام': 54,
    '55. تقرت': 55,
    '56. جانت': 56,
    '57. المغير': 57,
    '58. المنيعة': 58,
  };

  static Future<void> ensureLoaded() async {
    if (_loaded) return;

    try {
      // Step 1: Fetch wilayas from EcoTrack API
      print('📍 Loading wilayas from EcoTrack API...');
      final wilayasData = await EcoTrackService.getWilayasFromApi();

      if (wilayasData.isEmpty) {
        print('⚠️ EcoTrack API returned no wilayas, using fallback');
        _loadFallbackData();
        await _loadCommunesFromLocalJson();
        _loaded = true;
        return;
      }

      _wilayas.clear();
      _wilayaNameToId.clear();
      
      // 1. Set official UI names from our Arabic fallback list
      _wilayaNameToId.addAll(_fallbackWilayaCodes);

      final sortedEntries = _fallbackWilayaCodes.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      _wilayas.addAll(sortedEntries.map((e) => e.key));

      // 2. Load wilayas from API response as ALIASES
      // This means if the API returns "Tipaza" with ID 42, we map "Tipaza" -> 42,
      // but the UI only ever displays "42. تيبازة"
      int aliasCount = 0;
      for (final wilaya in wilayasData) {
        final wilayaName = wilaya['wilaya_name'] ?? wilaya['nom'] ?? '';
        final wilayaId = wilaya['wilaya_id'] ?? wilaya['id'] ?? 0;

        if (wilayaName.isNotEmpty && wilayaId != 0) {
          final nameStr = wilayaName.toString().trim();
          if (!_wilayaNameToId.containsKey(nameStr)) {
            _wilayaNameToId[nameStr] = wilayaId as int;
            aliasCount++;
          }
        }
      }

      print('✅ Loaded 58 official Arabic wilayas, plus $aliasCount aliases from API');

      // Step 2: Load communes from LOCAL JSON file (NO API CALLS = NO RATE LIMITING!)
      print('📚 Loading communes from local JSON file...');
      await _loadCommunesFromLocalJson();

      _loaded = true;
      print('✅ AlgeriaLocationService fully loaded');
    } catch (e) {
      print('❌ Error during location data loading: $e');
      _loadFallbackData();
      await _loadCommunesFromLocalJson();
      _loaded = true;
    }
  }

  static Future<void> _loadCommunesFromLocalJson() async {
    try {
      final jsonString = await rootBundle.loadString('communes.json');
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

      _wilayaToCommunes.clear();

      // Parse the communes JSON
      for (final entry in jsonData.entries) {
        final commune = entry.value as Map<String, dynamic>;
        final communeName = commune['nom'] as String?;
        final wilayaId = commune['wilaya_id'] as int?;

        if (communeName != null && communeName.isNotEmpty && wilayaId != null) {
          // Find official Arabic wilaya name by ID
          String? officialWilayaName;
          for (final entry in _fallbackWilayaCodes.entries) {
            if (entry.value == wilayaId) {
              officialWilayaName = entry.key;
              break;
            }
          }

          if (officialWilayaName != null) {
            _wilayaToCommunes.putIfAbsent(officialWilayaName, () => <String>[]);
            if (!_wilayaToCommunes[officialWilayaName]!.contains(communeName)) {
              _wilayaToCommunes[officialWilayaName]!.add(communeName);
            }
          }
        }
      }

      // Sort communes for each wilaya
      for (final communes in _wilayaToCommunes.values) {
        communes.sort();
      }

      final totalCommunes = _wilayaToCommunes.values.fold<int>(
        0,
        (sum, list) => sum + list.length,
      );
      print('✅ Loaded $totalCommunes communes from local JSON');
    } catch (e) {
      print('❌ Error loading communes from JSON: $e');
    }
  }

  static void _loadFallbackData() {
    _wilayas.clear();
    _wilayaNameToId.clear();

    for (final entry in _fallbackWilayaCodes.entries) {
      _wilayas.add(entry.key);
      _wilayaNameToId[entry.key] = entry.value;
    }

    _wilayas.sort();
    _loaded = true;
    print('✅ Using fallback wilayas (${_wilayas.length} total)');
  }

  static List<String> getWilayas() {
    return List<String>.unmodifiable(_wilayas);
  }

  // Get wilaya ID by name (used for EcoTrack API calls)
  static int? getWilayaId(String wilaya) {
    if (!_loaded) return null;

    final trimmed = wilaya.trim();
    if (trimmed.isEmpty) return null;

    // Try to extract ID if it starts with digits (e.g. "16 - Alger" or "16")
    final idMatch = RegExp(r'^(\d+)').firstMatch(trimmed);
    if (idMatch != null) {
      final id = int.tryParse(idMatch.group(1)!);
      if (id != null) {
        // Find wilaya with this ID
        for (final entry in _wilayaNameToId.entries) {
          if (entry.value == id) return id;
        }
      }
    }

    // Try exact match first
    if (_wilayaNameToId.containsKey(trimmed)) {
      return _wilayaNameToId[trimmed];
    }

    // Try normalized match
    final normalized = _normalize(trimmed);
    for (final entry in _wilayaNameToId.entries) {
      if (_normalize(entry.key) == normalized) {
        return entry.value;
      }
    }

    return null;
  }

  static List<String> getCommunesForWilaya(String wilaya) {
    if (!_loaded) return const <String>[];

    final normalizedWilaya = normalizeWilaya(wilaya);
    if (normalizedWilaya == null) return const <String>[];

    // Try exact match first
    if (_wilayaToCommunes.containsKey(normalizedWilaya)) {
      return List<String>.unmodifiable(
        _wilayaToCommunes[normalizedWilaya] ?? const <String>[],
      );
    }

    return const <String>[];
  }

  static String? _getOfficialNameById(int id) {
    for (final entry in _fallbackWilayaCodes.entries) {
      if (entry.value == id) return entry.key;
    }
    return null;
  }

  static String? normalizeWilaya(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    // 1. Numeric ID prefix ("16", "16 - Alger", "16. الجزائر")
    final idMatch = RegExp(r'^(\d+)').firstMatch(trimmed);
    if (idMatch != null) {
      final id = int.tryParse(idMatch.group(1)!);
      if (id != null && id >= 1 && id <= 58) {
        final officialName = _getOfficialNameById(id);
        if (officialName != null) return officialName;
      }
    }

    // 2. Exact match in official Arabic names
    if (_fallbackWilayaCodes.containsKey(trimmed)) return trimmed;

    // 3. Exact match in runtime aliases (from API)
    if (_wilayaNameToId.containsKey(trimmed)) {
      return _getOfficialNameById(_wilayaNameToId[trimmed]!);
    }

    final norm = _normalize(trimmed);

    // 4. Normalized match against runtime aliases
    for (final entry in _wilayaNameToId.entries) {
      if (_normalize(entry.key) == norm) {
        return _getOfficialNameById(entry.value);
      }
    }

    // 5. Exact match in Latin alias table
    if (_latinAliases.containsKey(norm)) {
      return _getOfficialNameById(_latinAliases[norm]!);
    }

    // 6. Fuzzy / contains match against Latin alias table
    for (final entry in _latinAliases.entries) {
      if (_fuzzyContains(norm, entry.key)) {
        return _getOfficialNameById(entry.value);
      }
    }

    // 7. Fuzzy / contains match against official Arabic names
    for (final entry in _fallbackWilayaCodes.entries) {
      final normKey = _normalize(entry.key.replaceFirst(RegExp(r'^\d+\.\s*'), ''));
      if (_fuzzyContains(norm, normKey)) {
        return entry.key;
      }
    }

    return null;
  }

  static String? normalizeCommune(String wilaya, String commune) {
    if (commune.trim().isEmpty) return null;

    final normalizedWilaya = normalizeWilaya(wilaya);
    if (normalizedWilaya == null) return null;

    final communes = _wilayaToCommunes[normalizedWilaya] ?? const <String>[];
    if (communes.isEmpty) return null;

    // 1. Exact match
    if (communes.contains(commune)) return commune;

    final norm = _normalize(commune);

    // 2. Normalized exact match
    for (final c in communes) {
      if (_normalize(c) == norm) return c;
    }

    // 3. Fuzzy / contains match
    for (final c in communes) {
      if (_fuzzyContains(norm, _normalize(c))) return c;
    }

    // 4. Best partial: find commune that shares most tokens
    String? bestMatch;
    int bestScore = 0;
    final inputTokens = norm.split(' ');
    for (final c in communes) {
      final cTokens = _normalize(c).split(' ');
      final shared = inputTokens.where((t) => t.length > 2 && cTokens.contains(t)).length;
      if (shared > bestScore) {
        bestScore = shared;
        bestMatch = c;
      }
    }
    if (bestScore > 0) return bestMatch;

    return null;
  }

  static bool isValidCommuneForWilaya(String wilaya, String commune) {
    final normalizedWilaya = normalizeWilaya(wilaya);
    if (normalizedWilaya == null) return false;

    final normalizedCommune = normalizeCommune(normalizedWilaya, commune);
    if (normalizedCommune == null) return false;

    return (_wilayaToCommunes[normalizedWilaya] ?? const <String>[]).contains(
      normalizedCommune,
    );
  }

  // ---------------------------------------------------------------------------
  // Latin / French aliases → wilaya ID  (covers all 58 wilayas)
  // ---------------------------------------------------------------------------
  static const Map<String, int> _latinAliases = {
    // 01
    'adrar': 1,
    // 02
    'chlef': 2, 'chleff': 2, 'el asnam': 2, 'asnam': 2, 'chelif': 2,
    // 03
    'laghouat': 3, 'aghwat': 3,
    // 04
    'oum el bouaghi': 4, 'oum bouaghi': 4, 'oum el baouaghi': 4,
    // 05
    'batna': 5,
    // 06
    'bejaia': 6, 'bjaia': 6, 'bgayet': 6, 'bgayeth': 6, 'bougie': 6, 'bejaie': 6,
    // 07
    'biskra': 7,
    // 08
    'bechar': 8,
    // 09
    'blida': 9, 'boulaida': 9,
    // 10
    'bouira': 10,
    // 11
    'tamanrasset': 11, 'tamanghasset': 11, 'tamanghast': 11, 'tam': 11,
    // 12
    'tebessa': 12,
    // 13
    'tlemcen': 13, 'tilimsen': 13, 'tlemsan': 13,
    // 14
    'tiaret': 14, 'tihert': 14,
    // 15
    'tizi ouzou': 15, 'tizi-ouzou': 15, 'tizi ouzu': 15, 'to': 15,
    // 16
    'alger': 16, 'algiers': 16, 'algers': 16, 'el djazair': 16, 'djazair': 16, 'algerie': 16,
    // 17
    'djelfa': 17,
    // 18
    'jijel': 18, 'djidjel': 18,
    // 19
    'setif': 19, 'setiff': 19,
    // 20
    'saida': 20,
    // 21
    'skikda': 21, 'philippeville': 21,
    // 22
    'sidi bel abbes': 22, 'sidi bel': 22, 'sba': 22,
    // 23
    'annaba': 23, 'bone': 23,
    // 24
    'guelma': 24,
    // 25
    'constantine': 25, 'qacentina': 25, 'qsentina': 25,
    // 26
    'medea': 26,
    // 27
    'mostaganem': 27, 'mustaganem': 27,
    // 28
    'msila': 28, "m'sila": 28, 'msilla': 28,
    // 29
    'mascara': 29,
    // 30
    'ouargla': 30, 'warqla': 30,
    // 31
    'oran': 31, 'wahran': 31, 'ouahran': 31,
    // 32
    'el bayadh': 32, 'bayadh': 32, 'el bayad': 32,
    // 33
    'illizi': 33,
    // 34
    'bordj bou arreridj': 34, 'bba': 34, 'bordj bouarreridj': 34,
    // 35
    'boumerdes': 35, 'boumerdas': 35,
    // 36
    'el tarf': 36, 'tarf': 36,
    // 37
    'tindouf': 37,
    // 38
    'tissemsilt': 38,
    // 39
    'el oued': 39, 'oued souf': 39, 'souf': 39, 'eloued': 39,
    // 40
    'khenchela': 40,
    // 41
    'souk ahras': 41, 'soukahras': 41,
    // 42
    'tipaza': 42, 'tipasa': 42,
    // 43
    'mila': 43,
    // 44
    'ain defla': 44, 'ain-defla': 44,
    // 45
    'naama': 45,
    // 46
    'ain temouchent': 46, 'ain temucent': 46,
    // 47
    'ghardaia': 47, 'ghardaya': 47,
    // 48
    'relizane': 48, 'rilizane': 48, 'ghilizane': 48,
    // 49
    'timimoun': 49,
    // 50
    'bordj badji mokhtar': 50, 'bbm': 50,
    // 51
    'ouled djellal': 51,
    // 52
    'beni abbes': 52, 'beni-abbes': 52,
    // 53
    'in salah': 53, 'insalah': 53,
    // 54
    'in guezzam': 54,
    // 55
    'touggourt': 55,
    // 56
    'djanet': 56,
    // 57
    'el mghair': 57, 'el meghaier': 57,
    // 58
    'el meniaa': 58, 'el menia': 58,
  };

  // ---------------------------------------------------------------------------
  // Normalize: lower-case, strip accents/diacritics, collapse spaces
  // ---------------------------------------------------------------------------
  static String _normalize(String value) {
    String s = value.trim().toLowerCase();
    // Arabic diacritics
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    // Arabic tatweel
    s = s.replaceAll('\u0640', '');
    // French accents → ASCII
    const Map<String, String> accents = {
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'à': 'a', 'â': 'a', 'ä': 'a',
      'ù': 'u', 'û': 'u', 'ü': 'u',
      'î': 'i', 'ï': 'i',
      'ô': 'o', 'ö': 'o',
      'ç': 'c',
    };
    accents.forEach((k, v) { s = s.replaceAll(k, v); });
    // Collapse whitespace
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  // ---------------------------------------------------------------------------
  // Fuzzy helpers
  // ---------------------------------------------------------------------------

  /// Returns true if [a] and [b] are close enough (one contains the other, ≥4 chars).
  static bool _fuzzyContains(String a, String b) {
    if (a.length < 4 || b.length < 4) return false;
    return a.contains(b) || b.contains(a);
  }
}
