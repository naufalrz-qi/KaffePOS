import 'dart:convert';
import 'dart:typed_data';

class Staff {
  Staff(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        role = j['role'] as String,
        pinHash = j['pin_hash'] as String? ?? '',
        canDiscount = j['can_discount'] == true;

  final String id, name, role, pinHash;
  final bool canDiscount;

  bool get isManager => role == 'OWNER' || role == 'MANAGER';
}

class MenuCategory {
  MenuCategory(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String;

  final String id, name;
}

class ModOption {
  ModOption(Map<String, dynamic> j, this.groupName)
      : id = j['id'] as String,
        name = j['name'] as String,
        priceDelta = j['price_delta'] as int;

  final String id, name, groupName;
  final int priceDelta;
}

class ModGroup {
  ModGroup(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        required = j['required'] == true,
        multi = j['multi'] == true,
        options = [
          for (final o in (j['options'] as List).cast<Map<String, dynamic>>()) ModOption(o, j['name'] as String),
        ];

  final String id, name;
  final bool required, multi;
  final List<ModOption> options;
}

class Product {
  Product(Map<String, dynamic> j)
      : id = j['id'] as String,
        categoryId = j['category_id'] as String,
        name = j['name'] as String,
        price = j['price'] as int,
        earnsStamp = j['earns_stamp'] == true,
        groupIds = (j['modifier_group_ids'] as List).cast<String>();

  final String id, categoryId, name;
  final int price;
  final bool earnsStamp;
  final List<String> groupIds;
}

class Outlet {
  Outlet(Map<String, dynamic> j)
      : id = j['id'] as String,
        code = j['code'] as String,
        name = j['name'] as String,
        type = j['type'] as String,
        timezone = j['timezone'] as String,
        taxEnabled = j['tax_enabled'] == true,
        taxRateBp = j['tax_rate_bp'] as int,
        taxInclusive = j['tax_inclusive'] == true,
        roundingUnit = j['rounding_unit'] as int,
        voidNeedsManager = j['void_needs_manager'] == true,
        receiptHeader = j['receipt_header'] as String? ?? '',
        receiptFooter = j['receipt_footer'] as String? ?? '',
        qrisImage = j['qris_image'] == null ? null : base64.decode(j['qris_image'] as String);

  final String id, code, name, type, timezone, receiptHeader, receiptFooter;
  final bool taxEnabled, taxInclusive, voidNeedsManager;
  final int taxRateBp, roundingUnit;
  final Uint8List? qrisImage;

  /// Setting pajak & pembulatan yang ikut dikirim di setiap penjualan (`pricing`, desain §5).
  Map<String, Object> get pricing =>
      {'tax_enabled': taxEnabled, 'tax_rate_bp': taxRateBp, 'tax_inclusive': taxInclusive, 'rounding_unit': roundingUnit};
}

/// Snapshot master data dari GET /sync/master (desain §5). Diganti utuh saat versinya berubah.
class Snapshot {
  Snapshot(this.version, Map<String, dynamic> j)
      : minAppVersion = j['min_app_version'] as String? ?? '0.0.0',
        businessName = (j['business'] as Map)['name'] as String,
        businessFooter = (j['business'] as Map)['receipt_footer'] as String? ?? '',
        outlet = Outlet(j['outlet'] as Map<String, dynamic>),
        deviceNo = (j['device'] as Map)['number'] as int,
        staff = [for (final s in (j['staff'] as List).cast<Map<String, dynamic>>()) Staff(s)],
        categories = [for (final c in (j['categories'] as List).cast<Map<String, dynamic>>()) MenuCategory(c)],
        products = [for (final p in (j['products'] as List).cast<Map<String, dynamic>>()) Product(p)],
        groups = {
          for (final g in (j['modifier_groups'] as List).cast<Map<String, dynamic>>()) g['id'] as String: ModGroup(g),
        },
        paymentMethods = (j['payment_methods'] as List).cast<String>();

  factory Snapshot.parse(int version, String json) => Snapshot(version, jsonDecode(json) as Map<String, dynamic>);

  final int version, deviceNo;
  final String minAppVersion, businessName, businessFooter;
  final Outlet outlet;
  final List<Staff> staff;
  final List<MenuCategory> categories;
  final List<Product> products;
  final Map<String, ModGroup> groups;
  final List<String> paymentMethods;

  Staff? staffById(String id) {
    for (final s in staff) {
      if (s.id == id) return s;
    }
    return null;
  }

  String categoryName(String id) {
    for (final c in categories) {
      if (c.id == id) return c.name;
    }
    return '';
  }

  /// Grup modifier milik produk, dengan urutan sesuai server.
  List<ModGroup> groupsOf(Product p) => [for (final id in p.groupIds) if (groups.containsKey(id)) groups[id]!];
}
