import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/mac_theme.dart';
import '../../models/pair_data.dart';
import '../../state/wire_controller.dart';

/// Tela de Pareamento com o Servidor Linux via QR Code ou Entrada Manual
class PairScreen extends StatefulWidget {
  final WireController controller;
  final VoidCallback onPairedSuccess;

  const PairScreen({
    Key? key,
    required this.controller,
    required this.onPairedSuccess,
  }) : super(key: key);

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MobileScannerController _scannerController = MobileScannerController();
  final TextEditingController _hostController = TextEditingController(text: '100.82.41.95');
  final TextEditingController _portController = TextEditingController(text: '7434');
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _deviceNameController = TextEditingController(text: 'Android Client');

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (image == null) return;

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final BarcodeCapture? barcodes = await _scannerController.analyzeImage(image.path);

      if (barcodes != null && barcodes.barcodes.isNotEmpty) {
        await _handleQrDetected(barcodes);
      } else {
        setState(() {
          _errorMessage = 'Nenhum QR Code do Maestri detectado no print selecionado. Verifique se o código está nítido na imagem ou use a aba manual.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao processar imagem da galeria: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleQrDetected(BarcodeCapture capture) async {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final pairData = PairData.fromQrString(rawValue);
      final success = await widget.controller.pairWithHost(
        pairData: pairData,
        deviceName: _deviceNameController.text.trim(),
        code: pairData.pairingCode,
      );

      if (success) {
        widget.onPairedSuccess();
      } else {
        setState(() {
          _errorMessage = widget.controller.errorMessage ?? 'Falha no pareamento.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'QR Code inválido: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleManualPair() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 7434;
    final code = _codeController.text.trim();
    final password = _passwordController.text.trim();

    if (host.isEmpty) {
      setState(() => _errorMessage = 'Informe o IP ou Host do Linux.');
      return;
    }
    if (code.isEmpty && password.isEmpty) {
      setState(() => _errorMessage = 'Informe o código de 6 dígitos ou a senha.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final pairData = PairData(
      protocolVersion: 1,
      scheme: 'https',
      host: host,
      port: port,
      pairingCode: code.isNotEmpty ? code : null,
      serverKeyHash: '', // Validação tolerante na conexão manual
    );

    final success = await widget.controller.pairWithHost(
      pairData: pairData,
      deviceName: _deviceNameController.text.trim(),
      code: code.isNotEmpty ? code : null,
      password: password.isNotEmpty ? password : null,
    );

    setState(() => _isLoading = false);

    if (success) {
      widget.onPairedSuccess();
    } else {
      setState(() {
        _errorMessage = widget.controller.errorMessage ?? 'Erro de conexão com o host Linux.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              decoration: MacTheme.glassCardDecoration(borderRadius: 20),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Ícone de cabeçalho
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.gradientStart, AppColors.gradientEnd],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.neonViolet.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.hub_rounded, size: 28, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Conectar ao Maestri Wire',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pareie com o servidor Linux para controlar seus agentes de IA em tempo real.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Abas: QR Code / Manual
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: AppColors.neonViolet,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: AppColors.textSecondary,
                      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      tabs: const [
                        Tab(text: 'Escanear QR Code'),
                        Tab(text: 'Manual (IP / Senha)'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Mensagem de Erro
                  if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.statusAlert.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.statusAlert.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 16, color: AppColors.statusAlert),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                  color: AppColors.statusAlert, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Conteúdo das Abas
                  SizedBox(
                    height: 380,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Aba 1: Leitor de QR Code + Upload de Print/Foto
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Stack(
                                  children: [
                                    MobileScanner(
                                      controller: _scannerController,
                                      onDetect: _handleQrDetected,
                                    ),
                                    Center(
                                      child: Container(
                                        width: 180,
                                        height: 180,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: AppColors.neonViolet,
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                    ),
                                    if (_isLoading)
                                      Container(
                                        color: Colors.black54,
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: AppColors.neonViolet,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _isLoading ? null : _pickImageFromGallery,
                              icon: const Icon(Icons.photo_library_outlined, size: 18, color: AppColors.neonViolet),
                              label: const Text(
                                'Carregar Print / Foto da Galeria',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: AppColors.neonViolet.withOpacity(0.5)),
                                backgroundColor: AppColors.surfaceElevated.withOpacity(0.7),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              ),
                            ),
                          ],
                        ),

                        // Aba 2: Entrada Manual
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _buildTextField(
                                    controller: _hostController,
                                    label: 'IP do Servidor Linux',
                                    hint: 'ex: 192.168.1.218',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 1,
                                  child: _buildTextField(
                                    controller: _portController,
                                    label: 'Porta',
                                    hint: '7434',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Chips de atalho rápido para os IPs do Linux
                            Wrap(
                              spacing: 8,
                              children: [
                                ActionChip(
                                  label: const Text('Wi-Fi: 192.168.1.218', style: TextStyle(fontSize: 11, color: AppColors.textPrimary)),
                                  backgroundColor: AppColors.surfaceElevated,
                                  side: BorderSide(color: AppColors.border.withOpacity(0.6)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  onPressed: () {
                                    setState(() {
                                      _hostController.text = '192.168.1.218';
                                    });
                                  },
                                ),
                                ActionChip(
                                  label: const Text('Tailscale: 100.82.41.95', style: TextStyle(fontSize: 11, color: AppColors.textPrimary)),
                                  backgroundColor: AppColors.surfaceElevated,
                                  side: BorderSide(color: AppColors.border.withOpacity(0.6)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  onPressed: () {
                                    setState(() {
                                      _hostController.text = '100.82.41.95';
                                    });
                                  },
                                ),
                                ActionChip(
                                  label: const Text('Cabo USB: 127.0.0.1', style: TextStyle(fontSize: 11, color: AppColors.neonViolet)),
                                  backgroundColor: AppColors.surfaceElevated,
                                  side: BorderSide(color: AppColors.neonViolet.withOpacity(0.6)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  onPressed: () {
                                    setState(() {
                                      _hostController.text = '127.0.0.1';
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _buildTextField(
                              controller: _codeController,
                              label: 'Código de 6 Dígitos (Aba Pareamento)',
                              hint: 'ex: 148658',
                            ),
                            const SizedBox(height: 10),
                            _buildTextField(
                              controller: _passwordController,
                              label: 'Ou Senha do Host (Aba Manual)',
                              hint: 'Senha configurada no Maestri',
                              obscureText: true,
                            ),
                            const Spacer(),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleManualPair,
                              style: MacTheme.macPillButtonStyle(isPrimary: true),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Conectar',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscureText,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            filled: true,
            fillColor: AppColors.surfaceElevated,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.neonViolet, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
