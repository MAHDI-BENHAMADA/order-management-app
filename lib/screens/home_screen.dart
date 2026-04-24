import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis/drive/v3.dart' as drive;
import '../models/order.dart';
import '../models/shipping_provider.dart';
import '../widgets/order_card.dart';
import '../widgets/token_setup_dialog.dart';
import '../utils/algeria_location_service.dart';
import '../utils/google_auth_service.dart';
import '../services/ecotrack_service.dart';
import '../services/shipping_provider_factory.dart';

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
  final String? spreadsheetId;

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
  ShippingProvider _selectedProvider = ShippingProvider.e48hr;

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
      // Initialize the ShippingProviderFactory
      await ShippingProviderFactory.initialize();

      // Load stored provider selection
      final prefs = await SharedPreferences.getInstance();
      final providerId = prefs.getString('selected_provider') ?? '48hr';
      _selectedProvider = ShippingProvider.fromId(providerId);

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
    // If no spreadsheet selected, don't try to fetch
    if (widget.spreadsheetId == null || widget.spreadsheetId!.isEmpty) {
      setState(() => isLoading = false);
      return;
    }

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
        widget.spreadsheetId!,
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

  Future<void> _showSheetSelector() async {
    if (!mounted) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF10B981), strokeWidth: 3),
              const SizedBox(height: 24),
              const Text(
                'جاري تحميل الجداول...',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'يرجى الانتظار بينما نبحث في ملفاتك',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final driveApi = await GoogleAuthService.getDriveApi();
      if (driveApi == null) {
        if (mounted) Navigator.pop(context);
        _showError('خطأ: لم يتم الاتصال بـ Google Drive');
        return;
      }

      // Fetch all Google Sheets from Drive
      final fileList = await driveApi.files.list(
        q: "mimeType='application/vnd.google-apps.spreadsheet'",
        spaces: 'drive',
        pageSize: 100,
      );

      if (mounted) Navigator.pop(context); // Close loading dialog

      final files = fileList.files ?? [];

      if (files.isEmpty) {
        if (mounted) {
          _showError('لم يتم العثور على أي جداول Google Sheets');
        }
        return;
      }

      if (!mounted) return;

      // Show sheet selection dialog
      final selectedFile = await showDialog<drive.File>(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 550),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.table_chart_rounded, size: 48, color: Color(0xFF10B981)),
                const SizedBox(height: 16),
                const Text(
                  'اختر جدول البيانات',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'اختر ملف Google Sheets لمزامنته مع التطبيق',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(8),
                      itemCount: files.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final file = files[index];
                        return InkWell(
                          onTap: () => Navigator.pop(context, file),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.description, size: 20, color: Color(0xFF10B981)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        file.name ?? 'بدون اسم',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        file.id ?? '',
                                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: Colors.redAccent,
                  ),
                  child: const Text('إلغاء'),
                ),
              ],
            ),
          ),
        ),
      );

      if (selectedFile != null && selectedFile.id != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('spreadsheetId', selectedFile.id!);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(spreadsheetId: selectedFile.id!),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog if still open
        _showError('خطأ عند جلب الجداول: $e');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('spreadsheetId');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen(spreadsheetId: null)),
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
        widget.spreadsheetId!,
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
        widget.spreadsheetId!,
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
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final wilayas = _locationDataReady
                ? AlgeriaLocationService.getWilayas()
                : const <String>[];
            
            // Normalize current wilaya selector
            String currentWilayaSelection = selectedWilaya;
            if (_locationDataReady) {
               currentWilayaSelection = AlgeriaLocationService.normalizeWilaya(selectedWilaya) ?? selectedWilaya;
            }

            final communes = _locationDataReady
                ? AlgeriaLocationService.getCommunesForWilaya(currentWilayaSelection)
                : const <String>[];
            
            // Sync commune controller with selected item
            String selectedCommune = communeController.text;
            if (_locationDataReady && communes.isNotEmpty && !communes.contains(selectedCommune)) {
              selectedCommune = communes.first;
              communeController.text = selectedCommune;
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_note, color: Colors.white, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Form Content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showField('name')) ...[
                              _buildModernTextField(
                                controller: nameController,
                                label: 'الاسم الكامل',
                                icon: Icons.person_outline,
                                textDirection: TextDirection.rtl,
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (showField('phone')) ...[
                              _buildModernTextField(
                                controller: phoneController,
                                label: 'رقم الهاتف',
                                icon: Icons.phone_android,
                                keyboardType: TextInputType.phone,
                                textDirection: TextDirection.ltr,
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (showField('wilaya')) ...[
                              _buildWilayaDropdown(
                                wilayas: wilayas,
                                selectedValue: currentWilayaSelection,
                                onChanged: (value) {
                                  setDialogState(() {
                                    selectedWilaya = value ?? '';
                                    wilayaController.text = selectedWilaya;
                                    
                                    final nextCommunes = AlgeriaLocationService.getCommunesForWilaya(selectedWilaya);
                                    if (nextCommunes.isNotEmpty) {
                                      communeController.text = nextCommunes.first;
                                    } else {
                                      communeController.clear();
                                    }
                                  });
                                }
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (showField('commune')) ...[
                              _buildCommuneDropdown(
                                communes: communes,
                                selectedValue: selectedCommune,
                                onChanged: (value) {
                                  setDialogState(() {
                                    communeController.text = value ?? '';
                                  });
                                }
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (showField('address')) ...[
                              _buildModernTextField(
                                controller: addressController,
                                label: 'العنوان بالتفصيل',
                                icon: Icons.location_on_outlined,
                                textDirection: TextDirection.rtl,
                                maxLines: 2,
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (showField('product') || showField('price'))
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showField('product'))
                                    Expanded(
                                      flex: 2,
                                      child: _buildModernTextField(
                                        controller: productController,
                                        label: 'المنتج',
                                        icon: Icons.inventory_2_outlined,
                                        textDirection: TextDirection.rtl,
                                      ),
                                    ),
                                  if (showField('product') && showField('price'))
                                    const SizedBox(width: 12),
                                  if (showField('price'))
                                    Expanded(
                                      child: _buildModernTextField(
                                        controller: priceController,
                                        label: 'السعر',
                                        icon: Icons.payments_outlined,
                                        keyboardType: TextInputType.number,
                                        textDirection: TextDirection.ltr,
                                      ),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                    
                    // Buttons
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: BorderSide(color: Colors.grey[300]!),
                              ),
                              child: const Text('إلغاء', style: TextStyle(color: Colors.black87)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
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
                                  final normalizedWilaya = AlgeriaLocationService.normalizeWilaya(data['wilaya']!);
                                  if (normalizedWilaya == null) {
                                    missing.add(_fieldLabel('wilaya'));
                                  } else {
                                    data['wilaya'] = normalizedWilaya;
                                  }
                                }

                                if (_locationDataReady && showField('commune') && data['wilaya']!.isNotEmpty && data['commune']!.isNotEmpty) {
                                  final normalizedCommune = AlgeriaLocationService.normalizeCommune(data['wilaya']!, data['commune']!);
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
                                  name: data['name']!.isNotEmpty ? data['name']! : order.name,
                                  phone: data['phone']!.isNotEmpty ? data['phone']! : order.phone,
                                  wilaya: data['wilaya']!.isNotEmpty ? data['wilaya']! : order.wilaya,
                                  commune: data['commune']!.isNotEmpty ? data['commune']! : order.commune,
                                  address: data['address']!.isNotEmpty ? data['address']! : order.address,
                                  product: data['product']!.isNotEmpty ? data['product']! : (order.product.isNotEmpty ? order.product : 'طلب'),
                                  price: data['price']!.isNotEmpty ? data['price']! : (order.price.isNotEmpty ? order.price : '0'),
                                  showSuccessMessage: showSuccessMessage,
                                );

                                if (!saved || !dialogContext.mounted) return;
                                Navigator.pop(dialogContext, true);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: Text(
                                saveLabel,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return result ?? false;
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    TextDirection? textDirection,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textDirection: textDirection,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: Colors.black45),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
        ),
        labelStyle: const TextStyle(fontSize: 14, color: Colors.black54),
      ),
    );
  }

  Widget _buildWilayaDropdown({
    required List<String> wilayas,
    required String? selectedValue,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: wilayas.contains(selectedValue) ? selectedValue : null,
      isExpanded: true,
      hint: const Text('اختر الولاية'),
      items: wilayas.map((w) => DropdownMenuItem(value: w, child: Text(w, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: 'الولاية',
        prefixIcon: const Icon(Icons.map_outlined, size: 20, color: Colors.black45),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
      ),
    );
  }

  Widget _buildCommuneDropdown({
    required List<String> communes,
    required String? selectedValue,
    required ValueChanged<String?> onChanged,
  }) {
    if (!_locationDataReady || communes.isEmpty) {
      // Fallback to text field if no communes loaded
      return _buildModernTextField(
        controller: TextEditingController(text: selectedValue),
        label: 'البلدية',
        icon: Icons.location_city_outlined,
        textDirection: TextDirection.rtl,
      );
    }

    return DropdownButtonFormField<String>(
      value: communes.contains(selectedValue) ? selectedValue : (communes.isNotEmpty ? communes.first : null),
      isExpanded: true,
      items: communes.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: 'البلدية',
        prefixIcon: const Icon(Icons.location_city_outlined, size: 20, color: Colors.black45),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
      ),
    );
  }

  }

  /// Unified shipping method that handles all provider types
  void _shipWithSelectedProvider(AppOrder order) async {
    if (_shippingRowsInProgress.contains(order.row)) return;

    try {
      // Determine if we need EcoTrack-specific validation
      final isEcoTrack = _selectedProvider.integrationType == 'ecotrack';
      final ready = await _ensureReadyForShipping(order, forEcoTrack: isEcoTrack);
      if (!ready) return;

      // Validate and fix commune for EcoTrack providers
      if (isEcoTrack) {
        final communeOk = await _validateAndFixEcoTrackCommune(order);
        if (!communeOk) return;
      }

      if (!mounted) return;

      // Get the appropriate API token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final tokenKey = _getTokenKeyForProvider(_selectedProvider);
      final apiToken = prefs.getString(tokenKey);

      // If token is missing, show dialog to enter it
      if (apiToken == null || apiToken.isEmpty) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => TokenSetupDialog(
            provider: _selectedProvider,
            onTokenSaved: () {
              // Retry shipping after token is saved
              _shipWithSelectedProvider(order);
            },
          ),
        );
        return;
      }

      setState(() {
        _shippingRowsInProgress.add(order.row);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('جاري إرسال الطلب إلى ${_selectedProvider.displayName}...'),
          duration: const Duration(seconds: 2),
        ),
      );

      // Use the factory to create shipment with selected provider
      final trackingNumber = await ShippingProviderFactory
          .createShipmentWithSelectedProvider(order, apiToken);

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
      _showError('خطأ ${_selectedProvider.displayName}: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _shippingRowsInProgress.remove(order.row);
      });
    }
  }

  /// Map provider to SharedPreferences token key
  String _getTokenKeyForProvider(ShippingProvider provider) {
    return switch (provider.integrationType) {
      'ecotrack' => 'ecotrack_token',
      'yalidine' => 'yalidine_token',
      'yalitec' => 'yalitec_token',
      'procolis' => 'procolis_token',
      _ => 'ecotrack_token', // fallback
    };
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
        widget.spreadsheetId!,
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
    // If no spreadsheet selected, show sheet selector
    if (widget.spreadsheetId == null || widget.spreadsheetId!.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('اختر جدول'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.table_chart, size: 80, color: Color(0xFF10B981)),
                const SizedBox(height: 24),
                const Text(
                  'لم يتم اختيار جدول',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'اختر جدول Google Sheets لإدارة الطلبات',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _showSheetSelector,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة جدول'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
            tooltip: 'تغيير الجدول',
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
            // Provider Selector Dropdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                      color: const Color(0xFFF7F7F7),
                    ),
                    child: DropdownButton<ShippingProvider>(
                      value: _selectedProvider,
                      isExpanded: true,
                      underline: const SizedBox(), // Remove default underline
                      items: ShippingProvider.values.map((provider) {
                        return DropdownMenuItem(
                          value: provider,
                          child: Row(
                            children: [
                              const Icon(Icons.local_shipping, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  provider.displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (provider) async {
                        if (provider != null) {
                          setState(() {
                            _selectedProvider = provider;
                          });
                          // Update SharedPreferences
                          await ShippingProviderFactory
                              .setSelectedProvider(provider);
                          
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تم تحديد ${provider.displayName} كشركة التوصيل الافتراضية',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
                            : () => _shipWithSelectedProvider(order),
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
