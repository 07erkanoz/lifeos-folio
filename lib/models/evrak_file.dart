import 'dart:io';
import 'dart:typed_data';

enum EvrakFormat {
  pdf,
  spreadsheet,
  udf,
  docx,
  tif,
  image,
  text,
  odt,
  rtf,
  doc,
  html,
  markdown,
  data,
  svg,
  unknown;

  static EvrakFormat fromExtension(String ext) {
    switch (ext.toLowerCase().replaceAll('.', '')) {
      case 'xlsx':
        return EvrakFormat.spreadsheet;
      case 'pdf':
        return EvrakFormat.pdf;
      case 'udf':
        return EvrakFormat.udf;
      case 'docx':
        return EvrakFormat.docx;
      case 'tif':
      case 'tiff':
        return EvrakFormat.tif;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'bmp':
      case 'gif':
      case 'heic':
      case 'heif':
        return EvrakFormat.image;
      case 'txt':
        return EvrakFormat.text;
      case 'odt':
        return EvrakFormat.odt;
      case 'rtf':
        return EvrakFormat.rtf;
      case 'doc':
        return EvrakFormat.doc;
      case 'html':
      case 'htm':
        return EvrakFormat.html;
      case 'md':
      case 'markdown':
        return EvrakFormat.markdown;
      case 'csv':
      case 'tsv':
      case 'json':
      case 'xml':
      case 'log':
        return EvrakFormat.data;
      case 'svg':
        return EvrakFormat.svg;
      default:
        return EvrakFormat.unknown;
    }
  }

  String get label {
    switch (this) {
      case EvrakFormat.spreadsheet:
        return 'Excel XLSX';
      case EvrakFormat.pdf:
        return 'PDF';
      case EvrakFormat.udf:
        return 'UYAP UDF';
      case EvrakFormat.docx:
        return 'Word DOCX';
      case EvrakFormat.tif:
        return 'TIFF Evrak';
      case EvrakFormat.image:
        return 'Görsel';
      case EvrakFormat.text:
        return 'Metin';
      case EvrakFormat.odt:
        return 'OpenDocument';
      case EvrakFormat.rtf:
        return 'Zengin Metin RTF';
      case EvrakFormat.doc:
        return 'Word 97-2003';
      case EvrakFormat.html:
        return 'HTML';
      case EvrakFormat.markdown:
        return 'Markdown';
      case EvrakFormat.data:
        return 'Veri / Metin';
      case EvrakFormat.svg:
        return 'SVG';
      case EvrakFormat.unknown:
        return 'Bilinmeyen';
    }
  }

  String get defaultExtension {
    switch (this) {
      case EvrakFormat.spreadsheet:
        return 'xlsx';
      case EvrakFormat.pdf:
        return 'pdf';
      case EvrakFormat.udf:
        return 'udf';
      case EvrakFormat.docx:
        return 'docx';
      case EvrakFormat.tif:
        return 'tif';
      case EvrakFormat.image:
        return 'png';
      case EvrakFormat.text:
        return 'txt';
      case EvrakFormat.odt:
        return 'odt';
      case EvrakFormat.rtf:
        return 'rtf';
      case EvrakFormat.doc:
        // Nothing here writes the old binary format; a document edited from
        // one is saved in a format that can be written.
        return 'udf';
      case EvrakFormat.html:
        return 'html';
      case EvrakFormat.markdown:
        return 'md';
      case EvrakFormat.data:
        return 'txt';
      case EvrakFormat.svg:
        return 'svg';
      case EvrakFormat.unknown:
        return '';
    }
  }

  bool get canEdit => [
    pdf,
    udf,
    docx,
    rtf,
    doc,
    text,
    odt,
    html,
    markdown,
    data,
    spreadsheet,
  ].contains(this);
  bool get usesPlainTextEditor => [html, markdown, data].contains(this);
  bool get isVisual => [image, tif, svg].contains(this);
  String get groupLabel => isVisual
      ? 'Görseller'
      : this == data
      ? 'Veri dosyaları'
      : 'Belgeler';
  static const supportedExtensions = [
    'xlsx',
    'pdf',
    'udf',
    'docx',
    'txt',
    'odt',
    'rtf',
    'doc',
    'html',
    'htm',
    'md',
    'markdown',
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
    'gif',
    'heic',
    'heif',
    'tif',
    'tiff',
    'svg',
    'csv',
    'tsv',
    'json',
    'xml',
    'log',
  ];

  /// Bu formattan hangi hedeflere dönüştürülebilir?
  List<EvrakFormat> get availableConversions {
    switch (this) {
      case EvrakFormat.pdf:
        return [EvrakFormat.docx, EvrakFormat.udf, EvrakFormat.text];
      case EvrakFormat.udf:
        return [EvrakFormat.pdf, EvrakFormat.docx, EvrakFormat.text];
      case EvrakFormat.docx:
        return [EvrakFormat.pdf, EvrakFormat.udf, EvrakFormat.text];
      case EvrakFormat.tif:
        return [EvrakFormat.pdf];
      case EvrakFormat.image:
        return [EvrakFormat.image, EvrakFormat.tif, EvrakFormat.pdf];
      case EvrakFormat.text:
        return [EvrakFormat.pdf, EvrakFormat.docx, EvrakFormat.udf];
      case EvrakFormat.doc:
        return [
          EvrakFormat.pdf,
          EvrakFormat.docx,
          EvrakFormat.udf,
          EvrakFormat.rtf,
          EvrakFormat.text,
        ];
      case EvrakFormat.rtf:
        return [
          EvrakFormat.pdf,
          EvrakFormat.docx,
          EvrakFormat.udf,
          EvrakFormat.text,
        ];
      case EvrakFormat.odt:
      case EvrakFormat.html:
      case EvrakFormat.markdown:
        return [EvrakFormat.pdf, EvrakFormat.text];
      case EvrakFormat.spreadsheet:
      case EvrakFormat.data:
      case EvrakFormat.svg:
      case EvrakFormat.unknown:
        return [];
    }
  }
}

class EvrakFile {
  final String path;
  final String name;
  final EvrakFormat format;
  final int sizeInBytes;
  Uint8List? cachedBytes;
  int? pageCount;
  bool isLoading;
  String? error;

  EvrakFile({
    required this.path,
    required this.name,
    required this.format,
    required this.sizeInBytes,
    this.cachedBytes,
    this.pageCount,
    this.isLoading = false,
    this.error,
  });

  static Future<EvrakFile> fromPathAsync(String path) async {
    final name = path.replaceAll('\\', '/').split('/').last;
    final stat = await File(path).stat();
    return EvrakFile(
      path: path,
      name: name,
      format: EvrakFormat.fromExtension(name.split('.').last),
      sizeInBytes: stat.size < 0 ? 0 : stat.size,
    );
  }

  static EvrakFile fromPath(String filePath) {
    final file = File(filePath);
    final name = filePath.replaceAll('\\', '/').split('/').last;
    final dotIndex = name.lastIndexOf('.');
    final ext = dotIndex != -1 ? name.substring(dotIndex + 1) : '';
    final format = EvrakFormat.fromExtension(ext);
    int size = 0;
    try {
      size = file.lengthSync();
    } catch (_) {}

    return EvrakFile(
      path: filePath,
      name: name,
      format: format,
      sizeInBytes: size,
    );
  }

  List<EvrakFormat> get conversionTargets => format.availableConversions
      .where(
        (target) =>
            name.split('.').last.toLowerCase() != target.defaultExtension,
      )
      .where(
        (target) =>
            !['gif', 'webp'].contains(name.split('.').last.toLowerCase()) ||
            target == EvrakFormat.pdf,
      )
      .toList();
  bool get canOptimize =>
      format == EvrakFormat.pdf ||
      format == EvrakFormat.tif ||
      ['png', 'jpg', 'jpeg'].contains(name.split('.').last.toLowerCase());

  String get readableSize {
    if (sizeInBytes < 1024) return '$sizeInBytes B';
    if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get baseName {
    final dotIndex = name.lastIndexOf('.');
    return dotIndex != -1 ? name.substring(0, dotIndex) : name;
  }
}
