import 'package:flutter/material.dart';

/// Representa uma conexão (cabo) entre dois nós no canvas
class CableTie {
  final String id;
  final String fromNodeId;
  final String toNodeId;
  final String? label;
  final Color? color;
  final bool isFlowing;

  CableTie({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    this.label,
    this.color,
    this.isFlowing = false,
  });

  factory CableTie.fromJson(Map<String, dynamic> json) {
    return CableTie(
      id: json['id'] ?? '',
      fromNodeId: json['from'] ?? json['fromNodeId'] ?? '',
      toNodeId: json['to'] ?? json['toNodeId'] ?? '',
      label: json['label'],
      isFlowing: json['flowing'] ?? json['isFlowing'] ?? false,
    );
  }
}
