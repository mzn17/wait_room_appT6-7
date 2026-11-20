import 'sync_status.dart';

class Client {
  final String id;
  final String name;

  /// The waiting room this registration belongs to.
  final String? tenantId;

  /// Auth user who created this registration (null for legacy rows).
  final String? registeredBy;

  /// Assigned by Supabase. Null while the registration is only local.
  final int? queueNumber;

  /// Precise coordinates: only ever present on this device's own records.
  final double? lat;
  final double? lng;
  final double? locationAccuracy;

  /// True when the server knows a location was captured (coordinates stay private).
  final bool serverHasLocation;
  final DateTime createdAt;
  final SyncStatus syncStatus;

  const Client({
    required this.id,
    required this.name,
    this.tenantId,
    this.registeredBy,
    this.queueNumber,
    this.lat,
    this.lng,
    this.locationAccuracy,
    this.serverHasLocation = false,
    required this.createdAt,
    this.syncStatus = SyncStatus.synced,
  });

  bool get hasLocation => (lat != null && lng != null) || serverHasLocation;

  bool isMine(String? userId) =>
      userId != null && registeredBy != null && registeredBy == userId;

  String get locationText {
    if (lat != null && lng != null) {
      return '${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}';
    }
    return serverHasLocation ? 'Location shared' : 'Location not captured';
  }

  Client copyWith({SyncStatus? syncStatus}) => Client(
        id: id,
        name: name,
        tenantId: tenantId,
        registeredBy: registeredBy,
        queueNumber: queueNumber,
        lat: lat,
        lng: lng,
        locationAccuracy: locationAccuracy,
        serverHasLocation: serverHasLocation,
        createdAt: createdAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );

  /// Business data only (no local sync metadata).
  Map<String, dynamic> toSupabaseMap() => {
        'id': id,
        'tenant_id': tenantId,
        'registered_by': registeredBy,
        'name': name,
        'lat': lat,
        'lng': lng,
        'location_accuracy_m': locationAccuracy,
        'created_at': createdAt.toIso8601String(),
      };

  /// SQLite row, includes local sync status.
  Map<String, dynamic> toLocalMap() => {
        'id': id,
        'tenant_id': tenantId,
        'registered_by': registeredBy,
        'name': name,
        'lat': lat,
        'lng': lng,
        'location_accuracy_m': locationAccuracy,
        'created_at': createdAt.toIso8601String(),
        'sync_status': syncStatus.name,
      };

  factory Client.fromSupabaseMap(Map<String, dynamic> map) => Client(
        id: map['id'].toString(),
        name: map['name'] as String,
        tenantId: map['tenant_id']?.toString(),
        registeredBy: map['registered_by']?.toString(),
        queueNumber: (map['queue_number'] as num?)?.toInt(),
        serverHasLocation: (map['has_location'] as bool?) ?? false,
        createdAt: DateTime.parse(map['created_at'] as String),
        syncStatus: SyncStatus.synced,
      );

  factory Client.fromLocalMap(Map<String, dynamic> map) => Client(
        id: map['id'] as String,
        name: map['name'] as String,
        tenantId: map['tenant_id'] as String?,
        registeredBy: map['registered_by'] as String?,
        lat: (map['lat'] as num?)?.toDouble(),
        lng: (map['lng'] as num?)?.toDouble(),
        locationAccuracy: (map['location_accuracy_m'] as num?)?.toDouble(),
        createdAt: DateTime.parse(map['created_at'] as String),
        syncStatus: SyncStatus.values.firstWhere(
          (s) => s.name == map['sync_status'],
          orElse: () => SyncStatus.pending,
        ),
      );
}
