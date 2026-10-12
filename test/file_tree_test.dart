import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/file_tree.dart';

void main() {
  group('FileTreeNode (payload do canvas)', () {
    test('lê raiz, navegação, miniatura e ambiente', () {
      final node = FileTreeNode.fromJson({
        'rootPath': '/home/u/proj',
        'currentPath': 'lib/src',
        'environment': 'ssh',
        'showsHiddenFiles': true,
        'pinnedPaths': ['lib', '.github'],
        'preview': [
          {'name': 'main.dart', 'isDirectory': false, 'gitStatus': 'M'},
          {'name': 'core', 'isDirectory': true},
        ],
        'branch': 'main',
      });
      expect(node.rootPath, '/home/u/proj');
      expect(node.currentPath, 'lib/src');
      expect(node.environment, 'ssh');
      expect(node.showsHiddenFiles, isTrue);
      expect(node.pinnedPaths, ['lib', '.github']);
      expect(node.preview!.first.gitStatus, 'M');
      expect(node.preview!.last.isDirectory, isTrue);
      expect(node.branch, 'main');
    });

    test('disco do host: sem environment nem preview', () {
      final node = FileTreeNode.fromJson({'rootPath': '/tmp', 'currentPath': ''});
      expect(node.environment, isNull);
      expect(node.preview, isNull);
      expect(node.pinnedPaths, isEmpty);
      expect(node.showsHiddenFiles, isFalse);
    });
  });

  group('FileTreeListing', () {
    test('mantém a ordem do host e os caminhos opacos sem normalizar', () {
      final listing = FileTreeListing.fromJson({
        'path': 'a/b',
        'name': 'b',
        'entries': [
          {'name': 'sub', 'path': 'a/b/sub', 'isDirectory': true, 'isSymbolicLink': false, 'size': 0},
          {
            'name': 'x.dart',
            'path': 'a/b/x.dart',
            'isDirectory': false,
            'isSymbolicLink': true,
            'size': 42,
            'modifiedAt': '2026-10-10T20:48:10.593Z',
            'gitStatus': '?',
          },
        ],
        'isTruncated': true,
        'git': {'branch': 'feature', 'changedCount': 3, 'hasUpstream': false},
      });
      expect(listing.path, 'a/b');
      expect(listing.entries.map((e) => e.path), ['a/b/sub', 'a/b/x.dart']);
      expect(listing.entries[0].isDirectory, isTrue);
      expect(listing.entries[1].isSymbolicLink, isTrue);
      expect(listing.entries[1].size, 42);
      expect(listing.entries[1].modifiedAt, isNotNull);
      expect(listing.entries[1].gitStatus, '?');
      expect(listing.isTruncated, isTrue);
      expect(listing.git!.branch, 'feature');
      expect(listing.git!.changedCount, 3);
    });

    test('pasta fora de repositório não tem git', () {
      final listing = FileTreeListing.fromJson({'path': '', 'name': 'tmp', 'entries': []});
      expect(listing.git, isNull);
      expect(listing.entries, isEmpty);
      expect(listing.isTruncated, isFalse);
    });
  });

  test('FileTreeSearch lê hits e truncamento', () {
    final s = FileTreeSearch.fromJson({
      'query': 'main',
      'hits': [
        {'name': 'main.dart', 'path': 'lib/main.dart', 'isDirectory': false, 'isSymbolicLink': false, 'size': 0},
      ],
      'isTruncated': false,
    });
    expect(s.query, 'main');
    expect(s.hits.single.path, 'lib/main.dart');
    expect(s.isTruncated, isFalse);
  });

  test('FileTreeChanges separa staged e unstaged; arquivo nos dois lados aparece nos dois', () {
    final c = FileTreeChanges.fromJson({
      'branch': 'main',
      'staged': [
        {'path': 'lib/a.dart', 'name': 'a.dart', 'directory': 'lib', 'status': 'M', 'isStaged': true, 'additions': 2, 'deletions': 1}
      ],
      'unstaged': [
        {'path': 'lib/a.dart', 'name': 'a.dart', 'directory': 'lib', 'status': 'M', 'isStaged': false},
        {'path': 'new.txt', 'name': 'new.txt', 'directory': '', 'status': '?', 'isStaged': false},
      ],
    });
    expect(c.branch, 'main');
    expect(c.staged.single.isStaged, isTrue);
    expect(c.staged.single.additions, 2);
    expect(c.staged.single.deletions, 1);
    expect(c.unstaged.length, 2);
    expect(c.unstaged.first.additions, isNull);
    expect(c.unstaged.last.status, '?');
  });

  test('FileTreeDiff e os escopos enviados ao host', () {
    final d = FileTreeDiff.fromJson({'path': 'lib/a.dart', 'scope': 'staged', 'patch': '@@ -1 +1 @@\n-a\n+b\n'});
    expect(d.patch, contains('+b'));
    expect(FileTreeDiffScope.combined.wire, 'combined');
    expect(FileTreeDiffScope.staged.wire, 'staged');
    expect(FileTreeDiffScope.unstaged.wire, 'unstaged');
  });

  group('parseContentRangeTotal', () {
    test('lê o total de bytes 0-15/1234', () {
      expect(parseContentRangeTotal('bytes 0-15/1234'), 1234);
    });
    test('lê o total de bytes */1234 (416)', () {
      expect(parseContentRangeTotal('bytes */1234'), 1234);
    });
    test('total desconhecido ou ausente', () {
      expect(parseContentRangeTotal('bytes 0-15/*'), isNull);
      expect(parseContentRangeTotal(null), isNull);
      expect(parseContentRangeTotal('nada'), isNull);
    });
  });

  test('FileTreeBytes indica quando há mais trechos', () {
    const first = FileTreeBytes(bytes: [1, 2, 3], statusCode: 206, totalLength: 10);
    expect(first.hasMore, isTrue);
    const last = FileTreeBytes(bytes: [1, 2], statusCode: 206, totalLength: 5, start: 3);
    expect(last.hasMore, isFalse);
    const unknown = FileTreeBytes(bytes: [1], statusCode: 200);
    expect(unknown.hasMore, isFalse);
  });

  group('FileTreeException (erros do host)', () {
    test('lê {"error": {code, message}}', () {
      final e = FileTreeException.fromResponse(400, '{"error":{"code":"invalidRequest","message":"Path leaves the tree"}}');
      expect(e.statusCode, 400);
      expect(e.code, 'invalidRequest');
      expect(e.message, 'Path leaves the tree');
    });

    test('404 com o texto do host', () {
      final e = FileTreeException.fromResponse(404, '{"error":{"code":"notFound","message":"Folder not found"}}');
      expect(e.code, 'notFound');
      expect(e.message, 'Folder not found');
    });

    test('corpo que não é JSON cai no texto bruto', () {
      final e = FileTreeException.fromResponse(502, 'Permission denied');
      expect(e.code, 'unknown');
      expect(e.message, 'Permission denied');
    });

    test('corpo vazio usa o status', () {
      final e = FileTreeException.fromResponse(500, '');
      expect(e.message, 'HTTP 500');
    });
  });

  group('FileTreeCrumbs (pilha de navegação)', () {
    FileTreeEntry folder(String name, String path) =>
        FileTreeEntry(name: name, path: path, isDirectory: true);

    test('começa na raiz e entra/sobe sem mexer nos caminhos', () {
      final crumbs = FileTreeCrumbs('proj');
      expect(crumbs.current.path, '');
      expect(crumbs.canGoUp, isFalse);
      expect(crumbs.up(), isFalse);

      crumbs.push(folder('lib', 'lib'));
      crumbs.push(folder('src', 'lib/src'));
      expect(crumbs.current.path, 'lib/src');
      expect(crumbs.items.map((c) => c.name), ['proj', 'lib', 'src']);

      expect(crumbs.up(), isTrue);
      expect(crumbs.current.path, 'lib');
    });

    test('jumpTo volta a um nível da pilha', () {
      final crumbs = FileTreeCrumbs('proj');
      crumbs.push(folder('a', 'a'));
      crumbs.push(folder('b', 'a/b'));
      crumbs.jumpTo(0);
      expect(crumbs.current.path, '');
      expect(crumbs.items.length, 1);
    });

    test('resetTo abre um resultado de busca como raiz + pasta', () {
      final crumbs = FileTreeCrumbs('proj');
      crumbs.push(folder('a', 'a'));
      crumbs.resetTo('proj', folder('deep', 'x/y/deep'));
      expect(crumbs.items.map((c) => c.path), ['', 'x/y/deep']);
      expect(crumbs.current.name, 'deep');
    });
  });
}
