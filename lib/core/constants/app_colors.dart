import 'package:flutter/material.dart';

/// Paleta de cores oficial e refinada no estilo macOS Sequoia / Maestri Dark Theme.
class AppColors {
  // Backgrounds profundos (Obsidian & Deep Space)
  static const Color background = Color(0xFF090A0E);
  static const Color surface = Color(0xFF12141C);
  static const Color surfaceElevated = Color(0xFF191B26);
  static const Color surfaceHover = Color(0xFF222533);

  // Bordas e Divisores (Vidro sutil)
  static const Color border = Color(0xFF262838);
  static const Color borderHighlight = Color(0xFF383C52);

  // Acentos de Destaque Mac
  static const Color electricCobalt = Color(0xFF1633F9);
  static const Color neonCobalt = Color(0xFF1633F9);
  static const Color neonViolet = Color(0xFF9653F4);
  static const Color gradientStart = Color(0xFF1633F9);
  static const Color gradientEnd = Color(0xFF9653F4);

  // Status de Agentes e Terminais
  static const Color statusActive = Color(0xFF10B981); // Verde Esmeralda (Online / Running)
  static const Color statusBusy = Color(0xFF3B82F6);   // Azul (Thinking / Working)
  static const Color statusAlert = Color(0xFFEF4444);  // Vermelho Coral (Attention / Error)
  static const Color statusWarning = Color(0xFFF59E0B);// Âmbar (Review / Conflicted)
  static const Color statusIdle = Color(0xFF6B7280);   // Cinza (Dormant / Standby)

  // Tipografia
  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textAccent = Color(0xFFA78BFA);

  // Canvas Grid & Cabos
  static const Color canvasGridDots = Color(0xFF1F2230);
  static const Color cableBase = Color(0xFF3B4058);
  static const Color cableActive = Color(0xFF9653F4);
  static const Color cableGlow = Color(0x669653F4);

  // Terminal Cores
  static const Color terminalBg = Color(0xFF0D0E14);
  static const Color terminalCursor = Color(0xFF10B981);
}
