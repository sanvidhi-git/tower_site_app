import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/outbox.dart';

class PhotoEntry {
  PhotoEntry(this.path, [this.caption = '']);
  final String path;
  String caption;
}

/// Camera-first photo capture. Photos are resized/compressed by image_picker
/// (max 1600px, quality 70) and copied into app storage for the outbox.
Future<String?> pickPhoto(BuildContext context, {bool allowGallery = true}) async {
  ImageSource? source = ImageSource.camera;
  if (allowGallery) {
    source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
  }
  if (source == null) return null;
  final x = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 70);
  if (x == null) return null;
  return Outbox.keepPhoto(x.path);
}

class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.photos, required this.onChanged, this.max = 8, this.hint = 'Caption'});

  final List<PhotoEntry> photos;
  final VoidCallback onChanged;
  final int max;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 132,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final p in photos)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 110,
                child: Column(children: [
                  Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(p.path), width: 110, height: 88, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: InkWell(
                        onTap: () {
                          photos.remove(p);
                          onChanged();
                        },
                        child: const CircleAvatar(
                            radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 16, color: Colors.white)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 36,
                    child: TextFormField(
                      initialValue: p.caption,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                          hintText: hint, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8)),
                      onChanged: (v) => p.caption = v,
                    ),
                  ),
                ]),
              ),
            ),
          if (photos.length < max)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final path = await pickPhoto(context);
                if (path != null) {
                  photos.add(PhotoEntry(path));
                  onChanged();
                }
              },
              child: Container(
                width: 110,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.outlineVariant, width: 1.5),
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_a_photo, color: scheme.primary),
                  const SizedBox(height: 4),
                  Text('Add photo', style: TextStyle(fontSize: 12, color: scheme.primary)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
