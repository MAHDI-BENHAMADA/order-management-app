import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import '../models/order.dart';
import '../widgets/order_card.dart';
import '../utils/google_auth_service.dart';
import '../services/yalidine_service.dart';
import '../services/ecotrack_service.dart';
import 'setup_screen.dart';

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
    fetchData();
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

  Future<void> _updateOrderFields(
    AppOrder order, {
    required String name,
    required String wilaya,
    required String commune,
    required String address,
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
        ],
      );

      await api.spreadsheets.values.batchUpdate(
        batchUpdate,
        widget.spreadsheetId,
      );

      setState(() {
        order.name = name;
        // Note: wilaya, commune, address are final in the current model, so this won't work.
        // You'll need to make them mutable or create a separate edit state.
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ التعديلات بنجاح!'),
            duration: Duration(seconds: 1),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      _showError('خطأ أثناء حفظ التعديلات: $e');
    }
  }

  void _showEditDialog(AppOrder order) {
    final nameController = TextEditingController(text: order.name);
    final communeController = TextEditingController(text: order.commune);
    final addressController = TextEditingController(text: order.address);
    String selectedWilaya = order.wilaya;

    final List<String> wilayaList = [
      'الجزائر',
      'بلیدة',
      'ورقلة',
      'إليزي',
      'تيبازة',
      'تمنراست',
      'تيسمسيلت',
      'الوادي',
      'البیض',
      'بسكرة',
      'بشار',
      'بومرداس',
      'تاجنانت',
      'تندوف',
      'تيارت',
      'تلمسان',
      'جيجل',
      'سطيف',
      'سعيدة',
      'سوق أهراس',
      'سكيكدة',
      'سيدي بلعباس',
      'شلف',
      'صفاقس',
      'عنابة',
      'عين الدفلى',
      'عين تيموشنت',
      'غار الدايس',
      'غليزان',
      'فرندة',
      'قالمة',
      'قسنطينة',
      'القيروان',
      'كلم الساحة',
      'ميلة',
      'مستغانم',
      'معسكر',
      'مدية',
      'مسيلة',
      'ولايات غير محددة',
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل الطلب', textAlign: TextAlign.right),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل',
                  border: OutlineInputBorder(),
                ),
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedWilaya,
                items: wilayaList
                    .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                    .toList(),
                onChanged: (val) => selectedWilaya = val ?? order.wilaya,
                decoration: const InputDecoration(
                  labelText: 'الولاية',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: communeController,
                decoration: const InputDecoration(
                  labelText: 'البلدية',
                  border: OutlineInputBorder(),
                ),
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  border: OutlineInputBorder(),
                ),
                textDirection: TextDirection.rtl,
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              _updateOrderFields(
                order,
                name: nameController.text,
                wilaya: selectedWilaya,
                commune: communeController.text,
                address: addressController.text,
              );
              Navigator.pop(context);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showLogisticsSheet(AppOrder order) {
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
    try {
      // Get Yalidine API token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final yalidineToken = prefs.getString('yalidine_token');

      if (yalidineToken == null || yalidineToken.isEmpty) {
        _showError('خطأ: لم يتم حفظ رمز Yalidine. يرجى تحديثه في الإعدادات.');
        return;
      }

      if (!mounted) return;

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
    }
  }

  void _shipWithEcoTrack(AppOrder order) async {
    try {
      // Get EcoTrack API token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final ecotrackToken = prefs.getString('ecotrack_token');

      if (ecotrackToken == null || ecotrackToken.isEmpty) {
        _showError('خطأ: لم يتم حفظ رمز EcoTrack. يرجى تحديثه في الإعدادات.');
        return;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جاري إرسال الطلب إلى EcoTrack...'),
          duration: Duration(seconds: 2),
        ),
      );

      EcoTrackService.setApiToken(ecotrackToken);
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
                        onShip: () => _showLogisticsSheet(order),
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
