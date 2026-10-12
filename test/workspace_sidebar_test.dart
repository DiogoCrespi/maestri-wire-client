import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/sidebar_layout.dart';
import 'package:maestri_wire_client/models/workspace.dart';
import 'package:maestri_wire_client/ui/widgets/workspace_editor.dart';
import 'package:maestri_wire_client/ui/widgets/workspace_sidebar.dart';

void main() {
  final layout = SidebarLayout.fromJson({
    'folders': [
      {'id': 'f1', 'name': 'Clientes'},
    ],
    'groups': [
      {
        'id': 'g1',
        'name': 'Trabalho',
        'folders': [
          {'id': 'f2', 'name': 'Projetos'},
        ],
      },
    ],
  });

  final workspaces = [
    WorkspaceMeta(id: 'w1', name: 'Solto'),
    WorkspaceMeta(id: 'w2', name: 'Do cliente', folderName: 'Clientes'),
    WorkspaceMeta(id: 'w3', name: 'Do grupo', groupName: 'Trabalho'),
    WorkspaceMeta(id: 'w4', name: 'No projeto', groupName: 'Trabalho', folderName: 'Projetos'),
    WorkspaceMeta(id: 'w5', name: 'Pasta sumida', folderName: 'Não existe'),
  ];

  Future<void> pumpSidebar(WidgetTester tester, {SidebarLayout? layout}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        drawer: WorkspaceSidebar(
          workspaces: workspaces,
          onSelectWorkspace: (_) {},
          onAddWorkspace: () {},
          layout: layout,
        ),
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Scaffold.of(context).openDrawer(),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('sem layout mostra a lista plana', (tester) async {
    await pumpSidebar(tester);
    expect(find.text('Solto'), findsOneWidget);
    expect(find.text('Do cliente'), findsOneWidget);
    expect(find.text('Clientes'), findsNothing);
  });

  testWidgets('com layout mostra pastas e grupos, sem perder workspace', (tester) async {
    await pumpSidebar(tester, layout: layout);
    expect(find.text('Clientes'), findsOneWidget);
    expect(find.text('Trabalho'), findsOneWidget);
    expect(find.text('Projetos'), findsOneWidget);
    // Workspace com pasta inexistente aparece sem pasta, nunca some
    expect(find.text('Pasta sumida'), findsOneWidget);
    expect(find.text('No projeto'), findsOneWidget);
  });

  test('placementOptions cobre pastas e pastas de grupo', () {
    final keys = placementOptions(layout).map((o) => o.key).toList();
    expect(keys, containsAll(['top', 'folder:f1', 'group:g1', 'folder:f2']));
  });

  test('currentPlacementKey acha a pasta pelo nome dentro do grupo', () {
    final ws = WorkspaceMeta(id: 'w', name: 'x', groupName: 'Trabalho', folderName: 'Projetos');
    expect(currentPlacementKey(ws, layout), 'folder:f2');
    expect(currentPlacementKey(WorkspaceMeta(id: 'w', name: 'x'), layout), 'top');
  });
}
