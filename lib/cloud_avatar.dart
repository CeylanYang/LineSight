import 'dart:convert';
import 'package:flutter/material.dart';

class CloudAvatar extends StatelessWidget {
  final Object? data;
  final double size;
  final Widget fallback;
  const CloudAvatar({
    super.key,
    this.data,
    required this.size,
    required this.fallback,
  });
  @override
  Widget build(BuildContext context) {
    if (data is! String || (data as String).isEmpty) return fallback;
    try {
      final bytes = base64Decode(data as String);
      return ClipOval(
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => fallback,
        ),
      );
    } on FormatException {
      return fallback;
    }
  }
}
