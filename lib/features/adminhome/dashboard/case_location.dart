/// Analytics gap 4: which barangay and city/municipality a report came
/// from, read from its saved address.
///
/// Reports store Google's formatted address (rescue_geocoding_service.dart),
/// which in the Philippines reads
/// "[street], [barangay], [city or municipality], [postal code] [province],
/// Philippines". From the end: country, then province, then city, then
/// barangay. An address too short to tell is left out, never guessed.
({String? barangay, String? city}) placeOf(String? address) {
  if (address == null) return (barangay: null, city: null);
  var parts = address
      .split(',')
      .map((p) => p.trim())
      // Plus codes ("QRX2+5F") and bare postal codes say nothing here.
      .where((p) => p.isNotEmpty && !RegExp(r'^[A-Z0-9]{4,}\+[A-Z0-9]{2,}').hasMatch(p))
      .map((p) => p.replaceFirst(RegExp(r'^\d{4}\s+'), '').replaceFirst(RegExp(r'\s+\d{4}$'), '').trim())
      .where((p) => p.isNotEmpty && !RegExp(r'^\d+$').hasMatch(p))
      .toList();
  if (parts.isNotEmpty && parts.last.toLowerCase() == 'philippines') parts = parts.sublist(0, parts.length - 1);

  // An explicit "Brgy." / "Barangay" part wins wherever it sits.
  final brgyIndex = parts.indexWhere((p) => RegExp(r'^(brgy\.?|bgy\.?|barangay)\s', caseSensitive: false).hasMatch(p));

  if (parts.isEmpty) return (barangay: null, city: null);
  if (parts.length < 2) {
    return (barangay: brgyIndex == 0 ? _cleanBarangay(parts[0]) : null, city: null);
  }
  final cityIndex = parts.length - 2; // last is the province
  final city = parts[cityIndex];
  String? barangay;
  if (brgyIndex >= 0 && brgyIndex != cityIndex) {
    barangay = _cleanBarangay(parts[brgyIndex]);
  } else if (parts.length >= 3) {
    final candidate = parts[cityIndex - 1];
    // A street ("123 Mabini St") is not a barangay.
    if (!RegExp(r'^\d|\b(st|street|ave|avenue|road|rd|blvd|highway|hwy)\.?$', caseSensitive: false).hasMatch(candidate)) {
      barangay = candidate;
    }
  }
  return (barangay: barangay, city: city);
}

String _cleanBarangay(String p) =>
    p.replaceFirst(RegExp(r'^(brgy\.?|bgy\.?|barangay)\s+', caseSensitive: false), '').trim();
