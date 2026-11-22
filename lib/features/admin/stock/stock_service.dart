import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';

/// Units a stock item or in-kind item can be counted in. Mirrored in
/// functions/campaigns.js (STOCK_UNITS) for campaign in-kind items.
const stockUnits = ['pcs', 'kg', 'g', 'L', 'mL', 'sacks', 'packs', 'boxes', 'cans', 'bottles'];

/// Donation gap 5: what the shelter has on hand, per organization.
///
/// `organizations/{orgId}/stock/{itemId}` with every change logged in
/// `organizations/{orgId}/stockMovements`. Received in-kind goods are added
/// by the backend (manageInKindDonation in functions/campaigns.js, item id
/// `inkind_<category>`); staff record usage, purchases and low-stock
/// levels on the Stock page. A food item at or below its level makes the
/// "Food & medicine" readiness factor read Constrained.

FirebaseFirestore get _db => FirebaseFirestore.instance;
DocumentReference<Map<String, dynamic>> _org(String orgId) => _db.collection('organizations').doc(orgId);

String get _actorName {
  final u = FirebaseAuth.instance.currentUser;
  return (u?.displayName?.trim().isNotEmpty ?? false) ? u!.displayName!.trim() : (u?.email ?? 'Staff');
}

class StockItem {
  final String id;
  final String name;
  final String category;
  final String unit;
  final double quantity;
  final double? lowStockThreshold;
  final DateTime? updatedAt;

  const StockItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.quantity,
    this.lowStockThreshold,
    this.updatedAt,
  });

  bool get isLow => lowStockThreshold != null && quantity <= lowStockThreshold!;
  bool get isFood => category.toLowerCase().contains('food') || name.toLowerCase().contains('food');

  /// Kilograms when the unit says so, else null (pieces, sacks... can't be
  /// turned into days of food without knowing their weight).
  double? get kilograms => const {'kg', 'kgs', 'kilo', 'kilos', 'kilogram', 'kilograms'}.contains(unit.toLowerCase())
      ? quantity
      : null;

  factory StockItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return StockItem(
      id: d.id,
      name: m['name'] as String? ?? d.id,
      category: m['category'] as String? ?? 'Others',
      unit: m['unit'] as String? ?? 'pcs',
      quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
      lowStockThreshold: (m['lowStockThreshold'] as num?)?.toDouble(),
      updatedAt: m['updatedAt'] is Timestamp ? (m['updatedAt'] as Timestamp).toDate() : null,
    );
  }
}

final stockItemsProvider = StreamProvider.autoDispose<List<StockItem>>((ref) async* {
  final orgId = await ref.watch(dashboardOrgIdProvider.future);
  if (orgId == null) {
    yield const [];
    return;
  }
  yield* _org(orgId).collection('stock').snapshots().map((s) {
    final list = s.docs.map(StockItem.fromFirestore).toList()..sort((a, b) => a.name.compareTo(b.name));
    return list;
  });
});

class StockService {
  StockService(this.organizationId);
  final String organizationId;

  CollectionReference<Map<String, dynamic>> get _stock => _org(organizationId).collection('stock');
  CollectionReference<Map<String, dynamic>> get _moves => _org(organizationId).collection('stockMovements');

  Future<void> addItem({
    required String name,
    required String category,
    required String unit,
    double quantity = 0,
    double? lowStockThreshold,
  }) async {
    final ref = _stock.doc();
    final batch = _db.batch();
    batch.set(ref, {
      'name': name,
      'category': category,
      'unit': unit,
      'quantity': quantity,
      'lowStockThreshold': lowStockThreshold,
      'organizationId': organizationId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser?.uid,
    });
    if (quantity != 0) _logMove(batch, ref.id, name, quantity, 'opening');
    await batch.commit();
  }

  /// [change] > 0 for purchases or corrections up, < 0 for usage. Usage can't
  /// take the quantity below zero.
  Future<void> adjust(StockItem item, double change, {required String kind, String? note}) async {
    await _db.runTransaction((tx) async {
      final ref = _stock.doc(item.id);
      final snap = await tx.get(ref);
      final current = (snap.data()?['quantity'] as num?)?.toDouble() ?? 0;
      if (current + change < -0.0001) {
        throw StateError('Only ${_fmt(current)} ${item.unit} of ${item.name} is in stock.');
      }
      tx.update(ref, {
        'quantity': FieldValue.increment(change),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      });
      tx.set(_moves.doc(), _move(item.id, item.name, change, kind, note));
    });
  }

  Future<void> setThreshold(StockItem item, double? threshold) =>
      _stock.doc(item.id).update({'lowStockThreshold': threshold, 'updatedAt': FieldValue.serverTimestamp()});

  void _logMove(WriteBatch b, String id, String name, double change, String kind) =>
      b.set(_moves.doc(), _move(id, name, change, kind, null));

  Map<String, dynamic> _move(String id, String name, double change, String kind, String? note) => {
    'itemId': id,
    'itemName': name,
    'change': change,
    'kind': kind, // opening | received | purchased | used | correction
    'note': note,
    'organizationId': organizationId,
    'byUid': FirebaseAuth.instance.currentUser?.uid,
    'byName': _actorName,
    'at': FieldValue.serverTimestamp(),
  };

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
