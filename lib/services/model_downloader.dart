import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class ModelDownloader {
  final Dio _dio = Dio();
  CancelToken? _cancelToken;

  /// Downloads the model from [url] to the app's document directory.
  /// Supports resuming partial downloads.
  Future<void> downloadModel({
    required String url,
    required String fileName,
    required Function(double progress, String speed, String sizeInfo) onProgress,
    required VoidCallback onComplete,
    required Function(String error) onError,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final savePath = '${directory.path}/$fileName';
      final file = File(savePath);

      int downloadedBytes = 0;
      if (await file.exists()) {
        downloadedBytes = await file.length();
      }

      _cancelToken = CancelToken();
      
      // Get file total size first if possible, or just start download
      final response = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            if (downloadedBytes > 0) 'range': 'bytes=$downloadedBytes-',
          },
        ),
        cancelToken: _cancelToken,
      );

      final totalBytes = int.tryParse(response.headers.value('content-length') ?? '0') ?? 0;
      final fullSize = totalBytes + downloadedBytes;

      final IOSink sink = file.openWrite(mode: downloadedBytes > 0 ? FileMode.append : FileMode.write);
      
      int currentDownloaded = downloadedBytes;
      DateTime lastTime = DateTime.now();
      int lastBytes = downloadedBytes;

      await response.data.stream.listen(
        (List<int> chunk) {
          sink.add(chunk);
          currentDownloaded += chunk.length;

          final now = DateTime.now();
          final duration = now.difference(lastTime).inMilliseconds;
          
          if (duration >= 500) { // Update every 500ms
            final double progress = fullSize > 0 ? currentDownloaded / fullSize : 0;
            
            // Speed calculation
            final bytesSinceLast = currentDownloaded - lastBytes;
            final speedKBps = (bytesSinceLast / duration) * 1000 / 1024;
            final speedText = speedKBps > 1024 
                ? '${(speedKBps / 1024).toStringAsFixed(2)} MB/s' 
                : '${speedKBps.toStringAsFixed(1)} KB/s';

            final sizeText = '${(currentDownloaded / 1024 / 1024 / 1024).toStringAsFixed(2)} GB / ${(fullSize / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';

            onProgress(progress, speedText, sizeText);
            
            lastTime = now;
            lastBytes = currentDownloaded;
          }
        },
        onDone: () async {
          await sink.close();
          onComplete();
        },
        onError: (e) async {
          await sink.close();
          onError(e.toString());
        },
        cancelOnError: true,
      ).asFuture();

    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        onError('Download paused');
      } else {
        onError(e.toString());
      }
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel('User cancelled');
  }
}
