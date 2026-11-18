import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/ndef_record.dart'; // NdefMessage, NdefRecord, TypeNameFormat
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
import 'package:respawnd1/core/constants/app.links.dart';

/// A problem the user should see (bad chip, timeout, nothing written, ...).
class NfcException implements Exception {
  const NfcException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The user cancelled the scan (Cancel button, or closed the iOS sheet).
class NfcCancelledException extends NfcException {
  const NfcCancelledException() : super('NFC scan cancelled.');
}

/// Reads and writes collar tag chips.
///
/// A chip holds one NDEF URI record: the same link the QR code uses
/// ([AppLinks.tagUrl]), so a scanned chip goes through the same lookup as a
/// scanned QR code and a phone tapping it outside the app opens the tag page.
///
/// In nfc_manager 4.x `startSession` returns as soon as the session opens,
/// not when a tag is tapped. Each call below therefore waits on a [Completer]
/// that the tag callback completes, so callers get the real result or the
/// real error.
class NfcService {
  static const _defaultTimeout = Duration(seconds: 30);

  Completer<Object?>? _pending;

  Future<bool> isAvailable() async {
    try {
      final status = await NfcManager.instance.checkAvailability();
      return status == NfcAvailability.enabled;
    } catch (_) {
      return false;
    }
  }

  /// Writes the tag's link to the next chip tapped, then marks the collar tag
  /// as written in Firestore. Completes only after the chip is written.
  Future<void> writeTag(String tagId, {Duration timeout = _defaultTimeout}) async {
    final url = AppLinks.tagUrl(tagId);
    final message = NdefMessage(records: [_uriRecord(url)]);

    await _runSession(
      timeout: timeout,
      alertMessageIos: 'Hold the NFC chip near the top of your iPhone.',
      successMessageIos: 'Chip written.',
      onTag: (tag) async {
        await _writeMessage(tag, message);
        return null;
      },
    );

    // The chip is written; the NFC session is closed before this runs.
    try {
      await FirebaseFirestore.instance.collection('collarTags').doc(tagId).update({
        'nfcWritten': true,
        'nfcWrittenAt': FieldValue.serverTimestamp(),
        'nfcUrl': url,
      });
    } catch (e) {
      throw NfcException(
        'The chip was written, but saving its status failed: $e',
      );
    }
  }

  /// Reads the next chip tapped and returns what is written on it (normally
  /// the tag link). Pass the result to [AppLinks.tagIdFromScan].
  Future<String> readTag({Duration timeout = _defaultTimeout}) async {
    final result = await _runSession(
      timeout: timeout,
      alertMessageIos: 'Hold the pet\'s collar tag near the top of your iPhone.',
      successMessageIos: 'Tag read.',
      onTag: _readText,
    );
    return result as String;
  }

  /// Cancels a read or write that is waiting for a chip.
  Future<void> stopSession() async {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const NfcCancelledException());
    }
    await _safeStop();
  }

  /// Extracts the collar tag ID from a tag link.
  String? extractTagId(String url) => AppLinks.tagIdFromScan(url);

  // ── Session ────────────────────────────────────────────────────────────────

  Future<Object?> _runSession({
    required Duration timeout,
    required String alertMessageIos,
    required String successMessageIos,
    required Future<Object?> Function(NfcTag tag) onTag,
  }) async {
    if (!await isAvailable()) {
      throw const NfcException('NFC is not available or is turned off on this device.');
    }

    // Only one session at a time: cancel anything left over.
    await stopSession();

    final completer = Completer<Object?>();
    _pending = completer;

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        alertMessageIos: alertMessageIos,
        onDiscovered: (NfcTag tag) async {
          if (completer.isCompleted) return; // a second tap after we finished
          try {
            final value = await onTag(tag);
            await _safeStop(alertMessageIos: successMessageIos);
            if (!completer.isCompleted) completer.complete(value);
          } catch (e) {
            final error = e is NfcException ? e : NfcException(_describe(e));
            await _safeStop(errorMessageIos: error.message);
            if (!completer.isCompleted) completer.completeError(error);
          }
        },
        // iOS only: the system sheet was closed, timed out or failed.
        onSessionErrorIos: (error) {
          if (completer.isCompleted) return;
          final cancelled = error.code.name.toLowerCase().contains('usercanceled');
          completer.completeError(
            cancelled ? const NfcCancelledException() : NfcException(error.message),
          );
        },
      );
    } catch (e) {
      _pending = null;
      throw NfcException('Could not start NFC: ${_describe(e)}');
    }

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      await _safeStop(errorMessageIos: 'No chip detected.');
      throw const NfcException(
        'No chip detected. Hold the chip flat against the back of the phone and try again.',
      );
    } finally {
      if (identical(_pending, completer)) _pending = null;
    }
  }

  Future<void> _safeStop({String? alertMessageIos, String? errorMessageIos}) async {
    try {
      await NfcManager.instance.stopSession(
        alertMessageIos: alertMessageIos,
        errorMessageIos: errorMessageIos,
      );
    } catch (_) {
      // No session running.
    }
  }

  // ── Write ──────────────────────────────────────────────────────────────────

  Future<void> _writeMessage(NfcTag tag, NdefMessage message) async {
    final ndef = Ndef.from(tag);
    if (ndef != null) {
      if (!ndef.isWritable) {
        throw const NfcException('This chip is locked (read-only). Use a new chip.');
      }
      if (ndef.maxSize > 0 && message.byteLength > ndef.maxSize) {
        throw NfcException(
          'This chip is too small (${ndef.maxSize} bytes, needs '
              '${message.byteLength}). Use an NTAG213/215/216 chip.',
        );
      }
      await ndef.write(message: message);
      return;
    }

    // Brand-new chips are often not NDEF-formatted yet. Android can format
    // them and write the record in one step.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final formatable = NdefFormatableAndroid.from(tag);
      if (formatable != null) {
        await formatable.format(message);
        return;
      }
    }

    throw const NfcException(
      'This chip type is not supported. Use an NTAG213, NTAG215 or NTAG216 chip.',
    );
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  Future<String> _readText(NfcTag tag) async {
    final ndef = Ndef.from(tag);
    if (ndef == null) {
      throw const NfcException('This chip has no pet tag written on it.');
    }

    final message = ndef.cachedMessage ?? await ndef.read();
    if (message == null || message.records.isEmpty) {
      throw const NfcException('This chip is empty. No pet tag is written on it.');
    }

    for (final record in message.records) {
      final uri = _decodeUri(record);
      if (uri != null) return uri;
    }
    for (final record in message.records) {
      final text = _decodeText(record);
      if (text != null) return text;
    }
    throw const NfcException('This chip does not hold a pet tag link.');
  }

  // ── NDEF records ───────────────────────────────────────────────────────────

  /// URI identifier codes from the NFC Forum URI Record Type Definition.
  static const _uriPrefixes = <String>[
    '', 'http://www.', 'https://www.', 'http://', 'https://', 'tel:',
    'mailto:', 'ftp://anonymous:anonymous@', 'ftp://ftp.', 'ftps://',
    'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://', 'news:',
    'telnet://', 'imap:', 'rtsp://', 'urn:', 'pop:', 'sip:', 'sips:',
    'tftp:', 'btspp://', 'btl2cap://', 'btgoep://', 'tcpobex://',
    'irdaobex://', 'file://', 'urn:epc:id:', 'urn:epc:tag:',
    'urn:epc:pat:', 'urn:epc:raw:', 'urn:epc:', 'urn:nfc:',
  ];

  static NdefRecord _uriRecord(String uri) {
    // Longest matching prefix wins (e.g. https://www. before https://).
    var code = 0;
    for (var i = 1; i < _uriPrefixes.length; i++) {
      if (uri.startsWith(_uriPrefixes[i]) &&
          _uriPrefixes[i].length > _uriPrefixes[code].length) {
        code = i;
      }
    }
    final rest = uri.substring(_uriPrefixes[code].length);

    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList([0x55]), // 'U'
      identifier: Uint8List(0),
      payload: Uint8List.fromList([code, ...utf8.encode(rest)]),
    );
  }

  static String? _decodeUri(NdefRecord record) {
    if (record.payload.isEmpty) return null;
    if (record.typeNameFormat == TypeNameFormat.absoluteUri) {
      return utf8.decode(record.payload, allowMalformed: true);
    }
    final isUri = record.typeNameFormat == TypeNameFormat.wellKnown &&
        record.type.length == 1 &&
        record.type.first == 0x55;
    if (!isUri) return null;

    final code = record.payload.first;
    final prefix = code < _uriPrefixes.length ? _uriPrefixes[code] : '';
    return prefix + utf8.decode(record.payload.sublist(1), allowMalformed: true);
  }

  static String? _decodeText(NdefRecord record) {
    final isText = record.typeNameFormat == TypeNameFormat.wellKnown &&
        record.type.length == 1 &&
        record.type.first == 0x54; // 'T'
    if (!isText || record.payload.isEmpty) return null;

    final status = record.payload.first;
    if ((status & 0x80) != 0) return null; // UTF-16 text: not something we write
    final langLength = status & 0x3F;
    if (record.payload.length <= 1 + langLength) return null;
    return utf8.decode(record.payload.sublist(1 + langLength), allowMalformed: true);
  }

  static String _describe(Object e) {
    final text = e.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }
}
