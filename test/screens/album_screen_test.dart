import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/album_screen.dart';
import 'package:aimaru/services/album_service.dart';
import 'package:aimaru/services/storage_service.dart';

// StorageServiceは本番実装がFirebaseStorage.instanceに触れるため、
// アップロード・削除先だけを差し替えたフェイクをサブクラスとして用意する
// （bug_report_screen_test.dartと同じ設計）。
class _FakeStorageService extends StorageService {
  final Future<String> Function(String coupleId, File file)? uploadImpl;
  final Future<void> Function(String url)? deleteImpl;
  _FakeStorageService({this.uploadImpl, this.deleteImpl});

  @override
  Future<String> uploadAlbumImage(String coupleId, File file) =>
      uploadImpl?.call(coupleId, file) ?? Future.value('https://example.com/uploaded.jpg');

  @override
  Future<void> deleteImage(String url) => deleteImpl?.call(url) ?? Future.value();
}

// 無限ローディングのまま固まらないことを確かめる（他画面のStreamBuilderと同じ観点）。
void main() {
  Widget wrap(
    Stream<List<AlbumPhoto>> stream, {
    AlbumService? albumService,
    StorageService? storageService,
    List<File>? imagesToUpload,
  }) =>
      MaterialApp(
        home: AlbumScreen(
          coupleId: 'couple-1',
          photosStreamOverride: stream,
          albumServiceOverride: albumService,
          storageServiceOverride: storageService,
          imagesToUploadForTest: imagesToUpload,
        ),
      );

  final samplePhoto = AlbumPhoto(
    id: 'p1',
    coupleId: 'couple-1',
    imageUrl: 'https://example.com/a.jpg',
    uploadedBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
  );

  testWidgets('データが来る前はローディング表示', (tester) async {
    final controller = StreamController<List<AlbumPhoto>>();
    await tester.pumpWidget(wrap(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await controller.close();
  });

  testWidgets('ストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    final controller = StreamController<List<AlbumPhoto>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('読み込みに失敗'), findsOneWidget);

    await controller.close();
  });

  testWidgets('写真が無い場合は案内文を表示する', (tester) async {
    final controller = StreamController<List<AlbumPhoto>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add(const []);
    await tester.pump();

    expect(find.textContaining('まだ写真がありません'), findsOneWidget);

    await controller.close();
  });

  testWidgets('データが来たら写真を並べて表示する', (tester) async {
    final controller = StreamController<List<AlbumPhoto>>();
    await tester.pumpWidget(wrap(controller.stream));

    controller.add([samplePhoto]);
    await tester.pump();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(ClipRRect), findsWidgets);

    await controller.close();
  });

  testWidgets('追加ボタンを押すとアップロードしてAlbumServiceに登録する', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = AlbumService(firestore: db, uid: 'u1');
    final uploadedCoupleIds = <String>[];
    final storage = _FakeStorageService(
      uploadImpl: (coupleId, file) async {
        uploadedCoupleIds.add(coupleId);
        return 'https://example.com/${file.path.split('/').last}';
      },
    );

    final controller = StreamController<List<AlbumPhoto>>();
    await tester.pumpWidget(wrap(
      controller.stream,
      albumService: service,
      storageService: storage,
      imagesToUpload: [File('fake/a.jpg')],
    ));
    controller.add(const []);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.pumpAndSettle();

    expect(uploadedCoupleIds, ['couple-1']);
    final snap = await db
        .collection('couples')
        .doc('couple-1')
        .collection('albumPhotos')
        .get();
    expect(snap.docs, hasLength(1));
    expect(snap.docs.first.data()['imageUrl'], 'https://example.com/a.jpg');

    await controller.close();
  });

  testWidgets('アップロードに失敗したらエラーメッセージを表示する', (tester) async {
    final storage = _FakeStorageService(
      uploadImpl: (coupleId, file) async => throw Exception('通信エラー'),
    );

    final controller = StreamController<List<AlbumPhoto>>();
    await tester.pumpWidget(wrap(
      controller.stream,
      storageService: storage,
      imagesToUpload: [File('fake/a.jpg')],
    ));
    controller.add(const []);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.pumpAndSettle();

    expect(find.text('写真の追加に失敗しました'), findsOneWidget);

    await controller.close();
  });

  testWidgets('長押しして削除を確定するとStorageとAlbumServiceの両方から削除する', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = AlbumService(firestore: db, uid: 'u1');
    await db
        .collection('couples')
        .doc('couple-1')
        .collection('albumPhotos')
        .doc('p1')
        .set(samplePhoto.toMap());

    final deletedUrls = <String>[];
    final storage = _FakeStorageService(deleteImpl: (url) async => deletedUrls.add(url));

    final controller = StreamController<List<AlbumPhoto>>();
    await tester.pumpWidget(wrap(controller.stream, albumService: service, storageService: storage));
    controller.add([samplePhoto]);
    await tester.pump();

    await tester.longPress(find.byType(ClipRRect).first);
    await tester.pumpAndSettle();

    expect(find.text('この写真を削除しますか？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '削除'));
    await tester.pumpAndSettle();

    expect(deletedUrls, ['https://example.com/a.jpg']);
    final doc = await db
        .collection('couples')
        .doc('couple-1')
        .collection('albumPhotos')
        .doc('p1')
        .get();
    expect(doc.exists, isFalse);

    await controller.close();
  });

  testWidgets('削除ダイアログでキャンセルすると何も消えない', (tester) async {
    final db = FakeFirebaseFirestore();
    final service = AlbumService(firestore: db, uid: 'u1');
    await db
        .collection('couples')
        .doc('couple-1')
        .collection('albumPhotos')
        .doc('p1')
        .set(samplePhoto.toMap());

    final controller = StreamController<List<AlbumPhoto>>();
    await tester.pumpWidget(wrap(controller.stream, albumService: service));
    controller.add([samplePhoto]);
    await tester.pump();

    await tester.longPress(find.byType(ClipRRect).first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'キャンセル'));
    await tester.pumpAndSettle();

    final doc = await db
        .collection('couples')
        .doc('couple-1')
        .collection('albumPhotos')
        .doc('p1')
        .get();
    expect(doc.exists, isTrue);

    await controller.close();
  });
}
