import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/media_ref.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

export 'package:respawnd1/core/models/media_ref.dart';

/// Picking, uploading and showing photos, videos and PDFs attached to
/// records (dose proof, carer updates, medical documents).

/// A photo, video or PDF chosen on the device, not yet uploaded.
class PickedMedia {
  const PickedMedia(this.file, {required this.isVideo, this.isDocument = false});

  final XFile file;
  final bool isVideo;
  final bool isDocument;

  String get extension {
    if (isDocument) return 'pdf';
    final dot = file.path.lastIndexOf('.');
    return dot == -1 ? (isVideo ? 'mp4' : 'jpg') : file.path.substring(dot + 1).toLowerCase();
  }

  String get contentType {
    if (isDocument) return 'application/pdf';
    if (isVideo) return 'video/${extension == 'mov' ? 'quicktime' : 'mp4'}';
    return 'image/jpeg';
  }
}

/// Asks for a photo or video (camera or gallery). [allowVideo] false offers
/// photos only; [allowDocument] adds a PDF from the device's files. Null if
/// dismissed.
Future<PickedMedia?> pickPhotoOrVideo(
  BuildContext context, {
  bool allowVideo = true,
  bool allowDocument = false,
  String title = 'Add a photo or video',
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      Widget tile(IconData icon, String label, String value) => ListTile(
            leading: Icon(icon, color: AppColors.textPrimary),
            title: Text(label, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
            onTap: () => Navigator.pop(ctx, value),
          );
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(title, style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            ),
            tile(Icons.camera_alt_outlined, 'Take a photo', 'photo_camera'),
            tile(Icons.photo_library_outlined, 'Choose a photo', 'photo_gallery'),
            if (allowVideo) ...[
              tile(Icons.videocam_outlined, 'Record a video', 'video_camera'),
              tile(Icons.video_library_outlined, 'Choose a video', 'video_gallery'),
            ],
            if (allowDocument) tile(Icons.picture_as_pdf_outlined, 'Choose a PDF', 'document'),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (choice == null) return null;
  if (choice == 'document') {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf']);
    return picked == null ? null : PickedMedia(picked.xFile, isVideo: false, isDocument: true);
  }
  final picker = ImagePicker();
  final XFile? file = switch (choice) {
    'photo_camera' => await picker.pickImage(source: ImageSource.camera, imageQuality: 85),
    'photo_gallery' => await picker.pickImage(source: ImageSource.gallery, imageQuality: 85),
    // Short clips keep uploads small on mobile data.
    'video_camera' => await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 2)),
    _ => await picker.pickVideo(source: ImageSource.gallery),
  };
  if (file == null) return null;
  return PickedMedia(file, isVideo: choice.startsWith('video'));
}

/// Uploads [media] to `{folder}/{name}.{ext}` and returns its download URL.
Future<MediaRef> uploadMedia(PickedMedia media, {required String folder, required String name}) async {
  final ref = FirebaseStorage.instance.ref('$folder/$name.${media.extension}');
  final metadata = SettableMetadata(contentType: media.contentType);
  if (media.isDocument) {
    // A picked file can be a content:// URI on Android, so send its bytes.
    await ref.putData(await media.file.readAsBytes(), metadata);
  } else {
    await ref.putFile(File(media.file.path), metadata);
  }
  return MediaRef(await ref.getDownloadURL(), isVideo: media.isVideo, isDocument: media.isDocument);
}

/// Uploads every item in [media] under [folder], named `{prefix}_{i}`.
Future<List<MediaRef>> uploadAllMedia(List<PickedMedia> media, {required String folder, required String prefix}) async {
  return [
    for (var i = 0; i < media.length; i++) await uploadMedia(media[i], folder: folder, name: '${prefix}_$i'),
  ];
}

/// The form row for attaching photos or PDFs of prescriptions, vet notes or
/// other documents before a record is saved.
class AttachmentPicker extends StatelessWidget {
  const AttachmentPicker({
    super.key,
    required this.items,
    required this.onChanged,
    this.label = 'Attach prescription or document (photo or PDF)',
    this.max = 4,
    this.enabled = true,
    this.allowDocument = true,
  });

  final List<PickedMedia> items;
  final ValueChanged<List<PickedMedia>> onChanged;
  final String label;
  final int max;
  final bool enabled;
  final bool allowDocument;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++)
          InputChip(
            avatar: Icon(items[i].isDocument ? Icons.picture_as_pdf_outlined : Icons.photo_outlined, size: 18),
            label: Text(items[i].isDocument ? 'PDF ${i + 1}' : 'Photo ${i + 1}'),
            onDeleted: enabled ? () => onChanged([...items]..removeAt(i)) : null,
          ),
        if (items.length < max)
          OutlinedButton.icon(
            onPressed: !enabled
                ? null
                : () async {
                    final picked =
                        await pickPhotoOrVideo(context, allowVideo: false, allowDocument: allowDocument, title: label);
                    if (picked != null) onChanged([...items, picked]);
                  },
            style: AppButtons.outline,
            icon: const Icon(Icons.attach_file, size: 18),
            label: Text(items.isEmpty ? label : 'Attach another'),
          ),
      ],
    );
  }
}

/// A row of tappable thumbnails. Photos open full screen; videos play; PDFs
/// open in the device's PDF viewer.
class MediaThumbStrip extends StatelessWidget {
  const MediaThumbStrip({super.key, required this.media, this.size = 64});

  final List<MediaRef> media;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final m in media) MediaThumb(media: m, size: size)],
    );
  }
}

class MediaThumb extends StatelessWidget {
  const MediaThumb({super.key, required this.media, this.size = 64});

  final MediaRef media;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (media.isDocument) {
      return Semantics(
        button: true,
        label: 'Open PDF',
        child: InkWell(
          onTap: () => showMediaViewer(context, media),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.slaterspwn),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.picture_as_pdf_outlined, color: AppColors.error, size: size * 0.42),
                if (size >= 56) Text('PDF', style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
    }
    final placeholder = Container(
      width: size,
      height: size,
      color: AppColors.textPrimary,
      child: Icon(media.isVideo ? Icons.play_circle_outline : Icons.broken_image_outlined,
          color: AppColors.background, size: size * 0.45),
    );
    return Semantics(
      button: true,
      label: media.isVideo ? 'Play video' : 'View photo',
      child: InkWell(
        onTap: () => showMediaViewer(context, media),
        borderRadius: BorderRadius.circular(10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: media.isVideo
              ? placeholder
              : Image.network(media.url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
        ),
      ),
    );
  }
}

/// Full-screen photo or video. A PDF opens in the device's viewer instead.
Future<void> showMediaViewer(BuildContext context, MediaRef media) async {
  if (media.isDocument) {
    final ok = await launchUrl(Uri.parse(media.url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showAppError(context, 'Could not open this PDF.');
    }
    return;
  }
  if (!context.mounted) return;
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Center(
            child: media.isVideo
                ? _VideoView(url: media.url)
                : InteractiveViewer(maxScale: 5, child: Image.network(media.url, fit: BoxFit.contain)),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
        ],
      ),
    ),
  );
}

class _VideoView extends StatefulWidget {
  const _VideoView({required this.url});

  final String url;

  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  late final VideoPlayerController _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller.initialize().then((_) {
      if (mounted) setState(() {});
      _controller.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Text('Could not play this video.', style: GoogleFonts.zain(fontSize: 14, color: Colors.white));
    }
    if (!_controller.value.isInitialized) return const CircularProgressIndicator(color: Colors.white);
    return GestureDetector(
      onTap: () => setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play()),
      child: AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)),
    );
  }
}
