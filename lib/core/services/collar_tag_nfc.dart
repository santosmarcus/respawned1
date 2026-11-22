import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

import 'package:respawnd1/core/constants/app.links.dart';

/// NFC for collar tags. A chip holds one NDEF URI record with the tag link
/// (AppLinks.tagUrl), the same link the QR code carries: a phone without
/// the app opens public/tag/index.html, and the in-app scanner reads the
/// link and opens the same collar tag view.
class CollarTagNfc {
  CollarTagNfc._();

  static Future<bool> isAvailable() async {
    try {
      return await FlutterNfcKit.nfcAvailability == NFCAvailability.available;
    } catch (_) {
      return false;
    }
  }

  /// Waits for a chip and writes [tagId]'s link onto it.
  static Future<void> writeTag(String tagId, {Duration timeout = const Duration(seconds: 20)}) async {
    try {
      final chip = await FlutterNfcKit.poll(
        timeout: timeout,
        iosAlertMessage: 'Hold your iPhone near the collar tag chip',
      );
      if (chip.ndefAvailable != true) {
        throw Exception('This chip does not support NDEF.');
      }
      if (chip.ndefWritable != true) {
        throw Exception('This chip is read-only.');
      }
      await FlutterNfcKit.writeNDEFRecords([
        ndef.UriRecord.fromUri(Uri.parse(AppLinks.tagUrl(tagId))),
      ]);
      await FlutterNfcKit.finish(iosAlertMessage: 'Collar tag written');
    } catch (e) {
      try {
        await FlutterNfcKit.finish(iosErrorMessage: 'Could not write the chip');
      } catch (_) {}
      rethrow;
    }
  }

  /// Waits for a chip and returns what it holds: the first URI or text
  /// record when it has one (a collar tag link), else the chip's id.
  static Future<String> readTag({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final chip = await FlutterNfcKit.poll(timeout: timeout);
      String? value;
      if (chip.ndefAvailable == true) {
        try {
          for (final record in await FlutterNfcKit.readNDEFRecords()) {
            if (record is ndef.UriRecord && (record.uriString?.isNotEmpty ?? false)) {
              value = record.uriString;
              break;
            }
            if (record is ndef.TextRecord && (record.text?.isNotEmpty ?? false)) {
              value = record.text;
              break;
            }
          }
        } catch (_) {
          // Unreadable NDEF: fall back to the chip id.
        }
      }
      await FlutterNfcKit.finish();
      return value ?? chip.id;
    } catch (e) {
      try {
        await FlutterNfcKit.finish();
      } catch (_) {}
      rethrow;
    }
  }
}
