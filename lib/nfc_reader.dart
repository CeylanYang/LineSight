import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'collaboration_api.dart';

class NfcCardRead {
  final String code, technology;
  const NfcCardRead(this.code, this.technology);
}

String nfcCardCode(List<int> id, {List<int>? ndef}) => sha256.convert([
  ...utf8.encode(ndef == null ? 'linesight-uid-v1:' : 'linesight-ndef-v1:'),
  ...(ndef ?? id),
]).toString();

class NfcCardReader {
  Completer<NfcCardRead?>? pending;
  Timer? timeout;
  bool reading = false;
  int generation = 0;
  Future<NfcCardRead?> scan({bool initializeEmptyCard = false}) async {
    if (pending != null) return pending!.future;
    final ticket = generation;
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw const CollaborationApiException(400, '请在支持NFC的Android手机上使用');
    }
    final available = await NfcManager.instance.checkAvailability();
    if (ticket != generation) return null;
    if (available != NfcAvailability.enabled) {
      throw CollaborationApiException(
        400,
        available == NfcAvailability.disabled ? '请在手机设置中开启NFC' : '此手机不支持NFC',
      );
    }
    final result = Completer<NfcCardRead?>();
    pending = result;
    try {
      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (tag) async {
          if (reading || result.isCompleted || ticket != generation) return;
          reading = true;
          try {
            final android = NfcTagAndroid.from(tag);
            if (android == null || android.id.isEmpty) {
              throw const CollaborationApiException(400, '无法读取此卡片，请重试');
            }
            final ndef = NdefAndroid.from(tag);
            List<int>? marker;
            if (ndef != null) {
              final message = await ndef.getNdefMessage();
              for (final record in message?.records ?? <NdefRecord>[]) {
                if (record.typeNameFormat == TypeNameFormat.external &&
                    utf8.decode(record.type, allowMalformed: true) ==
                        'linesight.app:card' &&
                    record.payload.length == 32) {
                  marker = record.payload;
                }
              }
              if (marker == null &&
                  initializeEmptyCard &&
                  ndef.isWritable &&
                  (message == null || message.records.isEmpty)) {
                marker = List.generate(32, (_) => Random.secure().nextInt(256));
                await ndef.writeNdefMessage(
                  NdefMessage(
                    records: [
                      NdefRecord(
                        typeNameFormat: TypeNameFormat.external,
                        type: Uint8List.fromList(
                          utf8.encode('linesight.app:card'),
                        ),
                        identifier: Uint8List(0),
                        payload: Uint8List.fromList(marker),
                      ),
                    ],
                  ),
                );
              }
            }
            if (!result.isCompleted) {
              result.complete(
                NfcCardRead(
                  nfcCardCode(android.id, ndef: marker),
                  android.techList
                      .map((name) => name.split('.').last)
                      .join(', '),
                ),
              );
            }
          } catch (error) {
            if (!result.isCompleted) {
              result.completeError(
                error is CollaborationApiException
                    ? error
                    : const CollaborationApiException(400, '无法读取此卡片，请重试'),
              );
            }
          } finally {
            await stop();
          }
        },
      );
      if (result.isCompleted || ticket != generation) {
        return await result.future;
      }
      timeout = Timer(const Duration(seconds: 30), () {
        if (!result.isCompleted) {
          result.completeError(
            const CollaborationApiException(408, '读卡超时，请重新扫描'),
          );
        }
        stop();
      });
      return await result.future;
    } finally {
      await stop();
    }
  }

  Future<void> stop() async {
    generation++;
    timeout?.cancel();
    timeout = null;
    final current = pending;
    pending = null;
    reading = false;
    if (current != null && !current.isCompleted) current.complete(null);
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {
      /* Already stopped by the platform. */
    }
  }
}
