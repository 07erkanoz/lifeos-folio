class ViewerFileType {
  final String label;
  final List<String> extensions;
  final List<String> mimeTypes;
  const ViewerFileType(this.label, this.extensions, this.mimeTypes);

  static const supported = [
    ViewerFileType(
      'UYAP UDF',
      ['udf'],
      ['application/x-uyap-udf', 'application/udf', 'application/x-udf'],
    ),
    ViewerFileType(
      'Excel',
      ['xlsx'],
      ['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'],
    ),
    ViewerFileType('PDF', ['pdf'], ['application/pdf']),
    ViewerFileType(
      'Word',
      ['docx'],
      [
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      ],
    ),
    ViewerFileType(
      'OpenDocument',
      ['odt'],
      ['application/vnd.oasis.opendocument.text'],
    ),
    ViewerFileType('Düz metin', ['txt', 'log'], ['text/plain']),
    ViewerFileType('Markdown', ['md', 'markdown'], ['text/markdown']),
    ViewerFileType('HTML', ['html', 'htm'], ['text/html']),
    ViewerFileType('CSV', ['csv'], ['text/csv']),
    ViewerFileType('TSV', ['tsv'], ['text/tab-separated-values']),
    ViewerFileType('JSON', ['json'], ['application/json']),
    ViewerFileType('XML', ['xml'], ['application/xml', 'text/xml']),
    ViewerFileType('PNG', ['png'], ['image/png']),
    ViewerFileType('JPEG', ['jpg', 'jpeg'], ['image/jpeg']),
    ViewerFileType('TIFF', ['tif', 'tiff'], ['image/tiff']),
    ViewerFileType('WebP', ['webp'], ['image/webp']),
    ViewerFileType('GIF', ['gif'], ['image/gif']),
    ViewerFileType('BMP', ['bmp'], ['image/bmp']),
    ViewerFileType('SVG', ['svg'], ['image/svg+xml']),
  ];
}
