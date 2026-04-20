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
    'الجزائر': 1,
    'وهران': 2,
    'قسنطينة': 3,
    'البليدة': 4,
    'بوفاريك': 5,
    'تلمسان': 6,
    'جيجل': 7,
    'سيدي بلعباس': 8,
    'سطيف': 9,
    'تيارت': 10,
    'تيزي وزو': 11,
    'الجلفة': 12,
    'سعيدة': 13,
    'سكيكدة': 14,
    'سيدي عيسى': 15,
    'الشلف': 16,
    'البيض': 17,
    'عنابة': 18,
    'الأغواط': 19,
    'قالمة': 20,
    'قرقرة': 21,
    'بسكرة': 22,
    'طبرقة': 23,
    'تبسة': 24,
    'برج بوعريريج': 25,
    'عين الدفلى': 26,
    'عين تيموشنت': 27,
    'غرداية': 28,
    'الحمادية': 29,
    'درعة و تافيلالت': 30,
    'الونشريس': 31,
    'المنيعة': 32,
    'الأوراس': 34,
    'الإهقار': 35,
    'نقادي': 36,
    'أوليلي': 38,
    'أدرار': 39,
    'باتنة': 40,
    'بني سويف': 41,
    'بنى هلال': 42,
    'بوسعادة': 43,
    'الشقرة': 44,
    'المسيلة': 45,
    'عين بوسيف': 46,
    'أم البواقي': 47,
    'الواحات': 48,
    'سباتين': 49,
    'إليزي': 51,
    'تمنراست': 52,
    'الطاسيلي': 53,
    'عين قزام': 54,
    'جانت': 55,
    'إنقوسة': 57,
    'جاسي': 58,
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
        return;
      }

      _wilayas.clear();
      _wilayaNameToId.clear();

      for (final wilaya in wilayasData) {
        final wilayaName = wilaya['wilaya_name'] ?? wilaya['nom'] ?? '';
        final wilayaId = wilaya['wilaya_id'] ?? wilaya['id'] ?? 0;

        if (wilayaName.isNotEmpty && wilayaId != 0) {
          final nameStr = wilayaName.toString().trim();
          _wilayas.add(nameStr);
          _wilayaNameToId[nameStr] = wilayaId as int;
        }
      }

      _wilayas.sort();
      print('✅ Loaded ${_wilayas.length} wilayas from EcoTrack API');

      // Step 2: Load communes from LOCAL JSON file (NO API CALLS = NO RATE LIMITING!)
      print('📚 Loading communes from local JSON file...');
      await _loadCommunesFromLocalJson();

      _loaded = true;
      print('✅ AlgeriaLocationService fully loaded');
    } catch (e) {
      print('❌ Error during location data loading: $e');
      _loadFallbackData();
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
          // Find wilaya name by ID
          String? wilayaName;
          for (final entry in _wilayaNameToId.entries) {
            if (entry.value == wilayaId) {
              wilayaName = entry.key;
              break;
            }
          }

          if (wilayaName != null) {
            _wilayaToCommunes.putIfAbsent(wilayaName, () => <String>[]);
            if (!_wilayaToCommunes[wilayaName]!.contains(communeName)) {
              _wilayaToCommunes[wilayaName]!.add(communeName);
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

    // Try exact match first
    if (_wilayaNameToId.containsKey(wilaya)) {
      return _wilayaNameToId[wilaya];
    }

    // Try normalized match
    final normalized = _normalize(wilaya);
    for (final entry in _wilayaNameToId.entries) {
      if (_normalize(entry.key) == normalized) {
        return entry.value;
      }
    }

    return null;
  }

  static List<String> getCommunesForWilaya(String wilaya) {
    if (!_loaded) return const <String>[];

    // Try exact match first
    if (_wilayaToCommunes.containsKey(wilaya)) {
      return List<String>.unmodifiable(_wilayaToCommunes[wilaya] ?? const <String>[]);
    }

    // Try to find by normalized name
    for (final entry in _wilayaToCommunes.entries) {
      if (_normalize(entry.key) == _normalize(wilaya)) {
        return List<String>.unmodifiable(entry.value);
      }
    }

    return const <String>[];
  }

  static String? normalizeWilaya(String value) {
    if (value.trim().isEmpty) return null;

    // Try exact match first
    if (_wilayas.contains(value)) {
      return value;
    }

    // Try normalized match
    final normalized = _normalize(value);
    for (final wilaya in _wilayas) {
      if (_normalize(wilaya) == normalized) {
        return wilaya;
      }
    }

    return null;
  }

  static String? normalizeCommune(String wilaya, String commune) {
    if (commune.trim().isEmpty) return null;

    final normalizedWilaya = normalizeWilaya(wilaya);
    if (normalizedWilaya == null) return null;

    final communes = _wilayaToCommunes[normalizedWilaya] ?? const <String>[];
    
    // Try exact match first
    if (communes.contains(commune)) {
      return commune;
    }

    // Try normalized match
    final normalized = _normalize(commune);
    for (final c in communes) {
      if (_normalize(c) == normalized) {
        return c;
      }
    }

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

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('ـ', '');
  }
}
