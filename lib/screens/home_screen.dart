import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import '../models/order.dart';
import '../widgets/order_card.dart';
import '../utils/algeria_location_service.dart';
import '../utils/google_auth_service.dart';
import '../services/yalidine_service.dart';
import '../services/ecotrack_service.dart';
import 'setup_screen.dart';

class _ShippingReadiness {
  final Map<String, String> normalizedValues;
  final Set<String> blockingFields;

  const _ShippingReadiness({
    required this.normalizedValues,
    required this.blockingFields,
  });

  bool get isReady => blockingFields.isEmpty;
}

class HomeScreen extends StatefulWidget {
  final String spreadsheetId;

  const HomeScreen({super.key, required this.spreadsheetId});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _locationDataReady = false;
  final Set<int> _shippingRowsInProgress = <int>{};
  List<AppOrder> allOrders = [];
  bool isLoading = true;
  String? filterStatus; // null = show all
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    filterStatus = null;
    _searchController.addListener(() {
      final nextQuery = _searchController.text.trim();
      if (nextQuery == _searchQuery) return;
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        setState(() {
          _searchQuery = nextQuery;
        });
      });
    });
    _loadLocationData();
    fetchData();
  }

  Future<void> _loadLocationData() async {
    try {
      // Load EcoTrack token from SharedPreferences first
      final prefs = await SharedPreferences.getInstance();
      final ecotrackToken = prefs.getString('ecotrack_token');

      if (ecotrackToken != null && ecotrackToken.isNotEmpty) {
        EcoTrackService.setApiToken(ecotrackToken);
      }

      await AlgeriaLocationService.ensureLoaded();
      if (!mounted) return;
      setState(() {
        _locationDataReady = true;
      });
    } catch (e) {
      print('Error loading location data: $e');
      if (!mounted) return;
      setState(() {
        _locationDataReady = false;
      });
    }
  }

  Future<void> fetchData() async {
    setState(() => isLoading = true);
    try {
      final api = await GoogleAuthService.getSheetsApi();
      if (api == null) {
        _showError('خطأ: لم يتم تسجيل الدخول بصلاحيات كافية.');
        await _logout();
        return;
      }

      // Read columns A to K.
      final response = await api.spreadsheets.values.get(
        widget.spreadsheetId,
        'A:K',
      );
      final rows = response.values ?? [];

      List<dynamic> parsedData = [];
      for (int i = 1; i < rows.length; i++) {
        // Start at 1 to skip headers
        var r = rows[i];
        // Ensure the row has enough columns (up to name at [2])
        if (r.length >= 3 && r[2].toString().isNotEmpty) {
          parsedData.add({
            'row': i + 1, // original sheet row number
            'date': r.isNotEmpty ? r[0] : "",
            'time': r.length > 1 ? r[1] : "",
            'name': r.length > 2 ? r[2] : "",
            'wilaya': r.length > 3 ? r[3] : "",
            'phone': r.length > 4 ? r[4] : "",
            'status': r.length > 5 ? r[5] : "جديد",
            'commune': r.length > 6 ? r[6] : "",
            'address': r.length > 7 ? r[7] : "",
            'product': r.length > 8 ? r[8] : "",
            'price': r.length > 9 ? r[9] : "",
            'trackingNumber': r.length > 10
                ? (r[10].toString().isEmpty ? null : r[10].toString())
                : null,
          });
        }
      }

      setState(() {
        allOrders = AppOrder.processRawData(parsedData);
      });
    } catch (e) {
      _showError('تعذر جلب البيانات: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _logout() async {
    await GoogleAuthService.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('spreadsheetId');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SetupScreen()),
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Get filtered orders based on current filter
  List<AppOrder> _getFilteredOrders() {
    Iterable<AppOrder> filtered = allOrders;

    if (filterStatus != null) {
      filtered = filtered.where((o) => o.status == filterStatus);
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((o) {
        final tracking = o.trackingNumber?.toLowerCase() ?? '';
        return o.name.toLowerCase().contains(query) ||
            o.phone.contains(query) ||
            o.wilaya.toLowerCase().contains(query) ||
            o.commune.toLowerCase().contains(query) ||
            tracking.contains(query);
      });
    }

    return filtered.toList(growable: false);
  }

  Map<String, int> _buildStatusCounts() {
    final counts = <String, int>{};
    for (final order in allOrders) {
      counts[order.status] = (counts[order.status] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _updateOrderStatus(AppOrder order, String newStatus) async {
    final oldStatus = order.status;
    setState(() {
      order.status = newStatus;
    });

    if (newStatus == 'uploaded') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جاري النقل والرفع...'),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }

    try {
      final api = await GoogleAuthService.getSheetsApi();
      if (api == null) throw Exception('API Call failed, not logged in.');

      final range = 'F${order.row}'; // Column F holds the status
      final valueRange = sheets.ValueRange(
        values: [
          [newStatus],
        ],
      );

      await api.spreadsheets.values.update(
        valueRange,
        widget.spreadsheetId,
        range,
        valueInputOption: 'USER_ENTERED',
      );
    } catch (e) {
      // Revert if API fails
      setState(() {
        order.status = oldStatus;
      });
      _showError('خطأ أثناء التحديث! تم التراجع عن التغيير.');
    }
  }

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('213') && digits.length == 12) {
      return '0${digits.substring(3)}';
    }
    if (digits.length == 9 && RegExp(r'^[567]').hasMatch(digits)) {
      return '0$digits';
    }
    return digits;
  }

  bool _isValidAlgerianPhone(String phone) {
    final normalized = _normalizePhone(phone);
    return RegExp(r'^0[5-7][0-9]{8}$').hasMatch(normalized);
  }

  String _fieldLabel(String key) {
    switch (key) {
      case 'name':
        return 'الاسم';
      case 'phone':
        return 'الهاتف';
      case 'wilaya':
        return 'الولاية';
      case 'commune':
        return 'البلدية';
      case 'address':
        return 'العنوان';
      case 'product':
        return 'المنتج';
      case 'price':
        return 'السعر';
      default:
        return key;
    }
  }

  _ShippingReadiness _buildShippingReadiness(
    AppOrder order, {
    required bool forEcoTrack,
  }) {
    final normalized = <String, String>{
      'name': order.name.trim(),
      'phone': _normalizePhone(order.phone),
      'wilaya': order.wilaya.trim(),
      'commune': order.commune.trim(),
      'address': order.address.trim(),
      'product': order.product.trim().isNotEmpty ? order.product.trim() : 'طلب',
      'price': order.price.trim().isNotEmpty ? order.price.trim() : '0',
    };

    if (_locationDataReady) {
      final normalizedWilaya = AlgeriaLocationService.normalizeWilaya(
        normalized['wilaya']!,
      );
      if (normalizedWilaya != null) {
        normalized['wilaya'] = normalizedWilaya;
      }

      if (normalized['commune']!.isEmpty && normalized['wilaya']!.isNotEmpty) {
        final communes = AlgeriaLocationService.getCommunesForWilaya(
          normalized['wilaya']!,
        );
        if (communes.isNotEmpty) {
          normalized['commune'] = communes.first;
        }
      }

      if (normalized['wilaya']!.isNotEmpty &&
          normalized['commune']!.isNotEmpty) {
        final normalizedCommune = AlgeriaLocationService.normalizeCommune(
          normalized['wilaya']!,
          normalized['commune']!,
        );
        if (normalizedCommune != null) {
          normalized['commune'] = normalizedCommune;
        }
      }
    }

    if (normalized['address']!.isEmpty &&
        normalized['wilaya']!.isNotEmpty &&
        normalized['commune']!.isNotEmpty) {
      normalized['address'] =
          '${normalized['commune']!} - ${normalized['wilaya']!}';
    }

    final blocking = <String>{};

    for (final field in [
      'name',
      'phone',
      'wilaya',
      'commune',
      'address',
      'product',
      'price',
    ]) {
      if (normalized[field]!.trim().isEmpty) {
        blocking.add(field);
      }
    }

    if (!_isValidAlgerianPhone(normalized['phone']!)) {
      blocking.add('phone');
    }

    if (_locationDataReady &&
        AlgeriaLocationService.normalizeWilaya(normalized['wilaya']!) == null) {
      print(
        '❌ Wilaya validation failed for: "${normalized['wilaya']!}" | LocationDataReady: $_locationDataReady',
      );
      blocking.add('wilaya');
    } else if (_locationDataReady) {
      final normalizedWilaya =
          AlgeriaLocationService.normalizeWilaya(normalized['wilaya']!);
      print(
        '✅ Wilaya normalized: "${normalized['wilaya']!}" → "$normalizedWilaya"',
      );
    }

    if (_locationDataReady &&
        normalized['wilaya']!.isNotEmpty &&
        normalized['commune']!.isNotEmpty) {
      // Only validate commune if we have communes loaded for this wilaya
      final communesForWilaya = AlgeriaLocationService.getCommunesForWilaya(
        normalized['wilaya']!,
      );
      
      if (communesForWilaya.isNotEmpty &&
          !AlgeriaLocationService.isValidCommuneForWilaya(
            normalized['wilaya']!,
            normalized['commune']!,
          )) {
        // Only block if communes were loaded but this one doesn't match
        blocking.add('commune');
      } else if (communesForWilaya.isEmpty) {
        // Communes didn't load (rate limit), but we allow manual entry
        print('⚠️ Communes not loaded for wilaya, allowing manual entry');
      }
    }

    if (forEcoTrack &&
        normalized['wilaya']!.isNotEmpty) {
      // Check if wilaya has a valid code for EcoTrack
      final wilayaCode = AlgeriaLocationService.getWilayaId(normalized['wilaya']!);
      if (wilayaCode == null) {
        blocking.add('wilaya');
      }
    }

    final parsedPrice = int.tryParse(normalized['price']!);
    if (parsedPrice == null || parsedPrice < 0) {
      blocking.add('price');
    }

    return _ShippingReadiness(
      normalizedValues: normalized,
      blockingFields: blocking,
    );
  }

  bool _hasNormalizedChanges(AppOrder order, Map<String, String> values) {
    return order.name.trim() != values['name'] ||
        order.phone.trim() != values['phone'] ||
        order.wilaya.trim() != values['wilaya'] ||
        order.commune.trim() != values['commune'] ||
        order.address.trim() != values['address'] ||
        order.product.trim() != values['product'] ||
        order.price.trim() != values['price'];
  }

  Future<bool> _saveNormalizedValues(
    AppOrder order,
    Map<String, String> values, {
    bool showSuccessMessage = false,
  }) {
    return _updateOrderFields(
      order,
      name: values['name']!,
      phone: values['phone']!,
      wilaya: values['wilaya']!,
      commune: values['commune']!,
      address: values['address']!,
      product: values['product']!,
      price: values['price']!,
      showSuccessMessage: showSuccessMessage,
    );
  }

  Future<bool> _ensureReadyForShipping(
    AppOrder order, {
    required bool forEcoTrack,
  }) async {
    final readiness = _buildShippingReadiness(order, forEcoTrack: forEcoTrack);

    if (readiness.isReady) {
      if (_hasNormalizedChanges(order, readiness.normalizedValues)) {
        return _saveNormalizedValues(order, readiness.normalizedValues);
      }
      return true;
    }

    final completed = await _showOrderFormDialog(
      order,
      title: 'أكمل البيانات قبل الشحن',
      saveLabel: 'حفظ ومتابعة',
      visibleFields: readiness.blockingFields,
      requiredFields: readiness.blockingFields,
      initialValues: readiness.normalizedValues,
      showSuccessMessage: false,
    );

    if (!completed) return false;

    final secondCheck = _buildShippingReadiness(
      order,
      forEcoTrack: forEcoTrack,
    );
    if (!secondCheck.isReady) {
      final missing = secondCheck.blockingFields.map(_fieldLabel).join('، ');
      _showError('لا يمكن الشحن قبل إكمال: $missing');
      return false;
    }

    if (_hasNormalizedChanges(order, secondCheck.normalizedValues)) {
      return _saveNormalizedValues(order, secondCheck.normalizedValues);
    }

    return true;
  }

  Future<bool> _updateOrderFields(
    AppOrder order, {
    required String name,
    required String phone,
    required String wilaya,
    required String commune,
    required String address,
    required String product,
    required String price,
    bool showSuccessMessage = true,
  }) async {
    try {
      final api = await GoogleAuthService.getSheetsApi();
      if (api == null) throw Exception('API Call failed, not logged in.');

      final batchUpdate = sheets.BatchUpdateValuesRequest(
        valueInputOption: 'USER_ENTERED',
        data: [
          sheets.ValueRange(
            range: 'C${order.row}',
            values: [
              [name],
            ],
          ),
          sheets.ValueRange(
            range: 'D${order.row}',
            values: [
              [wilaya],
            ],
          ),
          sheets.ValueRange(
            range: 'E${order.row}',
            values: [
              [phone],
            ],
          ),
          sheets.ValueRange(
            range: 'G${order.row}',
            values: [
              [commune],
            ],
          ),
          sheets.ValueRange(
            range: 'H${order.row}',
            values: [
              [address],
            ],
          ),
          sheets.ValueRange(
            range: 'I${order.row}',
            values: [
              [product],
            ],
          ),
          sheets.ValueRange(
            range: 'J${order.row}',
            values: [
              [price],
            ],
          ),
        ],
      );

      await api.spreadsheets.values.batchUpdate(
        batchUpdate,
        widget.spreadsheetId,
      );

      setState(() {
        order.name = name;
        order.phone = phone;
        order.wilaya = wilaya;
        order.commune = commune;
        order.address = address;
        order.product = product;
        order.price = price;
      });

      if (mounted && showSuccessMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ التعديلات بنجاح!'),
            duration: Duration(seconds: 1),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }

      return true;
    } catch (e) {
      _showError('خطأ أثناء حفظ التعديلات: $e');
      return false;
    }
  }

  Future<bool> _showEditDialog(AppOrder order) {
    return _showOrderFormDialog(
      order,
      title: 'تعديل الطلب',
      saveLabel: 'حفظ',
      showSuccessMessage: true,
    );
  }

  Future<bool> _showOrderFormDialog(
    AppOrder order, {
    required String title,
    required String saveLabel,
    Set<String>? visibleFields,
    Set<String>? requiredFields,
    Map<String, String>? initialValues,
    bool showSuccessMessage = true,
  }) async {
    final values =
        initialValues ??
        <String, String>{
          'name': order.name,
          'phone': order.phone,
          'wilaya': order.wilaya,
          'commune': order.commune,
          'address': order.address,
          'product': order.product,
          'price': order.price,
        };

    final nameController = TextEditingController(text: values['name'] ?? '');
    final phoneController = TextEditingController(text: values['phone'] ?? '');
    final addressController = TextEditingController(
      text: values['address'] ?? '',
    );
    final productController = TextEditingController(
      text: values['product'] ?? '',
    );
    final priceController = TextEditingController(text: values['price'] ?? '');
    final communeController = TextEditingController(
      text: values['commune'] ?? '',
    );
    final wilayaController = TextEditingController(
      text: values['wilaya'] ?? '',
    );

    String selectedWilaya = wilayaController.text.trim();
    if (_locationDataReady) {
      selectedWilaya =
          AlgeriaLocationService.normalizeWilaya(selectedWilaya) ??
          selectedWilaya;
      wilayaController.text = selectedWilaya;

      final normalizedCommune = AlgeriaLocationService.normalizeCommune(
        selectedWilaya,
        communeController.text,
      );
      if (normalizedCommune != null) {
        communeController.text = normalizedCommune;
      }
    }

    bool showField(String key) {
      return visibleFields == null || visibleFields.contains(key);
    }

    final needed = requiredFields ?? <String>{};

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final wilayas = _locationDataReady
                ? AlgeriaLocationService.getWilayas()
                : const <String>[];
            final communes = _locationDataReady
                ? AlgeriaLocationService.getCommunesForWilaya(selectedWilaya)
                : const <String>[];
            
            // Ensure the selected commune is in the communes list for the current wilaya
            String selectedCommune = communeController.text;
            if (_locationDataReady && communes.isNotEmpty && !communes.contains(selectedCommune)) {
              selectedCommune = communes.first;
              communeController.text = selectedCommune;
            }

            return AlertDialog(
              title: Text(title, textAlign: TextAlign.right),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showField('name')) ...[
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'الاسم الكامل',
                          border: OutlineInputBorder(),
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (showField('phone')) ...[
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف',
                          border: OutlineInputBorder(),
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (showField('wilaya')) ...[
                      if (_locationDataReady)
                        DropdownButtonFormField<String>(
                          value: wilayas.contains(selectedWilaya)
                              ? selectedWilaya
                              : null,
                          isExpanded: true,
                          items: wilayas
                              .map(
                                (w) =>
                                    DropdownMenuItem(
                                      value: w,
                                      child: Text(
                                        w,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedWilaya = value ?? '';
                              wilayaController.text = selectedWilaya;

                              final nextCommunes =
                                  AlgeriaLocationService.getCommunesForWilaya(
                                    selectedWilaya,
                                  );
                              if (nextCommunes.isNotEmpty) {
                                selectedCommune = nextCommunes.first;
                                communeController.text = selectedCommune;
                              } else {
                                selectedCommune = '';
                                communeController.clear();
                              }
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'الولاية',
                            border: OutlineInputBorder(),
                          ),
                        )
                      else
                        TextField(
                          controller: wilayaController,
                          decoration: const InputDecoration(
                            labelText: 'الولاية',
                            border: OutlineInputBorder(),
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      const SizedBox(height: 12),
                    ],
                    if (showField('commune')) ...[
                      if (_locationDataReady && communes.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: selectedCommune,
                          isExpanded: true,
                          items: communes
                              .map(
                                (c) =>
                                    DropdownMenuItem(
                                      value: c,
                                      child: Text(
                                        c,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedCommune = value ?? '';
                              communeController.text = selectedCommune;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'البلدية',
                            border: OutlineInputBorder(),
                          ),
                        )
                      else
                        TextField(
                          controller: communeController,
                          decoration: const InputDecoration(
                            labelText: 'البلدية',
                            border: OutlineInputBorder(),
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      const SizedBox(height: 12),
                    ],
                    if (showField('address')) ...[
                      TextField(
                        controller: addressController,
                        decoration: const InputDecoration(
                          labelText: 'العنوان',
                          border: OutlineInputBorder(),
                        ),
                        textDirection: TextDirection.rtl,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (showField('product')) ...[
                      TextField(
                        controller: productController,
                        decoration: const InputDecoration(
                          labelText: 'المنتج',
                          border: OutlineInputBorder(),
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (showField('price'))
                      TextField(
                        controller: priceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'السعر',
                          border: OutlineInputBorder(),
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                TextButton(
                  onPressed: () async {
                    final data = <String, String>{
                      'name': nameController.text.trim(),
                      'phone': _normalizePhone(phoneController.text.trim()),
                      'wilaya': wilayaController.text.trim(),
                      'commune': communeController.text.trim(),
                      'address': addressController.text.trim(),
                      'product': productController.text.trim(),
                      'price': priceController.text.trim(),
                    };

                    final missing = <String>[];
                    for (final field in needed) {
                      if ((data[field] ?? '').isEmpty) {
                        missing.add(_fieldLabel(field));
                      }
                    }

                    if (showField('phone') && data['phone']!.isNotEmpty) {
                      if (!_isValidAlgerianPhone(data['phone']!)) {
                        missing.add(_fieldLabel('phone'));
                      }
                    }

                    if (_locationDataReady && showField('wilaya')) {
                      final normalizedWilaya =
                          AlgeriaLocationService.normalizeWilaya(
                            data['wilaya']!,
                          );
                      if (normalizedWilaya == null) {
                        missing.add(_fieldLabel('wilaya'));
                      } else {
                        data['wilaya'] = normalizedWilaya;
                      }
                    }

                    if (_locationDataReady &&
                        showField('commune') &&
                        data['wilaya']!.isNotEmpty &&
                        data['commune']!.isNotEmpty) {
                      final normalizedCommune =
                          AlgeriaLocationService.normalizeCommune(
                            data['wilaya']!,
                            data['commune']!,
                          );
                      if (normalizedCommune == null) {
                        missing.add(_fieldLabel('commune'));
                      } else {
                        data['commune'] = normalizedCommune;
                      }
                    }

                    if (showField('price') && data['price']!.isNotEmpty) {
                      final parsed = int.tryParse(data['price']!);
                      if (parsed == null || parsed < 0) {
                        missing.add(_fieldLabel('price'));
                      }
                    }

                    if (missing.isNotEmpty) {
                      _showError('يرجى مراجعة: ${missing.toSet().join('، ')}');
                      return;
                    }

                    final saved = await _updateOrderFields(
                      order,
                      name: data['name']!.isNotEmpty
                          ? data['name']!
                          : order.name,
                      phone: data['phone']!.isNotEmpty
                          ? data['phone']!
                          : order.phone,
                      wilaya: data['wilaya']!.isNotEmpty
                          ? data['wilaya']!
                          : order.wilaya,
                      commune: data['commune']!.isNotEmpty
                          ? data['commune']!
                          : order.commune,
                      address: data['address']!.isNotEmpty
                          ? data['address']!
                          : order.address,
                      product: data['product']!.isNotEmpty
                          ? data['product']!
                          : (order.product.isNotEmpty ? order.product : 'طلب'),
                      price: data['price']!.isNotEmpty
                          ? data['price']!
                          : (order.price.isNotEmpty ? order.price : '0'),
                      showSuccessMessage: showSuccessMessage,
                    );

                    if (!saved || !dialogContext.mounted) return;
                    Navigator.pop(dialogContext, true);
                  },
                  child: Text(saveLabel),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
  }

  void _showLogisticsSheet(AppOrder order) {
    if (_shippingRowsInProgress.contains(order.row)) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'اختر شركة التوصيل',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.local_shipping),
              title: const Text('Yalidine'),
              onTap: () {
                Navigator.pop(context);
                _shipWithYalidine(order);
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping),
              title: const Text('EcoTrack'),
              onTap: () {
                Navigator.pop(context);
                _shipWithEcoTrack(order);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _shipWithYalidine(AppOrder order) async {
    if (_shippingRowsInProgress.contains(order.row)) return;

    try {
      final ready = await _ensureReadyForShipping(order, forEcoTrack: false);
      if (!ready) return;

      // Get Yalidine API token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final yalidineToken = prefs.getString('yalidine_token');

      if (yalidineToken == null || yalidineToken.isEmpty) {
        _showError('خطأ: لم يتم حفظ رمز Yalidine. يرجى تحديثه في الإعدادات.');
        return;
      }

      if (!mounted) return;

      setState(() {
        _shippingRowsInProgress.add(order.row);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جاري إرسال الطلب إلى Yalidine...'),
          duration: Duration(seconds: 2),
        ),
      );

      YalidineService.setApiToken(yalidineToken);
      final trackingNumber = await YalidineService.createShipment(order);

      if (trackingNumber != null) {
        await _updateTrackingAndStatus(order, trackingNumber, 'uploaded');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم الإرسال بنجاح! رقم التتبع: $trackingNumber'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      _showError('خطأ Yalidine: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _shippingRowsInProgress.remove(order.row);
      });
    }
  }

  Future<bool> _validateAndFixEcoTrackCommune(AppOrder order) async {
    final wilayaName = order.wilaya.trim();
    final communeName = order.commune.trim();

    if (wilayaName.isEmpty || communeName.isEmpty) return false;

    // Get wilaya code
    final wilayaCode = AlgeriaLocationService.getWilayaId(wilayaName);
    if (wilayaCode == null) {
      _showError('الولاية غير معروفة في EcoTrack: $wilayaName');
      return false;
    }

    try {
      // Fetch valid communes from EcoTrack
      final validCommunes = await EcoTrackService.getCommunes(wilayaCode);

      if (validCommunes.isEmpty) {
        _showError('لم يتمكن من جلب البلديات من EcoTrack');
        return false;
      }

      // Check if commune is already in valid list (case-insensitive)
      final exactMatch = validCommunes.firstWhere(
        (c) => c.trim().toLowerCase() == communeName.toLowerCase(),
        orElse: () => '',
      );

      if (exactMatch.isNotEmpty) {
        // Update order with exact match
        if (order.commune != exactMatch) {
          setState(() {
            order.commune = exactMatch;
          });
        }
        return true;
      }

      // Try fuzzy match
      final fuzzyMatch = validCommunes.firstWhere(
        (c) {
          final clean1 = c.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
          final clean2 = communeName.toLowerCase().replaceAll(RegExp(r'\s+'), '');
          final matches = clean1.split('').where((char) => clean2.contains(char)).length;
          final similarity = matches / (clean1.length > clean2.length ? clean1.length : clean2.length);
          return similarity >= 0.75;
        },
        orElse: () => '',
      );

      if (fuzzyMatch.isNotEmpty) {
        setState(() {
          order.commune = fuzzyMatch;
        });
        return true;
      }

      // No automatic match found - ask user to pick from valid communes
      if (!mounted) return false;

      final selected = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('اختر البلدية الصحيحة', textAlign: TextAlign.right),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              itemCount: validCommunes.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(validCommunes[index], textAlign: TextAlign.right),
                  onTap: () => Navigator.pop(context, validCommunes[index]),
                );
              },
            ),
          ),
        ),
      );

      if (selected != null) {
        setState(() {
          order.commune = selected;
        });
        return true;
      }

      return false;
    } catch (e) {
      _showError('خطأ في التحقق من البلديات: $e');
      return false;
    }
  }

  void _shipWithEcoTrack(AppOrder order) async {
    if (_shippingRowsInProgress.contains(order.row)) return;

    try {
      final ready = await _ensureReadyForShipping(order, forEcoTrack: true);
      if (!ready) return;

      // Get EcoTrack API token from SharedPreferences FIRST
      final prefs = await SharedPreferences.getInstance();
      final ecotrackToken = prefs.getString('ecotrack_token');

      if (ecotrackToken == null || ecotrackToken.isEmpty) {
        _showError('خطأ: لم يتم حفظ رمز EcoTrack. يرجى تحديثه في الإعدادات.');
        return;
      }

      // Set token before validating communes
      EcoTrackService.setApiToken(ecotrackToken);

      // Validate and fix commune against EcoTrack's database
      final communeOk = await _validateAndFixEcoTrackCommune(order);
      if (!communeOk) return;

      if (!mounted) return;

      setState(() {
        _shippingRowsInProgress.add(order.row);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جاري إرسال الطلب إلى EcoTrack...'),
          duration: Duration(seconds: 2),
        ),
      );

      final trackingNumber = await EcoTrackService.createParcel(order);

      if (trackingNumber != null) {
        await _updateTrackingAndStatus(order, trackingNumber, 'uploaded');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم الإرسال بنجاح! رقم التتبع: $trackingNumber'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      _showError('خطأ EcoTrack: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _shippingRowsInProgress.remove(order.row);
      });
    }
  }

  Future<void> _updateTrackingAndStatus(
    AppOrder order,
    String newTrackingNumber,
    String newStatus,
  ) async {
    final oldStatus = order.status;
    final oldTracking = order.trackingNumber;
    setState(() {
      order.status = newStatus;
      order.trackingNumber = newTrackingNumber;
    });

    try {
      final api = await GoogleAuthService.getSheetsApi();
      if (api == null) throw Exception('API Call failed, not logged in.');

      // Update Column F (status) and K (tracking)
      final batchUpdate = sheets.BatchUpdateValuesRequest(
        valueInputOption: 'USER_ENTERED',
        data: [
          sheets.ValueRange(
            range: 'F${order.row}',
            values: [
              [newStatus],
            ],
          ),
          sheets.ValueRange(
            range: 'K${order.row}',
            values: [
              [newTrackingNumber],
            ],
          ),
        ],
      );

      await api.spreadsheets.values.batchUpdate(
        batchUpdate,
        widget.spreadsheetId,
      );
    } catch (e) {
      // Revert if API fails
      setState(() {
        order.status = oldStatus;
        order.trackingNumber = oldTracking;
      });
      _showError('خطأ أثناء التحديث! تم التراجع عن التغيير: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _getFilteredOrders();
    final totalOrders = allOrders.length;
    final statusCounts = _buildStatusCounts();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'لوحة تتبع الطلبات',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchData,
            color: const Color(0xFF10B981),
            tooltip: 'تحديث',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            color: Colors.redAccent,
            tooltip: 'تغيير الرابط',
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF10B981)),
            )
          : Column(
              children: [
                _buildHeaderPanel(
                  totalOrders: totalOrders,
                  visibleOrders: filteredOrders.length,
                  statusCounts: statusCounts,
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: fetchData,
                    color: const Color(0xFF10B981),
                    child: _buildOrderList(filteredOrders),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeaderPanel({
    required int totalOrders,
    required int visibleOrders,
    required Map<String, int> statusCounts,
  }) {
    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو الهاتف أو الولاية أو رقم التتبع',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'مسح البحث',
                        onPressed: () => _searchController.clear(),
                      ),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF7F7F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildStatusChip(
                    'الكل',
                    null,
                    allOrders.length,
                    Icons.inbox,
                    Colors.blueGrey,
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChip(
                    'جديد',
                    'جديد',
                    statusCounts['جديد'] ?? 0,
                    Icons.fiber_new,
                    const Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChip(
                    'مؤكد',
                    'confirm',
                    statusCounts['confirm'] ?? 0,
                    Icons.check_circle,
                    const Color(0xFF10B981),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChip(
                    'لا إجابة',
                    'no_response',
                    statusCounts['no_response'] ?? 0,
                    Icons.hourglass_empty_rounded,
                    Colors.orangeAccent,
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChip(
                    'ملغى',
                    'canceled',
                    statusCounts['canceled'] ?? 0,
                    Icons.cancel,
                    Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChip(
                    'أرشيف',
                    'uploaded',
                    statusCounts['uploaded'] ?? 0,
                    Icons.upload_rounded,
                    const Color(0xFF065F46),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'عرض $visibleOrders من $totalOrders طلب',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(
    String label,
    String? status,
    int count,
    IconData icon,
    Color color,
  ) {
    final isActive = filterStatus == status;
    return FilterChip(
      selected: isActive,
      onSelected: (_) {
        setState(() {
          filterStatus = status;
        });
      },
      showCheckmark: false,
      avatar: Icon(icon, size: 16, color: isActive ? color : Colors.black54),
      label: Text('$label ($count)'),
      selectedColor: color.withValues(alpha: 0.14),
      side: BorderSide(color: isActive ? color : Colors.black12),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildOrderList(List<AppOrder> orders) {
    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      slivers: [
        if (orders.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'لا توجد طلبات مطابقة',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final order = orders[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RepaintBoundary(
                      child: OrderCard(
                        key: ValueKey(order.row),
                        order: order,
                        onStatusChange: (newStatus) =>
                            _updateOrderStatus(order, newStatus),
                        onEdit: () => _showEditDialog(order),
                        onShip: _shippingRowsInProgress.contains(order.row)
                            ? null
                            : () => _showLogisticsSheet(order),
                      ),
                    ),
                  );
                },
                childCount: orders.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
              ),
            ),
          ),
      ],
    );
  }
}
