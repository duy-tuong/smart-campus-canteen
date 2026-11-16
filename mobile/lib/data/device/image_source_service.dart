import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Ảnh người dùng vừa chọn (đã nén) — sẵn sàng tải lên máy chủ.
class PickedImage {
  const PickedImage({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

enum PickSource { camera, gallery }

/// Chọn ảnh (chụp mới hoặc từ thư viện). Tách thành interface để test không cần camera thật.
abstract interface class ImageSourceService {
  /// null nếu người dùng hủy.
  Future<PickedImage?> pick(PickSource source);
}

class DeviceImageSource implements ImageSourceService {
  DeviceImageSource([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedImage?> pick(PickSource source) async {
    // Thu nhỏ + nén ngay trên máy: ảnh đại diện chỉ cần ~800px, luôn dưới giới hạn 2 MB của máy chủ.
    final file = await _picker.pickImage(
      source: source == PickSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.front,
    );
    if (file == null) return null;
    return PickedImage(bytes: await file.readAsBytes(), fileName: file.name);
  }
}
