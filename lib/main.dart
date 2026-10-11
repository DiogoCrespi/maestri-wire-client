import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/mac_theme.dart';
import 'state/wire_controller.dart';
import 'ui/screens/main_canvas_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Força estilo de barra de status transparente e ícones claros no Android
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF090A0E),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const MaestriWireApp());
}

class MaestriWireApp extends StatefulWidget {
  const MaestriWireApp({Key? key}) : super(key: key);

  @override
  State<MaestriWireApp> createState() => _MaestriWireAppState();
}

class _MaestriWireAppState extends State<MaestriWireApp> {
  late final WireController _wireController;

  @override
  void initState() {
    super.initState();
    _wireController = WireController();
  }

  @override
  void dispose() {
    _wireController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maestri Wire',
      debugShowCheckedModeBanner: false,
      theme: MacTheme.darkTheme,
      home: MainCanvasScreen(controller: _wireController),
    );
  }
}
