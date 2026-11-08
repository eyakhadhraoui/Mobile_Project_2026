import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PhotoStorage {
  PhotoStorage({Future<Directory> Function()? documentsDirectory})
    : _documentsDirectory = documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  Future<String> copier(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw FileSystemException('Photo introuvable', sourcePath);
    final directory = Directory(p.join((await _documentsDirectory()).path, 'annonces_photos'));
    await directory.create(recursive: true);
    final extension = p.extension(sourcePath);
    final name = '${DateTime.now().microsecondsSinceEpoch}_${_nextId++}$extension';
    final destination = p.join(directory.path, name);
    await source.copy(destination);
    return destination;
  }

  Future<void> supprimerSiInterne(String filePath) async {
    final directory = Directory(p.join((await _documentsDirectory()).path, 'annonces_photos'));
    final root = p.normalize(p.absolute(directory.path));
    final candidate = p.normalize(p.absolute(filePath));
    if (!p.isWithin(root, candidate)) return;
    try {
      final file = File(candidate);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Missing or inaccessible cached image should not block an annonce update.
    }
  }

  Future<List<String>> copierPhotos(List<String> paths) async {
    final copied = <String>[];
    try {
      for (final photo in paths) {
        copied.add(await copier(photo));
      }
      return copied;
    } catch (_) {
      for (final file in copied) {
        await supprimerSiInterne(file);
      }
      rethrow;
    }
  }

  static int _nextId = 0;
}
