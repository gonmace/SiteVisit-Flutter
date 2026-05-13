import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

class DeviceService {
  final _plugin = DeviceInfoPlugin();
  static const _channel = MethodChannel('cl.sitevisit.app/device');

  Future<String> getFingerprint() async {
    final info = await _plugin.androidInfo;
    final raw = '${info.id}|${info.model}|${info.manufacturer}|${info.fingerprint}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  Future<Map<String, String>> getDeviceInfo() async {
    final info = await _plugin.androidInfo;
    return {
      'manufacturer': info.manufacturer,
      'model':        info.model,
      'os_version':   info.version.release,
    };
  }

  Future<Map<String, String>> getDeviceIdentifiers() async {
    try {
      final androidId = await _channel.invokeMethod<String>('getAndroidId') ?? '';
      return {'android_id': androidId};
    } catch (_) {
      return {'android_id': ''};
    }
  }
}
