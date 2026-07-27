/// Canonical, controlled dataset of organization service areas — the
/// single source shared by organization setup, organization profile
/// editing, organization search, service-coverage filters, and
/// transporter/rescue matching wherever service areas are consulted.
/// Deliberately NOT a free-text field: an admin can only pick from this
/// list, never type a new area into existence (spec: "Do not allow
/// arbitrary new free-text service areas").
///
/// Scope is limited to the three regions currently supported by the
/// project (National Capital Region, CALABARZON / Region IV-A, Central
/// Luzon / Region III) — real cities and municipalities (component-city or
/// municipality level), never barangay-level entries.
library;

const String kRegionNCR = 'National Capital Region';
const String kRegionCalabarzon = 'CALABARZON / Region IV-A';
const String kRegionCentralLuzon = 'Central Luzon / Region III';

/// Regions in the fixed display order used everywhere this dataset is
/// grouped (e.g. the service-area picker sheet).
const List<String> kSupportedServiceAreaRegions = [
  kRegionNCR,
  kRegionCalabarzon,
  kRegionCentralLuzon,
];

class ServiceAreaOption {
  final String name;
  final String region;
  const ServiceAreaOption(this.name, this.region);
}

/// Every supported city/municipality, already alphabetically sorted within
/// its region below — callers should preserve this order (or re-sort by
/// `.name` if filtering) rather than re-deriving their own ordering.
const List<ServiceAreaOption> kSupportedServiceAreas = [
  // National Capital Region — all 16 cities + 1 municipality (Pateros).
  ServiceAreaOption('Caloocan', kRegionNCR),
  ServiceAreaOption('Las Piñas', kRegionNCR),
  ServiceAreaOption('Makati', kRegionNCR),
  ServiceAreaOption('Malabon', kRegionNCR),
  ServiceAreaOption('Mandaluyong', kRegionNCR),
  ServiceAreaOption('Manila', kRegionNCR),
  ServiceAreaOption('Marikina', kRegionNCR),
  ServiceAreaOption('Muntinlupa', kRegionNCR),
  ServiceAreaOption('Navotas', kRegionNCR),
  ServiceAreaOption('Parañaque', kRegionNCR),
  ServiceAreaOption('Pasay', kRegionNCR),
  ServiceAreaOption('Pasig', kRegionNCR),
  ServiceAreaOption('Pateros', kRegionNCR),
  ServiceAreaOption('Quezon City', kRegionNCR),
  ServiceAreaOption('San Juan', kRegionNCR),
  ServiceAreaOption('Taguig', kRegionNCR),
  ServiceAreaOption('Valenzuela', kRegionNCR),

  // CALABARZON / Region IV-A — major cities/municipalities across Cavite,
  // Laguna, Batangas, Rizal, and Quezon province.
  ServiceAreaOption('Antipolo', kRegionCalabarzon),
  ServiceAreaOption('Bacoor', kRegionCalabarzon),
  ServiceAreaOption('Batangas City', kRegionCalabarzon),
  ServiceAreaOption('Biñan', kRegionCalabarzon),
  ServiceAreaOption('Cabuyao', kRegionCalabarzon),
  ServiceAreaOption('Cainta', kRegionCalabarzon),
  ServiceAreaOption('Calamba', kRegionCalabarzon),
  ServiceAreaOption('Cavite City', kRegionCalabarzon),
  ServiceAreaOption('Dasmariñas', kRegionCalabarzon),
  ServiceAreaOption('General Trias', kRegionCalabarzon),
  ServiceAreaOption('Imus', kRegionCalabarzon),
  ServiceAreaOption('Lipa', kRegionCalabarzon),
  ServiceAreaOption('Lucena', kRegionCalabarzon),
  ServiceAreaOption('San Pablo', kRegionCalabarzon),
  ServiceAreaOption('San Pedro', kRegionCalabarzon),
  ServiceAreaOption('Santa Rosa', kRegionCalabarzon),
  ServiceAreaOption('Tagaytay', kRegionCalabarzon),
  ServiceAreaOption('Tanauan', kRegionCalabarzon),
  ServiceAreaOption('Tayabas', kRegionCalabarzon),
  ServiceAreaOption('Taytay', kRegionCalabarzon),
  ServiceAreaOption('Trece Martires', kRegionCalabarzon),

  // Central Luzon / Region III — major cities/municipalities across
  // Bulacan, Pampanga, Nueva Ecija, Tarlac, Zambales, Bataan, and Aurora.
  ServiceAreaOption('Angeles', kRegionCentralLuzon),
  ServiceAreaOption('Baler', kRegionCentralLuzon),
  ServiceAreaOption('Balanga', kRegionCentralLuzon),
  ServiceAreaOption('Cabanatuan', kRegionCentralLuzon),
  ServiceAreaOption('Gapan', kRegionCentralLuzon),
  ServiceAreaOption('Malolos', kRegionCentralLuzon),
  ServiceAreaOption('Meycauayan', kRegionCentralLuzon),
  ServiceAreaOption('Olongapo', kRegionCentralLuzon),
  ServiceAreaOption('Palayan', kRegionCentralLuzon),
  ServiceAreaOption('San Fernando (Pampanga)', kRegionCentralLuzon),
  ServiceAreaOption('San Jose (Nueva Ecija)', kRegionCentralLuzon),
  ServiceAreaOption('San Jose del Monte', kRegionCentralLuzon),
  ServiceAreaOption('Tarlac City', kRegionCentralLuzon),
];
