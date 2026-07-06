/*import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/ndef_record.dart';        // NdefRecord, NdefMessage, TypeNameFormat
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart'; // Ndef.from(), ndef.write()


class NfcService {
  // ── Availability ───────────────────────────────────────────────────────────

  Future<bool> isAvailable() async {
    try {
      final status = await NfcManager.instance.checkAvailability();
      return status == NfcAvailability.enabled;
    } catch (_) {
      return false;
    }
  }

  // ── Write ──────────────────────────────────────────────────────────────────

  Future<void> writeTag(String tagId) async {
    await NfcManager.instance.startSession(
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (NfcTag tag) async {
        try {
          // Ndef.from() comes from nfc_manager_ndef
          final ndef = Ndef.from(tag);

          if (ndef == null) {
            throw Exception('This tag does not support NDEF.');
          }

          if (!ndef.isWritable) {
            throw Exception('This NFC tag is read-only.');
          }

          final payload = Uint8List.fromList([
            0x04, // "https://" prefix code
            ...'respawnd.app/tag/$tagId'.codeUnits,
          ]);

          final record = NdefRecord(
            typeNameFormat: TypeNameFormat.wellKnown,
            type: Uint8List.fromList([0x55]), // 'U' = URI record type
            identifier: Uint8List(0),
            payload: payload,
          );

          await ndef.write(
            message: NdefMessage(records: [record]),
          );

          await FirebaseFirestore.instance
              .collection('collarTags')
              .doc(tagId)
              .update({
            'nfcWritten': true,
            'nfcWrittenAt': FieldValue.serverTimestamp(),
          });

          await NfcManager.instance.stopSession();
        } catch (e) {
          await NfcManager.instance.stopSession(
          );
          rethrow;
        }
      },
    );
  }

  Future<String?> readTag() async {
    String? result;

    await NfcManager.instance.startSession(
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (NfcTag tag) async {
        try {
          final ndef = Ndef.from(tag);

          if (ndef == null) {
            throw Exception('Tag does not support NDEF.');
          }

          final message = ndef.cachedMessage ?? await ndef.read();

          if (message == null || message.records.isEmpty) {
            throw Exception('No NDEF records found on this tag.');
          }

          final record = message.records.first;

          if (record.payload.isEmpty) {
            throw Exception('Empty record payload.');
          }

          // Decode URI prefix byte back to scheme string
          const prefixMap = {
            0x00: '',
            0x01: 'http://www.',
            0x02: 'https://www.',
            0x03: 'http://',
            0x04: 'https://',
          };
          final prefixCode = record.payload[0];
          final prefix = prefixMap[prefixCode] ?? '';
          final rest = String.fromCharCodes(record.payload.sublist(1));
          result = '$prefix$rest';

          await NfcManager.instance.stopSession();
        } catch (e) {
          await NfcManager.instance.stopSession(
          );
          rethrow;
        }
      },
    );

    return result;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String? extractTagId(String url) {
    final uri = Uri.tryParse(url);
    final segments = uri?.pathSegments ?? [];
    if (segments.length >= 2 && segments[segments.length - 2] == 'tag') {
      return segments.last;
    }
    return null;
  }

  Future<void> stopSession() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }
}*/