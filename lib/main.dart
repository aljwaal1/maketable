import 'dart:io';
import 'dart:ui' as ui;
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExcelScannerApp());
}

class ExcelScannerApp extends StatelessWidget {
  const ExcelScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      title: 'صورة إلى Excel',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff137C72)),
      ),
      home: const Directionality(
        textDirection: ui.TextDirection.rtl,
        child: ScannerHomePage(),
      ),
    );
  }
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key});

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

class _ScannerHomePageState extends State<ScannerHomePage> {
  final ImagePicker _picker = ImagePicker();
  final List<ReceiptRow> _rows = [];
  final List<String> _rawLines = [];
  File? _imageFile;
  bool _busy = false;
  String _status = 'صوّر فاتورة كاش أو اختر صورة من المعرض.';

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _busy = true;
      _status = source == ImageSource.camera ? 'جاري فتح الكاميرا...' : 'جاري اختيار الصورة...';
    });

    try {
      if (source == ImageSource.camera) {
        await Permission.camera.request();
      }
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 2200,
      );
      if (picked == null) {
        setState(() {
          _busy = false;
          _status = 'لم يتم اختيار صورة.';
        });
        return;
      }
      _imageFile = File(picked.path);
      await _runOcr(_imageFile!);
    } catch (e) {
      setState(() {
        _busy = false;
        _status = 'حدث خطأ أثناء قراءة الصورة: $e';
      });
    }
  }

  Future<void> _runOcr(File file) async {
    setState(() => _status = 'جاري قراءة النص من الصورة...');
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(file);
      final recognized = await recognizer.processImage(inputImage);
      final parsed = ReceiptParser.parse(recognized);
      setState(() {
        _rawLines
          ..clear()
          ..addAll(parsed.rawLines);
        _rows
          ..clear()
          ..addAll(parsed.rows);
        _busy = false;
        _status = _rows.isEmpty
            ? 'تم استخراج النص، لكن لم أجد صفوف فاتورة واضحة. يمكنك إضافة صف يدويًا أو فتح النص الخام.'
            : 'تم تجهيز ${_rows.length} صف. راجع الجدول ثم صدّره إلى Excel.';
      });
    } finally {
      await recognizer.close();
    }
  }

  void _addRow() {
    setState(() => _rows.add(ReceiptRow(item: '', quantity: '', unitPrice: '', total: '', note: '')));
  }

  void _deleteRow(int index) {
    setState(() => _rows.removeAt(index));
  }

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) {
      _snack('لا يوجد جدول للتصدير.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'جاري إنشاء ملف Excel...';
    });
    try {
      final directory = await getApplicationDocumentsDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final path = '${directory.path}/receipt_$stamp.xlsx';
      final file = await ExcelExporter.exportXlsx(_rows, path);
      setState(() {
        _busy = false;
        _status = 'تم إنشاء ملف Excel بنجاح.';
      });
      await Share.shareXFiles([XFile(file.path)], text: 'ملف Excel من تطبيق صورة إلى Excel');
    } catch (e) {
      setState(() {
        _busy = false;
        _status = 'فشل إنشاء Excel: $e';
      });
    }
  }

  Future<void> _exportCsv() async {
    if (_rows.isEmpty) {
      _snack('لا يوجد جدول للتصدير.');
      return;
    }
    final directory = await getApplicationDocumentsDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final path = '${directory.path}/receipt_$stamp.csv';
    final buffer = StringBuffer('الصنف,الكمية,سعر الوحدة,الإجمالي,ملاحظة\n');
    for (final r in _rows) {
      buffer.writeln([r.item, r.quantity, r.unitPrice, r.total, r.note].map(_csv).join(','));
    }
    final file = await File(path).writeAsString(buffer.toString());
    await Share.shareXFiles([XFile(file.path)], text: 'ملف CSV من تطبيق صورة إلى Excel');
  }

  String _csv(String value) => '"${value.replaceAll('"', '""')}"';

  void _showRawText() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * .65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('النص الخام المستخرج', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(_rawLines.isEmpty ? 'لا يوجد نص.' : _rawLines.join('\n')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F7F6),
      appBar: AppBar(
        title: const Text('صورة إلى Excel'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _TopCard(
              status: _status,
              busy: _busy,
              onCamera: () => _pick(ImageSource.camera),
              onGallery: () => _pick(ImageSource.gallery),
              onRaw: _showRawText,
            ),
            if (_imageFile != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.file(_imageFile!, height: 110, fit: BoxFit.cover, width: double.infinity),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(child: _ReceiptTable(rows: _rows, onDelete: _deleteRow)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRow,
        icon: const Icon(Icons.add),
        label: const Text('صف'),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(blurRadius: 12, color: Colors.black12)]),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _exportExcel,
                icon: const Icon(Icons.table_chart),
                label: const Text('تصدير Excel'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _exportCsv,
              icon: const Icon(Icons.description),
              label: const Text('CSV'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopCard extends StatelessWidget {
  const _TopCard({required this.status, required this.busy, required this.onCamera, required this.onGallery, required this.onRaw});
  final String status;
  final bool busy;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onRaw;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.document_scanner, size: 36, color: Color(0xff137C72)),
              const SizedBox(width: 10),
              const Expanded(child: Text('حوّل الفاتورة أو الصورة إلى جدول قابل للتعديل', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              if (busy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 10),
          Text(status, style: const TextStyle(color: Colors.black87)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: FilledButton.icon(onPressed: busy ? null : onCamera, icon: const Icon(Icons.camera_alt), label: const Text('تصوير'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(onPressed: busy ? null : onGallery, icon: const Icon(Icons.photo), label: const Text('معرض'))),
              IconButton(onPressed: onRaw, icon: const Icon(Icons.text_snippet), tooltip: 'النص الخام'),
            ],
          )
        ],
      ),
    );
  }
}

class _ReceiptTable extends StatelessWidget {
  const _ReceiptTable({required this.rows, required this.onDelete});
  final List<ReceiptRow> rows;
  final void Function(int index) onDelete;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('لا توجد صفوف بعد. صوّر فاتورة أو أضف صفًا يدويًا.', textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(radius: 15, child: Text('${index + 1}')),
                    const SizedBox(width: 8),
                    Expanded(child: _Cell(label: 'الصنف / البيان', initial: row.item, onChanged: (v) => row.item = v)),
                    IconButton(onPressed: () => onDelete(index), icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _Cell(label: 'الكمية', initial: row.quantity, onChanged: (v) => row.quantity = v, keyboard: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: _Cell(label: 'سعر الوحدة', initial: row.unitPrice, onChanged: (v) => row.unitPrice = v, keyboard: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: _Cell(label: 'الإجمالي', initial: row.total, onChanged: (v) => row.total = v, keyboard: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 8),
                _Cell(label: 'ملاحظة', initial: row.note, onChanged: (v) => row.note = v),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Cell extends StatefulWidget {
  const _Cell({required this.label, required this.initial, required this.onChanged, this.keyboard});
  final String label;
  final String initial;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboard;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: widget.keyboard,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        filled: true,
        fillColor: const Color(0xffF7FAFA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
  }
}

class ReceiptRow {
  ReceiptRow({required this.item, required this.quantity, required this.unitPrice, required this.total, required this.note});
  String item;
  String quantity;
  String unitPrice;
  String total;
  String note;
}

class ParsedReceipt {
  ParsedReceipt({required this.rows, required this.rawLines});
  final List<ReceiptRow> rows;
  final List<String> rawLines;
}

class ReceiptParser {
  static ParsedReceipt parse(RecognizedText recognized) {
    final raw = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final clean = _normalize(line.text).trim();
        if (clean.isNotEmpty) raw.add(clean);
      }
    }
    final rows = <ReceiptRow>[];
    for (final line in raw) {
      final row = _parseLine(line);
      if (row != null) rows.add(row);
    }
    return ParsedReceipt(rows: rows, rawLines: raw);
  }

  static ReceiptRow? _parseLine(String line) {
    final lower = line.toLowerCase();
    final totalWords = ['total', 'subtotal', 'tax', 'vat', 'cash', 'change', 'balance', 'amount', 'المجموع', 'الاجمالي', 'الإجمالي', 'الضريبة', 'المدفوع', 'الباقي'];
    final hasTotalWord = totalWords.any(lower.contains);
    final numbers = RegExp(r'[-+]?\d+(?:[\.,]\d+)?').allMatches(line).map((m) => m.group(0)!.replaceAll(',', '.')).toList();
    if (numbers.isEmpty) return null;

    var textPart = line.replaceAll(RegExp(r'[-+]?\d+(?:[\.,]\d+)?'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    textPart = textPart.replaceAll(RegExp(r'[xX×*=]+'), ' ').trim();

    if (hasTotalWord && numbers.isNotEmpty) {
      return ReceiptRow(item: textPart.isEmpty ? 'إجمالي / بيان' : textPart, quantity: '', unitPrice: '', total: numbers.last, note: 'ملخص');
    }

    if (numbers.length >= 3) {
      return ReceiptRow(item: textPart, quantity: numbers[numbers.length - 3], unitPrice: numbers[numbers.length - 2], total: numbers.last, note: '');
    }
    if (numbers.length == 2) {
      return ReceiptRow(item: textPart, quantity: '1', unitPrice: numbers.first, total: numbers.last, note: '');
    }
    if (numbers.length == 1 && textPart.length > 2) {
      return ReceiptRow(item: textPart, quantity: '1', unitPrice: '', total: numbers.first, note: 'سطر بسعر واحد');
    }
    return null;
  }

  static String _normalize(String value) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value;
    for (var i = 0; i < 10; i++) {
      result = result.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    return result
        .replaceAll('٫', '.')
        .replaceAll('٬', ',')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class ExcelExporter {
  static Future<File> exportXlsx(List<ReceiptRow> rows, String path) async {
    final excel = Excel.createExcel();
    final sheet = excel['الفاتورة'];
    excel.setDefaultSheet('الفاتورة');
    final headers = ['الصنف', 'الكمية', 'سعر الوحدة', 'الإجمالي', 'ملاحظة'];
    for (var c = 0; c < headers.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).value = TextCellValue(headers[c]);
    }
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final values = [row.item, row.quantity, row.unitPrice, row.total, row.note];
      for (var c = 0; c < values.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value = TextCellValue(values[c]);
      }
    }
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }
    final bytes = excel.save();
    if (bytes == null) throw Exception('لم يتم إنشاء الملف');
    return File(path).writeAsBytes(bytes, flush: true);
  }
}
