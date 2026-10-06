import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/ui/mobile/mobile_gallery.dart';
import 'package:evrak_convert/ui/mobile/photo_viewer.dart';

import 'support/temp_directory.dart';

import 'package:image/image.dart' as img;
import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/platform/heif_images.dart';
import 'package:evrak_convert/services/platform/picture_folders.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/services/search/search_models.dart';
import 'package:evrak_convert/ui/library/gallery_view.dart';
import 'package:evrak_convert/ui/widgets/image_viewer_widget.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:evrak_convert/ui/library/library_sidebar.dart';

Future<Directory> pictures(WidgetTester tester, int count) async {
  final dir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('gallery-'),
  ))!;
  await tester.runAsync(() async {
    for (var i = 0; i < count; i++) {
      File('${dir.path}/foto$i.png')
          .writeAsBytesSync(img.encodePng(img.Image(width: 80, height: 60)));
    }
  });
  return dir;
}

Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('a picture folder is found without being asked for', () async {
    // On this machine the folder is called Resimler, elsewhere Pictures or
    // Bilder; the name is translated and has to be read, not guessed.
    final found = await PictureFolders.find();
    for (final path in found) {
      expect(Directory(path).existsSync(), isTrue);
    }
  });

  test('iPhone photographs are recognised, and honestly reported', () {
    expect(HeifImages.isHeif('/tmp/IMG_0042.HEIC'), isTrue);
    expect(HeifImages.isHeif('/tmp/IMG_0042.heif'), isTrue);
    expect(HeifImages.isHeif('/tmp/IMG_0042.jpg'), isFalse);
    expect(EvrakFormat.fromExtension('heic'), EvrakFormat.image);
    expect(EvrakFormat.fromExtension('heif'), EvrakFormat.image);
    // Only Android has a decoder to borrow, so only Android claims one.
    expect(HeifImages.supported, Platform.isAndroid);
  });

  testWidgets('an empty gallery offers to find the pictures itself', (
    tester,
  ) async {
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    await tester.runAsync(library.initialize);
    addTearDown(library.dispose);

    await tester.pumpWidget(
      app(
        GalleryView(
          library: library,
          hits: const [],
          onOpen: (_) {},
          loadMore: () {},
          pickFolder: () async => null,
        ),
      ),
    );
    expect(find.text('Galeri boş'), findsOneWidget);
    expect(find.text('Resim klasörlerimi ekle'), findsOneWidget);
    expect(find.text('Klasör ekle'), findsOneWidget);
  });

  testWidgets('a folder is added and taken away again', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = await pictures(tester, 3);
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    await tester.runAsync(library.initialize);
    addTearDown(library.dispose);

    await tester.pumpWidget(
      app(
        GalleryView(
          library: library,
          hits: const [],
          onOpen: (_) {},
          loadMore: () {},
          pickFolder: () async => dir.path,
        ),
      ),
    );

    await tester.tap(find.text('Klasör ekle'));
    // Adding a folder writes to the library, so wait for the writing rather
    // than for a fixed stretch of time: on a loaded machine the fixed wait
    // ran out first and the test failed for no reason of its own.
    final name = dir.path.split(Platform.pathSeparator).last;
    for (
      var i = 0;
      i < 80 &&
          (library.sources.where((s) => s.folder).isEmpty ||
              find.text(name).evaluate().isEmpty);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(library.sources.where((s) => s.folder).length, 1);
    expect(find.text(name), findsWidgets);

    // Taking it away asks first, and says what it does not touch.
    final remove = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('gallery-remove-'),
    );
    for (var i = 0; i < 40 && remove.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.tap(remove.first);
    await tester.pumpAndSettle();
    expect(find.textContaining('galeriden çıkarılsın mı'), findsOneWidget);
    expect(find.textContaining('dosyaya dokunulmaz'), findsOneWidget);
    await tester.tap(find.text('Çıkar'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    expect(library.sources.where((s) => s.folder), isEmpty);
    // The folder itself is untouched.
    expect(dir.listSync().length, 3);
    await removeTemporaryDirectory(tester, dir);
  });

  testWidgets('a phone can reach the gallery from its home screen', (
    tester,
  ) async {
    // A desktop reaches it from the sidebar. A phone has no sidebar, so
    // without a door on the home screen the gallery does not exist there.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-phone-gallery-'),
    ))!;
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    final appearance = ThemeController(settingsPath: '${dir.path}/theme.json');
    await tester.runAsync(library.initialize);

    await tester.pumpWidget(
      EvrakConvertApp(library: library, appearance: appearance),
    );
    await tester.pumpAndSettle();
    expect(find.text('Belge aç'), findsOneWidget);
    expect(find.text('Galeri'), findsOneWidget);

    await tester.tap(find.text('Galeri'));
    await tester.pumpAndSettle();
    // A phone's gallery is its own: the photographs edge to edge.
    expect(find.byType(MobileGallery), findsOneWidget);
    expect(find.text('Galeri boş'), findsOneWidget);

    // A photograph has no text to search, no file type to filter by and no
    // relevance to sort on; none of those belong on this screen.
    expect(find.text('Metin'), findsNothing);
    expect(find.text('Excel'), findsNothing);
    expect(find.text('Yeni eklenenler'), findsNothing);
    expect(find.text('Evrak adı veya içeriğinde ara…'), findsNothing);

    // And the menu's first page returns to the home screen.
    await tester.tap(find.byKey(const ValueKey('gallery-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawer-home')));
    await tester.pumpAndSettle();
    expect(find.text('Belge aç'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      library.dispose();
      appearance.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await removeTemporaryDirectory(tester, dir);
  });

  testWidgets('a swipe walks the whole folder, not only what was opened', (
    tester,
  ) async {
    // The bug this replaces: a swipe stepped through the list of documents
    // that had been opened, so a folder of six hundred photographs could be
    // walked only between the two that had already been tapped.
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = await pictures(tester, 5);
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    final appearance = ThemeController(settingsPath: '${dir.path}/theme.json');
    await tester.runAsync(library.initialize);
    await tester.runAsync(() => library.addPaths([dir.path]));

    await tester.pumpWidget(
      EvrakConvertApp(library: library, appearance: appearance),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galeri'));
    // Thumbnails are drawn after the hits arrive; wait for both.
    for (
      var i = 0;
      i < 160 &&
          (library.hits.length < 5 || find.byType(Image).evaluate().isEmpty);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(library.hits.length, 5, reason: 'klasördeki beş fotoğraf');
    expect(find.byType(Image), findsWidgets, reason: 'küçük resimler gelmedi');

    // Open the first, then walk forward without having opened the rest.
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    final first = library.hits.first.file.path;
    // On a phone: full screen, the whole folder to swipe through.
    expect(find.byType(PhotoViewerPage), findsOneWidget);
    expect(find.byKey(ValueKey('photo-$first')), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('photo-pages')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('2 / 5'),
      findsOneWidget,
      reason: 'hiç açılmamış olsa da sıradaki fotoğrafa gitmeli',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      library.dispose();
      appearance.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await removeTemporaryDirectory(tester, dir);
  });

  testWidgets('photographs are shown as photographs, not as file names', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = await pictures(tester, 6);
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    await tester.runAsync(library.initialize);
    addTearDown(library.dispose);

    final opened = <String>[];
    await tester.pumpWidget(
      app(
        GalleryView(
          library: library,
          hits: [
            for (final file in dir.listSync().whereType<File>())
              SearchHit(file: EvrakFile.fromPath(file.path)),
          ],
          onOpen: (file) => opened.add(file.path),
          loadMore: () {},
          pickFolder: () async => null,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(6));

    await tester.tap(find.byType(Image).first);
    await tester.pump();
    expect(opened.length, 1);
    await removeTemporaryDirectory(tester, dir);
  });

  /// A picture on its own, without the archive behind it, so what is being
  /// tested is the viewer and not the wiring.
  Future<List<bool>> stepping(
    WidgetTester tester,
    Directory dir, {
    bool grabFocus = false,
    int? position,
    int? total,
    VoidCallback? onFullScreen,
  }) async {
    final stepped = <bool>[];
    await tester.pumpWidget(
      app(
        ImageViewerWidget(
          filePath: '${dir.path}/foto0.png',
          onPastEnd: stepped.add,
          grabFocus: grabFocus,
          position: position,
          total: total,
          onFullScreen: onFullScreen,
        ),
      ),
    );
    await tester.pump();
    return stepped;
  }

  testWidgets('a photograph answers the arrow keys without being clicked', (
    tester,
  ) async {
    // Bu kusurun tamamı buydu: galeriden açınca odak ızgarada kalıyor,
    // ok tuşu fotoğrafa değil listeye gidiyordu.
    final dir = await pictures(tester, 3);
    final stepped = await stepping(tester, dir, grabFocus: true, total: 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(stepped, [true]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(stepped, [true, false]);
    await removeTemporaryDirectory(tester, dir);
  });

  testWidgets('a document viewer still leaves the arrow keys to the list', (
    tester,
  ) async {
    final dir = await pictures(tester, 3);
    final stepped = await stepping(tester, dir, total: 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(stepped, isEmpty);
    await removeTemporaryDirectory(tester, dir);
  });

  testWidgets('the picture carries its own way forward and back', (
    tester,
  ) async {
    final dir = await pictures(tester, 3);
    final stepped = await stepping(tester, dir, position: 2, total: 40);
    expect(find.text('2 / 40'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('image-next')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('image-previous')));
    await tester.pump();
    expect(stepped, [true, false]);
    await removeTemporaryDirectory(tester, dir);
  });

  testWidgets('a picture with no neighbours shows no arrows and no count', (
    tester,
  ) async {
    final dir = await pictures(tester, 1);
    await stepping(tester, dir, position: 1, total: 1);
    expect(find.byKey(const ValueKey('image-next')), findsNothing);
    expect(find.byKey(const ValueKey('image-previous')), findsNothing);
    expect(find.textContaining(' / '), findsNothing);
    await removeTemporaryDirectory(tester, dir);
  });

  testWidgets('full screen is reached without hunting for the icon', (
    tester,
  ) async {
    final dir = await pictures(tester, 2);
    var asked = 0;
    await stepping(
      tester,
      dir,
      grabFocus: true,
      total: 2,
      onFullScreen: () => asked++,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(asked, 1, reason: 'F tam ekran açmalı');

    final at = tester.getCenter(find.byType(InteractiveViewer));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(at);
    await tester.pump();
    expect(asked, 2, reason: 'çift tık da açmalı');
    await removeTemporaryDirectory(tester, dir);
  });

  testWidgets('a folder can be looked at on its own, and let go again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final one = await pictures(tester, 2);
    final two = await pictures(tester, 2);
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    await tester.runAsync(library.initialize);
    addTearDown(library.dispose);
    await tester.runAsync(
      () => library.addPaths([one.path, two.path], recursive: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: library,
            builder: (_, _) => GalleryView(
              library: library,
              hits: const [],
              onOpen: (_) {},
              loadMore: () {},
              pickFolder: () async => null,
            ),
          ),
        ),
      ),
    );
    for (
      var i = 0;
      i < 80 && library.sources.where((s) => s.folder).length < 2;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(library.sources.where((s) => s.folder).length, 2);
    await tester.pump();

    final first = library.sources.firstWhere((s) => s.folder);
    expect(library.sourceId, isNull);
    await tester.tap(find.byKey(ValueKey('gallery-folder-${first.id}')));
    await tester.pump();
    expect(library.sourceId, first.id);
    // Aynı klasöre tekrar basmak diğerlerini geri getirir.
    await tester.tap(find.byKey(ValueKey('gallery-folder-${first.id}')));
    await tester.pump();
    expect(library.sourceId, isNull);
    expect(find.byKey(const ValueKey('gallery-folder-all')), findsOneWidget);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await removeTemporaryDirectory(tester, one);
    await removeTemporaryDirectory(tester, two);
  });

  testWidgets('the keyboard comes back when nothing else has taken it', (
    tester,
  ) async {
    // Bildirilen kusur: fotoğraflar arasında gezerken odak kayboluyor ve
    // resmin üzerine bir kez tıklamadan ok tuşları işlemiyor. Odak gerçekten
    // başka bir şeye geçmişse dokunulmaz; hiç kimsede değilse geri alınır.
    final dir = await pictures(tester, 2);
    final stepped = <bool>[];
    await tester.pumpWidget(
      app(
        ImageViewerWidget(
          filePath: '${dir.path}/foto0.png',
          onPastEnd: stepped.add,
          grabFocus: true,
          total: 2,
          position: 1,
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(stepped, [true]);

    // Odağı hiçbir şeye bırakmadan düşür.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(stepped, [
      true,
      true,
    ], reason: 'kimse almadıysa klavye resme dönmeli');
    await removeTemporaryDirectory(tester, dir);
  });

  testWidgets('a field that has taken the keyboard keeps it', (tester) async {
    final dir = await pictures(tester, 2);
    final stepped = <bool>[];
    final field = FocusNode(debugLabel: 'yazı alanı');
    addTearDown(field.dispose);
    await tester.pumpWidget(
      app(
        Column(
          children: [
            SizedBox(
              height: 300,
              child: ImageViewerWidget(
                filePath: '${dir.path}/foto0.png',
                onPastEnd: stepped.add,
                grabFocus: true,
                total: 2,
                position: 1,
              ),
            ),
            TextField(focusNode: field),
          ],
        ),
      ),
    );
    await tester.pump();
    field.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus,
      field,
      reason: 'gerçekten odaklanan bir alandan klavye çalınmamalı',
    );
    expect(stepped, isEmpty);
    await removeTemporaryDirectory(tester, dir);
  });

  testWidgets('full screen on a desktop leaves only the picture', (
    tester,
  ) async {
    // Bildirilen kusur: resme çift tıklayınca tam ekran oluyor ama sol panel
    // ve sonuç listesi kalıyor. Tam ekran telefon için yazılmıştı; orada
    // zaten yanında bir şey yok.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = await pictures(tester, 3);
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    final appearance = ThemeController(settingsPath: '${dir.path}/theme.json');
    await tester.runAsync(library.initialize);
    await tester.runAsync(() => library.addPaths([dir.path]));
    await tester.pumpWidget(
      EvrakConvertApp(library: library, appearance: appearance),
    );
    Future<void> settle([int frames = 20]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    await settle();
    await tester.tap(find.text('Galeri'));
    // The thumbnails are drawn after the hits arrive, not with them; on a
    // slow machine (CI) the first picture was not there yet to be clicked.
    for (
      var i = 0;
      i < 160 &&
          (library.hits.length < 3 || find.byType(Image).evaluate().isEmpty);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.byType(Image), findsWidgets, reason: 'küçük resimler gelmedi');
    await tester.tap(find.byType(Image).first);
    await settle();

    // Galeri kipinde yan sütunda küçük resim ızgarası duruyor.
    final sidebar = find.byType(LibrarySidebar).hitTestable();
    expect(sidebar, findsOneWidget);
    expect(find.byType(GalleryView), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await settle();
    expect(sidebar, findsNothing, reason: 'sol panel kalmamalı');
    expect(
      find.byType(GalleryView),
      findsNothing,
      reason: 'yan sütun kalmamalı',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();
    expect(sidebar, findsOneWidget, reason: 'çıkınca geri gelmeli');
    expect(find.byType(GalleryView), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      library.dispose();
      appearance.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await removeTemporaryDirectory(tester, dir);
  });

  testWidgets('a picture opened from the archive list walks with the arrows', (
    tester,
  ) async {
    // Bildirilen kusur: arşiv listesinden bir resim açınca sağ/sol ok
    // tuşları hiçbir şey yapmıyor, resme bir kez tıklamak gerekiyor.
    // Galeri değil: orada resim odağı kendi alıyor. Burada odak listede
    // kalır ve liste sağ/sol tuşlarını hiç işlemiyordu.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = await pictures(tester, 3);
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    final appearance = ThemeController(settingsPath: '${dir.path}/theme.json');
    await tester.runAsync(library.initialize);
    await tester.runAsync(() => library.addPaths([dir.path]));
    await tester.pumpWidget(
      EvrakConvertApp(library: library, appearance: appearance),
    );
    Future<void> settle([int frames = 20]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    await settle();
    await tester.tap(find.text('Tüm Evraklar'));
    for (var i = 0; i < 60 && library.hits.length < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(library.hits.length, 3);

    final row = find
        .textContaining('foto', findRichText: true)
        .hitTestable()
        .first;
    await tester.tap(row);
    await settle();
    expect(find.byType(ImageViewerWidget), findsOneWidget);
    String shown() => tester
        .widget<ImageViewerWidget>(find.byType(ImageViewerWidget))
        .filePath;
    final first = shown();

    // Resme hiç dokunmadan, yalnız klavyeyle.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle();
    expect(shown(), isNot(first), reason: 'sağ ok sonraki resme geçmeli');
    final second = shown();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle();
    expect(shown(), first, reason: 'sol ok geri getirmeli');
    expect(second, isNot(first));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      library.dispose();
      appearance.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await removeTemporaryDirectory(tester, dir);
  });
}
