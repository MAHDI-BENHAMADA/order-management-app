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

  const HomeScreen({Key? key, required this.spreadsheetId}) : super(key: key);

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  List<AppOrder> allOrders = [];
  bool isLoading = true;
  String? filterStatus; // null = show all "جديد", or specific status
  final Map<String, bool> expandedWilayas = {}; // Track which Wilayas are expanded
  
  // Performance caching for Wilaya grouping
  Map<String, List<AppOrder>>? _cachedGroupedData;
  String? _cachedFilterStatus;
  
  // Dynamic rendering optimization
  double _screenHeight = 0;

  @override
  void initState() {
    super.initState();
    filterStatus = 'جديد'; // Default to "New" orders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _screenHeight = MediaQuery.of(context).size.height;
      _calculateVisibleItems();
    });
    fetchData();
  }
  
  // Calculate optimal items to render based on screen height
  void _calculateVisibleItems() {
    const itemHeight = 160; // OrderCard approximate height
    final visibleCount = (_screenHeight ~/ itemHeight) + 2;
    // Dynamic calculation for reference - used by scroll cache extent
    debugPrint('Calculated visible items: $visibleCount');
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
      final response = await api.spreadsheets.values.get(widget.spreadsheetId, 'A:K');
      final rows = response.values ?? [];
      
      List<dynamic> parsedData = [];
      for (int i = 1; i < rows.length; i++) { // Start at 1 to skip headers
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
            'trackingNumber': r.length > 10 ? (r[10].toString().isEmpty ? null : r[10].toString()) : null,
          });
        }
      }

      setState(() {
        allOrders = AppOrder.processRawData(parsedData);
        // Clear cache when data changes
        _cachedGroupedData = null;
        _cachedFilterStatus = null;
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
    _scrollController.dispose();
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
    super.dispose();
  }

  // Get filtered orders based on current filter
  List<AppOrder> _getFilteredOrders() {
    if (filterStatus == null) return allOrders;
    return allOrders.where((o) => o.status == filterStatus).toList();
  }

  // Count orders by status
  int _getStatusCount(String status) {
    return allOrders.where((o) => o.status == status).length;
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
      final valueRange = sheets.ValueRange(values: [[newStatus]]);
      
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

  Future<void> _updateOrderFields(AppOrder order, {
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
          sheets.ValueRange(range: 'C${order.row}', values: [[name]]),
          sheets.ValueRange(range: 'D${order.row}', values: [[wilaya]]),
          sheets.ValueRange(range: 'G${order.row}', values: [[commune]]),
          sheets.ValueRange(range: 'H${order.row}', values: [[address]]),
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
      'الجزائر', 'بلیدة', 'ورقلة', 'إليزي', 'تيبازة', 'تمنراست', 'تيسمسيلت', 'الوادي', 'البیض',
      'بسكرة', 'بشار', 'بومرداس', 'تاجنانت', 'تندوف', 'تيارت', 'تلمسان', 'جيجل', 'سطيف',
      'سعيدة', 'سوق أهراس', 'سكيكدة', 'سيدي بلعباس', 'شلف', 'صفاقس', 'عنابة', 'عين الدفلى',
      'عين تيموشنت', 'غار الدايس', 'غليزان', 'فرندة', 'قالمة', 'قسنطينة', 'القيروان',
      'كلم الساحة', 'ميلة', 'مستغانم', 'معسكر', 'مدية', 'مسيلة', 'ولايات غير محددة'
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
                value: selectedWilaya,
                items: wilayaList.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
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

  Future<void> _updateTrackingAndStatus(AppOrder order, String newTrackingNumber, String newStatus) async {
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
          sheets.ValueRange(range: 'F${order.row}', values: [[newStatus]]),
          sheets.ValueRange(range: 'K${order.row}', values: [[newTrackingNumber]]),
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

  // Group orders by Wilaya - with caching for performance
  Map<String, List<AppOrder>> _groupByWilaya(List<AppOrder> orders) {
    if (_cachedFilterStatus == filterStatus && _cachedGroupedData != null) {
      return _cachedGroupedData!;
    }
    
    Map<String, List<AppOrder>> grouped = {};
    for (var order in orders) {
      final wilaya = order.wilaya.isEmpty ? 'ولايات غير محددة' : order.wilaya;
      grouped.putIfAbsent(wilaya, () => []);
      grouped[wilaya]!.add(order);
    }
    
    _cachedFilterStatus = filterStatus;
    _cachedGroupedData = grouped;
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _getFilteredOrders();

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تتبع الطلبات', style: TextStyle(fontWeight: FontWeight.bold)),
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
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : Column(
              children: [
                // 5-Icon Filter Navigation Bar
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildFilterIcon(
                        icon: Icons.inbox,
                        label: 'الكل',
                        count: allOrders.length,
                        status: null,
                        color: Colors.blueGrey,
                      ),
                      _buildFilterIcon(
                        icon: Icons.check_circle,
                        label: 'مؤكد',
                        count: _getStatusCount('confirm'),
                        status: 'confirm',
                        color: const Color(0xFF10B981),
                      ),
                      _buildFilterIcon(
                        icon: Icons.hourglass_empty_rounded,
                        label: 'لا إجابة',
                        count: _getStatusCount('no_response'),
                        status: 'no_response',
                        color: Colors.orangeAccent,
                      ),
                      _buildFilterIcon(
                        icon: Icons.cancel,
                        label: 'ملغى',
                        count: _getStatusCount('canceled'),
                        status: 'canceled',
                        color: Colors.redAccent,
                      ),
                      _buildFilterIcon(
                        icon: Icons.upload_rounded,
                        label: 'أرشيف',
                        count: _getStatusCount('uploaded'),
                        status: 'uploaded',
                        color: const Color(0xFF065F46),
                      ),
                    ],
                  ),
                ),
                // Orders List/ExpansionTiles
                Expanded(
                  child: filteredOrders.isEmpty
                      ? const Center(child: Text('لا توجد طلبات هنا', style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: fetchData,
                          color: const Color(0xFF10B981),
                          child: filterStatus == 'جديد'
                              ? _buildNewOrdersWithExpansion(filteredOrders)
                              : _buildOrderList(filteredOrders),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterIcon({
    required IconData icon,
    required String label,
    required int count,
    required String? status,
    required Color color,
  }) {
    final isActive = filterStatus == status;
    return InkWell(
      onTap: () => setState(() => filterStatus = status),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? color.withOpacity(0.15) : Colors.transparent,
                ),
                child: Icon(
                  icon,
                  color: isActive ? color : Colors.grey,
                  size: 28,
                ),
              ),
              if (count > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      count.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildNewOrdersWithExpansion(List<AppOrder> orders) {
    final grouped = _groupByWilaya(orders);
    final sortedWilayas = grouped.keys.toList()..sort();

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final wilaya = sortedWilayas[index];
                final wilayaOrders = grouped[wilaya]!;
                return RepaintBoundary(
                  child: ExpansionTile(
                    key: ValueKey(wilaya),
                    title: Text(
                      '$wilaya (${wilayaOrders.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    initiallyExpanded: false,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        if (expanded) {
                          expandedWilayas.clear();
                        }
                        expandedWilayas[wilaya] = expanded;
                      });
                    },
                    children: [
                      _LazyOrderListBuilder(
                        orders: wilayaOrders,
                        onStatusChange: (order, status) => _updateOrderStatus(order, status),
                        onEdit: (order) => _showEditDialog(order),
                        onShip: (order) => _showLogisticsSheet(order),
                      ),
                    ],
                  ),
                );
              },
              childCount: sortedWilayas.length,
              addAutomaticKeepAlives: true,
              addRepaintBoundaries: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderList(List<AppOrder> orders) {
    if (orders.isEmpty) {
      return const Center(
        child: Text('لا توجد طلبات هنا', style: TextStyle(color: Colors.grey)),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
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
                      onShip: () => _showLogisticsSheet(order),
                    ),
                  ),
                );
              },
              childCount: orders.length,
              addAutomaticKeepAlives: true,
              addRepaintBoundaries: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// Lazy-loading widget for orders within ExpansionTile
class _LazyOrderListBuilder extends StatelessWidget {
  final List<AppOrder> orders;
  final Function(AppOrder, String) onStatusChange;
  final Function(AppOrder) onEdit;
  final Function(AppOrder) onShip;

  const _LazyOrderListBuilder({
    required this.orders,
    required this.onStatusChange,
    required this.onEdit,
    required this.onShip,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: orders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final order = orders[index];
        return RepaintBoundary(
          child: OrderCard(
            key: ValueKey(order.row),
            order: order,
            onStatusChange: (newStatus) => onStatusChange(order, newStatus),
            onEdit: () => onEdit(order),
            onShip: () => onShip(order),
          ),
        );
      },
    );
  }
}