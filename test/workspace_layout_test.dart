import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/core/network/api_workspaces.dart';
import 'package:maestri_wire_client/models/sidebar_layout.dart';
import 'package:maestri_wire_client/models/workspace.dart';

void main() {
  group('SidebarLayout', () {
    test('lê pastas de nível superior e grupos com suas pastas', () {
      final layout = SidebarLayout.fromJson({
        'folders': [
          {'id': 'f1', 'name': 'Clientes'},
          {'id': '', 'name': 'sem id'},
        ],
        'groups': [
          {
            'id': 'g1',
            'name': 'Trabalho',
            'folders': [
              {'id': 'f2', 'name': 'Projetos'},
            ],
          },
          {'name': 'sem id'},
        ],
      });
      expect(layout.folders.map((f) => f.name), ['Clientes']);
      expect(layout.groups.single.folders.single.id, 'f2');
      expect(layout.folderById('f2')?.name, 'Projetos');
      expect(layout.groupById('g1')?.name, 'Trabalho');
      expect(layout.isEmpty, isFalse);
    });

    test('ausente ou malformado é layout vazio', () {
      expect(SidebarLayout.fromJson(null).isEmpty, isTrue);
      expect(SidebarLayout.fromJson('x').isEmpty, isTrue);
    });
  });

  group('WorkspaceMeta com resumos de andar', () {
    test('ausência dos arrays significa indisponível (null), não lista vazia', () {
      final ws = WorkspaceMeta.fromJson({'id': 'w1', 'name': 'A'});
      expect(ws.floors, isNull);
      expect(ws.pendingFloors, isNull);
      expect(ws.groundStatus, isNull);
    });

    test('lê andares (térreo sem id), andares pendentes e o relato do térreo', () {
      final ws = WorkspaceMeta.fromJson({
        'id': 'w1',
        'name': 'A',
        'isActive': true,
        'folderName': 'Clientes',
        'environment': {'kind': 'ssh', 'name': 'servidor'},
        'floors': [
          {'name': 'Térreo', 'isActive': true},
          {'id': '6f1c2a3e-0000-4000-8000-000000000001', 'name': 'feat-x', 'isGitIsolated': true},
        ],
        'pendingFloors': [
          {'id': 'p1', 'name': 'copiando', 'completedItems': 2, 'totalItems': 5},
          {'name': 'sem id'},
        ],
        'groundStatus': {'state': 'review', 'text': 'Revisando', 'progress': 0.5},
        'groundFloorBranch': 'main',
      });
      expect(ws.isActive, isTrue);
      expect(ws.folderName, 'Clientes');
      expect(ws.environmentKind, 'ssh');
      expect(ws.floors!.first.isGround, isTrue);
      expect(ws.floors!.last.queryValue, '6f1c2a3e-0000-4000-8000-000000000001');
      expect(ws.pendingFloors!.single.totalItems, 5);
      expect(ws.groundStatus!.progress, 0.5);
      expect(ws.groundFloorBranch, 'main');
    });

    test('WorkspacesListing lê workspaces e layout juntos', () {
      final listing = WorkspacesListing.fromJson({
        'workspaces': [
          {'id': 'w1', 'name': 'A'},
          'lixo',
        ],
        'layout': {
          'folders': [
            {'id': 'f1', 'name': 'X'},
          ],
        },
      });
      expect(listing.workspaces.map((w) => w.id), ['w1']);
      expect(listing.layout.folders.single.name, 'X');
    });
  });

  group('Lugar de arquivamento', () {
    test('pasta, senão grupo, senão nível superior', () {
      expect(WorkspacePlacement.topLevel.toJson(), isEmpty);
      expect(const WorkspacePlacement(groupId: 'g').toJson(), {'groupId': 'g'});
      expect(const WorkspacePlacement(folderId: 'f', groupId: 'g').toJson(), {'folderId': 'f', 'groupId': 'g'});
    });

    test('diretórios do host: pastas com nome e caminho', () {
      final dirs = DirectoryListing.fromJson({
        'path': '/tmp',
        'name': 'tmp',
        'directories': [
          {'name': 'a', 'path': '/tmp/a'},
          {'name': 'sem caminho'},
        ],
        'isTruncated': true,
      });
      expect(dirs.directories.single.path, '/tmp/a');
      expect(dirs.isTruncated, isTrue);
    });
  });
}
