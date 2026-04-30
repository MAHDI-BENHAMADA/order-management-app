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
import 'staff_management_screen.dart';
import 'setup_screen.dart';
import '../services/column_mapper_service.dart';
import '../services/staff_sheets_service.dart';

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
  List<Map<String, dynamic>> _ecoTrackProducts = [];
  bool isLoading = true;
  String? filterStatus; // null = show all
  String _searchQuery = '';
  ShippingProvider _selectedProvider = ShippingProvider.e48hr;
  String _defaultPrice = '';
  String _defaultProduct = '';
  bool isOwner = false;
  bool _logoutInProgress = false;
  static const int _stopDeskDomicile = 0;
  static const int _stopDeskPointRelais = 1;
  static const int _stockNo = 0;
  static const int _stockYes = 1;
  static const int _stockQuantityDefault = 1;
  /// Reverse of the column map: field key → column letter (e.g. 'status' → 'F')
  Map<String, String> _fieldToColumn = {};


  Future<List<List<dynamic>>> _sheetsGet(String range) async {
    if (isOwner) {
      final api = await GoogleAuthService.getSheetsApi();
      if (api == null) throw Exception('API Call failed, not logged in.');
      final response = await api.spreadsheets.values.get(widget.spreadsheetId!, range);
      return (response.values ?? []).map((e) => e as List<dynamic>).toList();
    } else {
      final response = await StaffSheetsService.getValues(widget.spreadsheetId!, range);
      return (response.values ?? []).map((e) => e as List<dynamic>).toList();
    }
  }

  Future<void> _sheetsUpdate(String range, List<List<dynamic>> values) async {
    if (isOwner) {
      final api = await GoogleAuthService.getSheetsApi();
      if (api == null) throw Exception('API Call failed, not logged in.');
      await api.spreadsheets.values.update(
        sheets.ValueRange(values: values),
        widget.spreadsheetId!,
        range,
        valueInputOption: 'USER_ENTERED',
      );
    } else {
      await StaffSheetsService.updateValues(widget.spreadsheetId!, range, sheets.ValueRange(values: values));
    }
  }

  Future<void> _sheetsBatchUpdate(sheets.BatchUpdateValuesRequest request) async {
    if (isOwner) {
      final api = await GoogleAuthService.getSheetsApi();
      if (api == null) throw Exception('API Call failed, not logged in.');
      await api.spreadsheets.values.batchUpdate(request, widget.spreadsheetId!);
    } else {
      await StaffSheetsService.batchUpdate(widget.spreadsheetId!, request);
    }
  }


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

      // Load stored defaults for this sheet
      if (widget.spreadsheetId != null && widget.spreadsheetId!.isNotEmpty) {
        _defaultPrice = prefs.getString('default_price_${widget.spreadsheetId}') ?? '';
        _defaultProduct = prefs.getString('default_product_${widget.spreadsheetId}') ?? '';
      }
      
      isOwner = prefs.getBool('isOwner') ?? false;

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
      // Read the entire sheet dynamically (no hardcoded range)
      List<List<dynamic>> rows;
      try {
        rows = await _sheetsGet('A:ZZ');
      } catch (e) {
        _showError('خطأ: لم يتم تسجيل الدخول بصلاحيات كافية.');
        await _logout();
        return;
      }
      if (rows.isEmpty) {
        setState(() { allOrders = []; isLoading = false; });
        return;
      }

      // --- Step 1: Map headers from the first row ---
      final headerRow = rows[0].map((h) => h.toString()).toList();
      final columnMap = ColumnMapperService.mapHeaders(headerRow);

      print('🗺️ Column mapping detected: $columnMap');

      // Build reverse map: field → column letter (used for writes)
      final newFieldToColumn = <String, String>{};
      columnMap.forEach((letter, field) {
        if (field != null) newFieldToColumn[field] = letter;
      });

      // --- Content-based fallback: detect status/tracking if headers didn't match ---
      // Known status values that may appear in the data
      const knownStatusValues = {
        'confirm', 'no_response', 'canceled', 'uploaded', 'جديد',
        'مؤكد', 'ملغى', 'لا إجابة', 'أرشيف', 'nouveau', 'confirmé',
      };
      final mappedLetters = newFieldToColumn.values.toSet();

      if (!newFieldToColumn.containsKey('status')) {
        for (int col = 0; col < headerRow.length; col++) {
          final letter = _colLetter(col);
          if (mappedLetters.contains(letter)) continue;
          int hits = 0;
          for (int row = 1; row < rows.length && row <= 10; row++) {
            final r = rows[row];
            if (col < r.length) {
              final v = r[col].toString().trim().toLowerCase();
              if (knownStatusValues.contains(v)) hits++;
            }
          }
          if (hits > 0) {
            newFieldToColumn['status'] = letter;
            columnMap[letter] = 'status';
            mappedLetters.add(letter);
            print('✅ Content-based status detection: column $letter');
            break;
          }
        }
      }

      // --- Auto-assign missing critical columns to the end of the sheet ---
      Future<void> _ensureColumnExists(String field, String headerName) async {
        if (!newFieldToColumn.containsKey(field)) {
          int nextCol = headerRow.length;
          while (mappedLetters.contains(_colLetter(nextCol))) nextCol++;
          
          final letter = _colLetter(nextCol);
          newFieldToColumn[field] = letter;
          columnMap[letter] = field;
          mappedLetters.add(letter);
          print('🆕 Auto-assigned $field to new column $letter');

          // Write header to sheet so it's permanent
          try {
            await _sheetsUpdate('${letter}1', [[headerName]]);
          } catch (_) {}
        }
      }

      await _ensureColumnExists('status', 'Statut');
      await _ensureColumnExists('tracking', 'Tracking');

      setState(() { _fieldToColumn = newFieldToColumn; });

      // --- Step 2: Parse each data row using the mapping ---
      final List<dynamic> parsedData = [];
      for (int i = 1; i < rows.length; i++) {
        final r = rows[i];

        // Build the order map using the detected column mapping
        final orderMap = ColumnMapperService.rowToOrderMap(
          dataRow: r,
          columnMap: columnMap,
          sheetRowNumber: i + 1,
          columnMapping: columnMap,
        );

        // Only include rows that have at least a name or phone
        final name = orderMap['name']?.toString() ?? '';
        final phone = orderMap['phone']?.toString() ?? '';
        if (name.isNotEmpty || phone.isNotEmpty) {
          parsedData.add(orderMap);
        }
      }

      final processedOrders = AppOrder.processRawData(parsedData);
      await _applyStopDeskSelections(processedOrders);
      await _applyStockSelections(processedOrders);
      await _applyQuantitySelections(processedOrders);

      setState(() {
        allOrders = processedOrders;
      });
    } catch (e) {
      _showError('تعذر جلب البيانات: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  String _stopDeskKey(int row) {
    final sheetId = widget.spreadsheetId?.trim().isNotEmpty == true
        ? widget.spreadsheetId!.trim()
        : 'default';
    return 'stop_desk_${sheetId}_$row';
  }

  Future<void> _applyStopDeskSelections(List<AppOrder> orders) async {
    final prefs = await SharedPreferences.getInstance();
    for (final order in orders) {
      final value = prefs.getInt(_stopDeskKey(order.row));
      order.stopDesk = value == _stopDeskPointRelais ? _stopDeskPointRelais : _stopDeskDomicile;
    }
  }

  Future<void> _saveStopDeskSelection(AppOrder order, int value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value == _stopDeskPointRelais ? _stopDeskPointRelais : _stopDeskDomicile;
    await prefs.setInt(_stopDeskKey(order.row), normalized);
    order.stopDesk = normalized;
  }

  String _stockKey(int row) {
    final sheetId = widget.spreadsheetId?.trim().isNotEmpty == true
        ? widget.spreadsheetId!.trim()
        : 'default';
    return 'stock_${sheetId}_$row';
  }

  Future<void> _applyStockSelections(List<AppOrder> orders) async {
    final prefs = await SharedPreferences.getInstance();
    for (final order in orders) {
      final value = prefs.getInt(_stockKey(order.row));
      order.stock = value == _stockYes ? _stockYes : _stockNo;
    }
  }

  Future<void> _saveStockSelection(AppOrder order, int value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value == _stockYes ? _stockYes : _stockNo;
    await prefs.setInt(_stockKey(order.row), normalized);
    order.stock = normalized;
  }

  String _quantityKey(int row) {
    final sheetId = widget.spreadsheetId?.trim().isNotEmpty == true
        ? widget.spreadsheetId!.trim()
        : 'default';
    return 'quantity_${sheetId}_$row';
  }

  Future<void> _applyQuantitySelections(List<AppOrder> orders) async {
    final prefs = await SharedPreferences.getInstance();
    for (final order in orders) {
      final value = prefs.getInt(_quantityKey(order.row));
      order.quantity = value ?? _stockQuantityDefault;
    }
  }

  Future<void> _saveQuantitySelection(AppOrder order, int value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value > 0 ? value : _stockQuantityDefault;
    await prefs.setInt(_quantityKey(order.row), normalized);
    order.quantity = normalized;
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

      drive.FileList fileList;
      try {
        fileList = await driveApi.files.list(
          q: "mimeType='application/vnd.google-apps.spreadsheet'",
          spaces: 'drive',
          pageSize: 100,
        );
      } catch (e) {
        if (e is drive.DetailedApiRequestError && e.status == 401 && isOwner) {
          final user = await GoogleAuthService.signIn();
          if (user == null) {
            if (mounted) Navigator.pop(context);
            _showError('يرجى تسجيل الدخول من جديد');
            return;
          }

          final retryApi = await GoogleAuthService.getDriveApi();
          if (retryApi == null) {
            if (mounted) Navigator.pop(context);
            _showError('تعذر إعادة الاتصال بـ Google Drive');
            return;
          }

          fileList = await retryApi.files.list(
            q: "mimeType='application/vnd.google-apps.spreadsheet'",
            spaces: 'drive',
            pageSize: 100,
          );
        } else {
          rethrow;
        }
      }

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

        // Keep the sheet-sharing flow, but fetch the service account address from the backend.
        try {
          final serviceAccountEmail = await GoogleAuthService.getServiceAccountEmail();
          if (serviceAccountEmail != null && serviceAccountEmail.isNotEmpty) {
            final permission = drive.Permission(
              type: 'user',
              role: 'writer',
              emailAddress: serviceAccountEmail,
            );

            await driveApi.permissions.create(
              permission,
              selectedFile.id!,
              sendNotificationEmail: false,
            );
            print('Successfully shared sheet with service account: $serviceAccountEmail');
          }
        } catch (e) {
          print('Could not auto-share sheet: $e');
        }

        // Prompt for product settings right after choosing the sheet
        await _showProductSettingsDialog(selectedFile.id!, isInitialSetup: true);

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

  /// Shows a dialog to set or change the default product name & price for the current sheet.
  Future<void> _showProductSettingsDialog(String spreadsheetId, {bool isInitialSetup = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final currentPrice = prefs.getString('default_price_$spreadsheetId') ?? '';
    final currentProduct = prefs.getString('default_product_$spreadsheetId') ?? '';
    final priceController = TextEditingController(text: currentPrice);
    final productController = TextEditingController(text: currentProduct);

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: !isInitialSetup,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.settings_rounded, size: 40, color: Color(0xFF10B981)),
              ),
              const SizedBox(height: 20),
              Text(
                isInitialSetup ? 'إعدادات المنتج' : 'تعديل إعدادات المنتج',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isInitialSetup
                    ? 'حدد اسم المنتج وسعره — سيُملأ تلقائيًا عند الشحن'
                    : 'عدّل الإعدادات — سيُطبّق على الطلبات الجديدة',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              // Product name field
              TextField(
                controller: productController,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'اسم المنتج',
                  hintText: 'مثلا: كريم العناية',
                  prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20, color: Colors.black45),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey[200]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey[200]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Price field
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: TextStyle(color: Colors.grey[300], fontSize: 28),
                  labelText: 'السعر',
                  suffixText: 'د.ج',
                  suffixStyle: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey[200]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey[200]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (!isInitialSetup)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                        child: const Text('إلغاء', style: TextStyle(color: Colors.black87)),
                      ),
                    ),
                  if (!isInitialSetup) const SizedBox(width: 12),
                  Expanded(
                    flex: isInitialSetup ? 1 : 2,
                    child: ElevatedButton(
                      onPressed: () async {
                        final price = priceController.text.trim();
                        final product = productController.text.trim();
                        await prefs.setString('default_price_$spreadsheetId', price);
                        await prefs.setString('default_product_$spreadsheetId', product);
                        if (mounted) {
                          setState(() {
                            _defaultPrice = price;
                            _defaultProduct = product;
                          });
                        }
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        isInitialSetup ? 'حفظ والمتابعة' : 'حفظ التغيير',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
              if (isInitialSetup) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('تخطي', style: TextStyle(color: Colors.grey[500])),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _logout() async {
    if (_logoutInProgress) return;
    setState(() => _logoutInProgress = true);
    try {
      await GoogleAuthService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => SetupScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        _showError('تعذر تسجيل الخروج: $e');
      }
    } finally {
      if (mounted) setState(() => _logoutInProgress = false);
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

  /// Converts a 0-based column index to an Excel-style letter (A, B, … Z, AA, …)
  static String _colLetter(int index) {
    String result = '';
    int n = index;
    do {
      result = String.fromCharCode(65 + (n % 26)) + result;
      n = (n ~/ 26) - 1;
    } while (n >= 0);
    return result;
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
      // Use dynamic column from mapping. fetchData guarantees this exists.
      final statusCol = _fieldToColumn['status'];
      if (statusCol == null) throw Exception('Status column not found in mapping');
      
      final range = '$statusCol${order.row}';
      await _sheetsUpdate(range, [[newStatus]]);
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
      'product': order.product.trim().isNotEmpty
          ? order.product.trim()
          : (_defaultProduct.isNotEmpty ? _defaultProduct : 'طلب'),
      'price': order.price.trim().isNotEmpty
          ? order.price.trim()
          : (_defaultPrice.isNotEmpty ? _defaultPrice : '0'),
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
      // Build ranges dynamically using the detected column map.
      final List<sheets.ValueRange> ranges = [];

      void addRange(String? col, dynamic value) {
        if (col == null) return;
        ranges.add(sheets.ValueRange(
          range: '$col${order.row}',
          values: [[value]],
        ));
      }

      // Name: if sheet has separate firstName + name columns, split back
      if (_fieldToColumn.containsKey('firstName') && _fieldToColumn.containsKey('name')) {
        final parts = name.trim().split(' ');
        addRange(_fieldToColumn['firstName'], parts.first);
        addRange(_fieldToColumn['name'], parts.length > 1 ? parts.sublist(1).join(' ') : '');
      } else {
        addRange(_fieldToColumn['name'] ?? 'C', name);
      }

      addRange(_fieldToColumn['phone'] ?? 'E', phone);
      addRange(_fieldToColumn['wilaya'] ?? 'D', wilaya);
      addRange(_fieldToColumn['commune'] ?? 'G', commune);
      if (_fieldToColumn.containsKey('address')) addRange(_fieldToColumn['address'], address);
      if (_fieldToColumn.containsKey('product')) addRange(_fieldToColumn['product'], product);
      if (_fieldToColumn.containsKey('price'))   addRange(_fieldToColumn['price'], price);

      if (ranges.isNotEmpty) {
        final batchUpdate = sheets.BatchUpdateValuesRequest(
          valueInputOption: 'USER_ENTERED',
          data: ranges,
        );
        await _sheetsBatchUpdate(batchUpdate);
      }

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
    // Fetch ecotrack products if we are using ecotrack
    if (_selectedProvider.integrationType == 'ecotrack' && _ecoTrackProducts.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final tokenKey = _getTokenKeyForProvider(_selectedProvider);
        final apiToken = prefs.getString(tokenKey) ?? prefs.getString('ecotrack_token');
        if (apiToken != null && apiToken.isNotEmpty) {
          ShippingProviderFactory.initializeServiceForProvider(_selectedProvider, apiToken);
          final products = await EcoTrackService.getProductsFromApi();
          if (mounted) {
            setState(() {
              _ecoTrackProducts = products;
            });
          }
        }
      } catch (e) {
        print('Error fetching ecotrack products: $e');
      }
    }

    // Use defaults when order has no product/price set
    final effectiveProduct = order.product.trim().isNotEmpty
        ? order.product
        : (_defaultProduct.isNotEmpty ? _defaultProduct : '');
    final effectivePrice = order.price.trim().isNotEmpty
        ? order.price
        : (_defaultPrice.isNotEmpty ? _defaultPrice : '');

    final values =
        initialValues ??
        <String, String>{
          'name': order.name,
          'phone': order.phone,
          'wilaya': order.wilaya,
          'commune': order.commune,
          'address': order.address,
          'product': effectiveProduct,
          'price': effectivePrice,
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
    
    // Auto-address helper: 'commune - wilaya' with clean names (strip number prefix)
    String _cleanName(String s) => s.replaceFirst(RegExp(r'^\d+\.\s*'), '').trim();
    String _buildAutoAddress(String w, String c) {
      final cw = _cleanName(w);
      final cc = _cleanName(c);
      if (cw.isEmpty && cc.isEmpty) return '';
      if (cw.isEmpty) return cc;
      if (cc.isEmpty) return cw;
      return '$cc - $cw';
    }

    final communeController = TextEditingController(
      text: values['commune'] ?? '',
    );
    final wilayaController = TextEditingController(
      text: values['wilaya'] ?? '',
    );

    int selectedStopDesk = order.stopDesk;
    int selectedStock = order.stock;
    final quantityController = TextEditingController(
      text: (order.quantity > 0 ? order.quantity : _stockQuantityDefault)
          .toString(),
    );

    String lastAutoAddress = _buildAutoAddress(wilayaController.text, communeController.text);
    if (addressController.text.isEmpty) {
      addressController.text = lastAutoAddress;
    }

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

                                    // Auto update address if it matches auto-generated or is empty
                                    final newAutoAddress = _buildAutoAddress(selectedWilaya, communeController.text);
                                    if (addressController.text.trim().isEmpty || addressController.text.trim() == lastAutoAddress) {
                                      addressController.text = newAutoAddress;
                                      lastAutoAddress = newAutoAddress;
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

                                    // Auto update address if it matches auto-generated or is empty
                                    final newAutoAddress = _buildAutoAddress(selectedWilaya, communeController.text);
                                    if (addressController.text.trim().isEmpty || addressController.text.trim() == lastAutoAddress) {
                                      addressController.text = newAutoAddress;
                                      lastAutoAddress = newAutoAddress;
                                    }
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
                            if (showField('deliveryType')) ...[
                              _buildDeliveryTypeDropdown(
                                value: selectedStopDesk,
                                onChanged: (value) {
                                  setDialogState(() {
                                    selectedStopDesk = value ?? _stopDeskDomicile;
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (showField('stock')) ...[
                              _buildStockDropdown(
                                value: selectedStock,
                                onChanged: (value) {
                                  setDialogState(() {
                                    selectedStock = value ?? _stockNo;
                                    if (selectedStock == _stockYes &&
                                        quantityController.text.trim().isEmpty) {
                                      quantityController.text =
                                          _stockQuantityDefault.toString();
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (showField('stock') && selectedStock == _stockYes) ...[
                              _buildQuantityField(controller: quantityController),
                              const SizedBox(height: 16),
                            ],
                            if (showField('product') || showField('price'))
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showField('product'))
                                    Expanded(
                                      flex: 2,
                                      child: (selectedStock == _stockYes && _ecoTrackProducts.isNotEmpty)
                                          ? _buildProductAutocomplete(
                                              controller: productController,
                                              products: _ecoTrackProducts,
                                              onSelected: (val) {
                                                productController.text = val;
                                              },
                                            )
                                          : _buildModernTextField(
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

                                if (saved) {
                                  await _saveStopDeskSelection(order, selectedStopDesk);
                                  await _saveStockSelection(order, selectedStock);
                                  if (selectedStock == _stockYes) {
                                    final parsed = int.tryParse(
                                      quantityController.text.trim(),
                                    );
                                    await _saveQuantitySelection(
                                      order,
                                      parsed ?? _stockQuantityDefault,
                                    );
                                  } else {
                                    await _saveQuantitySelection(order, 0);
                                  }
                                }

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

  Widget _buildProductAutocomplete({
    required TextEditingController controller,
    required List<Map<String, dynamic>> products,
    required ValueChanged<String> onSelected,
  }) {
    return Autocomplete<Map<String, dynamic>>(
      initialValue: TextEditingValue(text: controller.text),
      displayStringForOption: (option) => option['reference']?.toString() ?? option['name']?.toString() ?? '',
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return products;
        }
        return products.where((product) {
          final ref = product['reference']?.toString().toLowerCase() ?? '';
          final name = product['name']?.toString().toLowerCase() ?? '';
          final search = textEditingValue.text.toLowerCase();
          return ref.contains(search) || name.contains(search);
        });
      },
      onSelected: (Map<String, dynamic> selection) {
        onSelected(selection['reference']?.toString() ?? '');
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        // Keep main controller in sync if user types manually
        textEditingController.addListener(() {
          if (textEditingController.text != controller.text) {
             controller.text = textEditingController.text;
          }
        });
        
        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: 'المنتج (اختر من المخزون)',
            prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20, color: Colors.black45),
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
      },
      optionsViewBuilder: (context, onSelectedInternal, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250, maxWidth: 300),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    title: Text(option['reference']?.toString() ?? ''),
                    subtitle: Text(option['name']?.toString() ?? ''),
                    onTap: () {
                      onSelectedInternal(option);
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeliveryTypeDropdown({
    required int value,
    required ValueChanged<int?> onChanged,
  }) {
    return DropdownButtonFormField<int>(
      value: value,
      isExpanded: true,
      items: const [
        DropdownMenuItem(value: _stopDeskDomicile, child: Text('A domicile')),
        DropdownMenuItem(value: _stopDeskPointRelais, child: Text('Stop desk')),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: 'Type de livraison',
        prefixIcon: const Icon(Icons.local_shipping_outlined, size: 20, color: Colors.black45),
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

  Widget _buildStockDropdown({
    required int value,
    required ValueChanged<int?> onChanged,
  }) {
    return DropdownButtonFormField<int>(
      value: value,
      isExpanded: true,
      items: const [
        DropdownMenuItem(value: _stockNo, child: Text('Stock: Non')),
        DropdownMenuItem(value: _stockYes, child: Text('Stock: Oui')),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: 'Préparé du stock',
        prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20, color: Colors.black45),
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

  Widget _buildQuantityField({
    required TextEditingController controller,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'Quantite',
        prefixIcon: const Icon(Icons.confirmation_number_outlined, size: 20, color: Colors.black45),
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
        labelText: 'الولاية (${wilayas.length})',
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
    final bool isReady = _locationDataReady && communes.isNotEmpty;
    
    // Ensure the value is valid for the current list of communes
    String? validValue = isReady && communes.contains(selectedValue) ? selectedValue : null;

    return DropdownButtonFormField<String>(
      value: validValue,
      isExpanded: true,
      hint: Text(
        !_locationDataReady 
            ? 'جاري التحميل...' 
            : (communes.isEmpty ? 'اختر الولاية أولاً' : 'اختر البلدية')
      ),
      items: isReady 
          ? communes.map((c) => DropdownMenuItem(
              value: c, 
              child: Text(c, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))
            )).toList()
          : [],
      onChanged: isReady ? onChanged : null,
      decoration: InputDecoration(
        labelText: 'البلدية',
        prefixIcon: const Icon(Icons.location_city_outlined, size: 20, color: Colors.black45),
        filled: true,
        fillColor: isReady ? Colors.grey[50] : Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[50]!),
        ),
      ),
    );
  }

  /// Unified shipping method that handles all provider types
  void _shipWithSelectedProvider(AppOrder order) async {
    if (_shippingRowsInProgress.contains(order.row)) return;

    try {
      // Determine if we need EcoTrack-specific validation
      final isEcoTrack = _selectedProvider.integrationType == 'ecotrack';
      final ready = await _ensureReadyForShipping(order, forEcoTrack: isEcoTrack);
      if (!ready) return;

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

      // Ensure EcoTrack service uses the correct token before validation
      if (isEcoTrack) {
        ShippingProviderFactory.initializeServiceForProvider(
          _selectedProvider,
          apiToken,
        );
      }

      // Validate and fix commune for EcoTrack providers
      if (isEcoTrack) {
        final communeOk = await _validateAndFixEcoTrackCommune(order);
        if (!communeOk) return;
      }

      if (!mounted) return;

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

  /// Bulk ship all visible confirmed orders with real-time visual tracking
  Future<void> _startOneClickBulkShip(List<AppOrder> ordersToShip) async {
    if (ordersToShip.isEmpty) {
      _showError('لا توجد طلبات مؤكدة للشحن في القائمة الحالية');
      return;
    }

    // Confirm dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0066CC).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.rocket_launch, size: 40, color: Color(0xFF0066CC)),
              ),
              const SizedBox(height: 20),
              const Text(
                'شحن بضغطة زر',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(fontSize: 15, color: Colors.grey[700]),
                  children: [
                    const TextSpan(text: 'سيتم تحويل '),
                    TextSpan(
                      text: '${ordersToShip.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0066CC)),
                    ),
                    TextSpan(text: ' طلب مؤكد إلى ${_selectedProvider.displayName} مباشرة.'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: const Text('إلغاء', style: TextStyle(color: Colors.black87)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('أكّد الشحن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0066CC),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show Progress Dialog
    final ValueNotifier<int> processedCountNotifier = ValueNotifier<int>(0);
    final ValueNotifier<String> currentOrderNameNotifier = ValueNotifier<String>('');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ValueListenableBuilder<int>(
            valueListenable: processedCountNotifier,
            builder: (context, processedCount, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF0066CC)),
                  const SizedBox(height: 24),
                  const Text('جاري الشحن...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text(
                    '$processedCount / ${ordersToShip.length}',
                    style: const TextStyle(fontSize: 20, color: Color(0xFF0066CC), fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: currentOrderNameNotifier,
                    builder: (context, name, child) {
                      return Text(name.isNotEmpty ? 'معالجة: $name' : '', style: TextStyle(color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis);
                    }
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: ordersToShip.isEmpty ? 0 : processedCount / ordersToShip.length,
                      backgroundColor: Colors.grey[200],
                      color: const Color(0xFF0066CC),
                      minHeight: 8,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    int successCount = 0;
    int failCount = 0;

    for (final order in ordersToShip) {
      if (!mounted) break;
      
      currentOrderNameNotifier.value = order.name.isNotEmpty ? order.name : 'طلب #${order.row}';
      
      try {
        final isEcoTrack = _selectedProvider.integrationType == 'ecotrack';
        final readiness = _buildShippingReadiness(order, forEcoTrack: isEcoTrack);

        if (!readiness.isReady) {
          failCount++;
        } else {
          bool canShip = true;
          if (_hasNormalizedChanges(order, readiness.normalizedValues)) {
            final saved = await _saveNormalizedValues(order, readiness.normalizedValues);
            if (!saved) canShip = false;
          }

          if (canShip && isEcoTrack) {
            final communeOk = await _validateAndFixEcoTrackCommune(order);
            if (!communeOk) canShip = false;
          }

          if (canShip) {
            final prefs = await SharedPreferences.getInstance();
            final tokenKey = _getTokenKeyForProvider(_selectedProvider);
            final apiToken = prefs.getString(tokenKey);

            if (apiToken == null || apiToken.isEmpty) {
              failCount++;
            } else {
              if (isEcoTrack) {
                ShippingProviderFactory.initializeServiceForProvider(
                  _selectedProvider,
                  apiToken,
                );
              }

              setState(() => _shippingRowsInProgress.add(order.row));

              final trackingNumber = await ShippingProviderFactory
                  .createShipmentWithSelectedProvider(order, apiToken);

              if (trackingNumber != null) {
                await _updateTrackingAndStatus(order, trackingNumber, 'uploaded');
                successCount++;
              } else {
                failCount++;
              }
            }
          } else {
            failCount++;
          }
        }
      } catch (e) {
        failCount++;
      } finally {
        if (mounted) setState(() => _shippingRowsInProgress.remove(order.row));
      }
      
      processedCountNotifier.value++;
    }

    // Close progress dialog
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    if (!mounted) return;

    // Show final summary dialog
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                failCount == 0 ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                size: 60,
                color: failCount == 0 ? const Color(0xFF10B981) : Colors.orange,
              ),
              const SizedBox(height: 16),
              const Text(
                'اكتملت العملية',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('نُفذت بنجاح:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('$successCount', style: const TextStyle(fontSize: 18, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                      ],
                    ),
                    if (failCount > 0) ...[
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('فشلت:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('$failCount', style: const TextStyle(fontSize: 18, color: Colors.red, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'سبب الفشل عادة يكون بيانات ناقصة (لا توجد ولاية، بلدية، أو رقم هاتف غير صحيح) يرجى مراجعتها وتصحيحها.',
                        style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                        textAlign: TextAlign.center,
                      )
                    ]
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0066CC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('حسناً', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Map provider to SharedPreferences token key
  String _getTokenKeyForProvider(ShippingProvider provider) {
    return 'provider_token_${provider.id}';
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
      final statusCol   = _fieldToColumn['status'];
      final trackingCol = _fieldToColumn['tracking'];
      if (statusCol == null || trackingCol == null) throw Exception('Status or Tracking column not found in mapping');

      final batchUpdate = sheets.BatchUpdateValuesRequest(
        valueInputOption: 'USER_ENTERED',
        data: [
          sheets.ValueRange(range: '$statusCol${order.row}',   values: [[newStatus]]),
          sheets.ValueRange(range: '$trackingCol${order.row}', values: [[newTrackingNumber]]),
        ],
      );

      await _sheetsBatchUpdate(batchUpdate);
    } catch (e) {
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
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    'إضافة جدول بيانات',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
          if (isOwner && widget.spreadsheetId != null && widget.spreadsheetId!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.people_alt),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StaffManagementScreen(
                      currentSpreadsheetId: widget.spreadsheetId!,
                    ),
                  ),
                );
              },
              color: const Color(0xFF10B981),
              tooltip: 'إدارة الموظفين',
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              if (widget.spreadsheetId != null) {
                _showProductSettingsDialog(widget.spreadsheetId!);
              }
            },
            color: const Color(0xFF10B981),
            tooltip: _defaultProduct.isNotEmpty || _defaultPrice.isNotEmpty
                ? '${_defaultProduct.isNotEmpty ? _defaultProduct : 'منتج'} • ${_defaultPrice.isNotEmpty ? '$_defaultPrice د.ج' : 'بدون سعر'}'
                : 'إعدادات المنتج',
          ),
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.bar_chart),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StatsScreen(
                      statusCounts: statusCounts,
                      totalOrders: totalOrders,
                    ),
                  ),
                );
              },
              color: const Color(0xFF10B981),
              tooltip: 'الإحصائيات',
            ),
          IconButton(
            icon: const Icon(Icons.table_chart),
            onPressed: _showSheetSelector,
            color: const Color(0xFF10B981),
            tooltip: 'تغيير الجدول',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logoutInProgress ? null : _logout,
            color: Colors.redAccent,
            tooltip: 'تسجيل الخروج',
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
      // Ship all visible confirmed orders
      floatingActionButton: filterStatus == 'confirm' && (statusCounts['confirm'] ?? 0) > 0
          ? FloatingActionButton.extended(
              onPressed: () {
                final ordersToShip = filteredOrders.where((o) => o.status == 'confirm').toList();
                _startOneClickBulkShip(ordersToShip);
              },
              backgroundColor: const Color(0xFF0066CC),
              icon: const Icon(Icons.rocket_launch, color: Colors.white),
              label: Text('شحن الكل بضغطة زر (${statusCounts['confirm'] ?? 0})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            )
          : null,
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
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'إعداد رموز API',
                  icon: const Icon(Icons.key),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const TokenStatusDialog(),
                    );
                  },
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
                        onStatusChange: (newStatus) => _updateOrderStatus(order, newStatus),
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

class StatsScreen extends StatelessWidget {
  final Map<String, int> statusCounts;
  final int totalOrders;

  const StatsScreen({
    super.key,
    required this.statusCounts,
    required this.totalOrders,
  });

  @override
  Widget build(BuildContext context) {
    final total = totalOrders == 0 ? 1 : totalOrders;
    final confirmed = statusCounts['confirm'] ?? 0;
    final uploaded = statusCounts['uploaded'] ?? 0;
    final canceled = statusCounts['canceled'] ?? 0;
    final noResponse = statusCounts['no_response'] ?? 0;
    final fresh = statusCounts['جديد'] ?? 0;
    final pending = totalOrders - uploaded - canceled;

    String percent(int value) => '${((value / total) * 100).toStringAsFixed(1)}%';

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الإحصائيات'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeroCard(totalOrders, percent(confirmed), confirmed),
          const SizedBox(height: 16),
          _buildGrid([
            _StatCardData('مؤكد', confirmed, percent(confirmed), const Color(0xFF10B981)),
            _StatCardData('أرشيف', uploaded, percent(uploaded), const Color(0xFF065F46)),
            _StatCardData('ملغى', canceled, percent(canceled), Colors.redAccent),
            _StatCardData('لا إجابة', noResponse, percent(noResponse), Colors.orangeAccent),
            _StatCardData('جديد', fresh, percent(fresh), const Color(0xFF2563EB)),
            _StatCardData('قيد المعالجة', pending, percent(pending), Colors.blueGrey),
          ]),
          const SizedBox(height: 24),
          Text(
            'نِسَب أساسية',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 12),
          _buildRatioBar('نسبة التأكيد', confirmed, totalOrders, const Color(0xFF10B981)),
          _buildRatioBar('نسبة الأرشفة', uploaded, totalOrders, const Color(0xFF065F46)),
          _buildRatioBar('نسبة الإلغاء', canceled, totalOrders, Colors.redAccent),
          _buildRatioBar('نسبة عدم الرد', noResponse, totalOrders, Colors.orangeAccent),
        ],
      ),
    );
  }

  Widget _buildHeroCard(int totalOrders, String confirmRate, int confirmed) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ملخص سريع',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 8),
          Text(
            '$totalOrders طلب',
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                confirmRate,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                'تأكيد: $confirmed',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<_StatCardData> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        return GridView.count(
          crossAxisCount: isWide ? 3 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.25,
          children: cards.map(_buildStatCard).toList(),
        );
      },
    );
  }

  Widget _buildStatCard(_StatCardData data) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(data.label, textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, color: Colors.black54)),
          const Spacer(),
          Text(
            '${data.value}',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: data.color),
          ),
          const SizedBox(height: 6),
          Text(
            data.ratio,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildRatioBar(String label, int value, int totalOrders, Color color) {
    final safeTotal = totalOrders == 0 ? 1 : totalOrders;
    final ratio = value / safeTotal;
    final percentText = '${(ratio * 100).toStringAsFixed(1)}%';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(percentText, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(label, textAlign: TextAlign.right),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              color: color,
              backgroundColor: Colors.grey.shade200,
              minHeight: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCardData {
  final String label;
  final int value;
  final String ratio;
  final Color color;

  const _StatCardData(this.label, this.value, this.ratio, this.color);
}
