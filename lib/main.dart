import 'dart:io';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
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
      title: 'صورة إلى Excel',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xff26786a),
        fontFamily: 'Roboto',
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: HomePage(),
      ),
    );
  }
}

class InvoiceRow {
  String item;
  String qty;
  String unitPrice;
  String total;
  InvoiceRow({required this.item, this.qty = '', this.unitPrice = '', this.total = ''});
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _rawController = TextEditingController();
  final List<InvoiceRow> _rows = [];
  bool _busy = false;
  String _status = 'اختر صورة فاتورة أو جدول، أو الصق النص يدويًا للتجربة.';

  @override
  void dispose() {
    _rawController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      setState(() {
        _busy = true;
        _status = 'جاري فتح الصورة وقراءة النص...';
      });
      final XFile? file = await _picker.pickImage(source: source, imageQuality: 95);
      if (file == null) {
        setState(() => _status = 'لم يتم اختيار صورة.');
        return;
      }
      final inputImage = InputImage.fromFilePath(file.path);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(inputImage);
      await recognizer.close();
      _rawController.text = result.text.trim();
      _parseText();
    } catch (e) {
      setState(() => _status = 'حدث خطأ أثناء القراءة. جرّب صورة أوضح أو استخدم الإدخال اليدوي.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _parseText() {
    final text = _normalizeNumbers(_rawController.text);
    final parsed = _parseInvoice(text);
    setState(() {
      _rows
        ..clear()
        ..addAll(parsed);
      _status = parsed.isEmpty
          ? 'لم أستطع تكوين جدول تلقائيًا. أضف الصفوف يدويًا أو عدّل النص ثم اضغط تحليل.'
          : 'تم استخراج ${parsed.length} صف. راجع الجدول قبل التصدير.';
    });
  }

  List<InvoiceRow> _parseInvoice(String text) {
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.length > 1)
        .toList();
    final rows = <InvoiceRow>[];
    final skipWords = RegExp(r'(total|subtotal|tax|vat|cash|visa|change|invoice|receipt|المجموع|الإجمالي|الضريبة|فاتورة|نقد|مدفوع)', caseSensitive: false);

    for (final line in lines) {
      if (skipWords.hasMatch(line)) continue;
      final nums = RegExp(r'[-+]?\d+(?:[\.,]\d+)?').allMatches(line).map((m) => m.group(0)!.replaceAll(',', '.')).toList();
      if (nums.isEmpty) continue;
      var item = line.replaceAll(RegExp(r'[-+]?\d+(?:[\.,]\d+)?'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      item = item.replaceAll(RegExp(r'[xX×*=]'), ' ').trim();
      if (item.isEmpty) item = 'صنف ${rows.length + 1}';
      String qty = '';
      String unit = '';
      String total = '';
      if (nums.length >= 3) {
        qty = nums[0];
        unit = nums[1];
        total = nums.last;
      } else if (nums.length == 2) {
        unit = nums[0];
        total = nums[1];
      } else {
        total = nums[0];
      }
      rows.add(InvoiceRow(item: item, qty: qty, unitPrice: unit, total: total));
    }
    return rows;
  }

  String _normalizeNumbers(String input) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var out = input;
    for (var i = 0; i < 10; i++) {
      out = out.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    return out;
  }

  void _addRow() {
    setState(() => _rows.add(InvoiceRow(item: 'صنف جديد')));
  }

  Future<void> _exportCsv() async {
    if (_rows.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/invoice_table.csv');
    final b = StringBuffer('item,quantity,unit_price,total\n');
    for (final r in _rows) {
      b.writeln('"${_csv(r.item)}","${_csv(r.qty)}","${_csv(r.unitPrice)}","${_csv(r.total)}"');
    }
    await file.writeAsString(b.toString());
    await Share.shareXFiles([XFile(file.path)], text: 'ملف CSV من تطبيق صورة إلى Excel');
  }

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) return;
    final book = xls.Excel.createExcel();
    final sheet = book['Invoice'];
    sheet.cell(xls.CellIndex.indexByString('A1')).value = 'الصنف';
    sheet.cell(xls.CellIndex.indexByString('B1')).value = 'الكمية';
    sheet.cell(xls.CellIndex.indexByString('C1')).value = 'سعر الوحدة';
    sheet.cell(xls.CellIndex.indexByString('D1')).value = 'الإجمالي';
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final excelRow = i + 2;
      sheet.cell(xls.CellIndex.indexByString('A$excelRow')).value = row.item;
      sheet.cell(xls.CellIndex.indexByString('B$excelRow')).value = row.qty;
      sheet.cell(xls.CellIndex.indexByString('C$excelRow')).value = row.unitPrice;
      sheet.cell(xls.CellIndex.indexByString('D$excelRow')).value = row.total;
    }
    final bytes = book.encode();
    if (bytes == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/invoice_table.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'ملف Excel من تطبيق صورة إلى Excel');
  }

  String _csv(String value) => value.replaceAll('"', '""');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('صورة إلى Excel')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('حوّل فاتورة كاش أو جدول إلى Excel', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_status),
                    const SizedBox(height: 12),
                    if (_busy) const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    FilledButton.icon(onPressed: _busy ? null : () => _pick(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('تصوير فاتورة')),
                    OutlinedButton.icon(onPressed: _busy ? null : () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('اختيار صورة')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _rawController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'النص المقروء أو الإدخال اليدوي'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(onPressed: _parseText, icon: const Icon(Icons.auto_fix_high), label: const Text('تحليل النص إلى جدول')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: _rows.isEmpty ? null : _exportExcel, icon: const Icon(Icons.table_chart), label: const Text('تصدير Excel'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: _rows.isEmpty ? null : _exportCsv, icon: const Icon(Icons.description), label: const Text('CSV'))),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _addRow, icon: const Icon(Icons.add), label: const Text('إضافة صف يدويًا')),
            const SizedBox(height: 10),
            ..._rows.asMap().entries.map((entry) {
              final index = entry.key;
              final row = entry.value;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Row(children: [
                        Text('صف ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(onPressed: () => setState(() => _rows.removeAt(index)), icon: const Icon(Icons.delete_outline)),
                      ]),
                      _cell('الصنف', row.item, (v) => row.item = v),
                      Row(children: [
                        Expanded(child: _cell('الكمية', row.qty, (v) => row.qty = v)),
                        const SizedBox(width: 8),
                        Expanded(child: _cell('السعر', row.unitPrice, (v) => row.unitPrice = v)),
                        const SizedBox(width: 8),
                        Expanded(child: _cell('الإجمالي', row.total, (v) => row.total = v)),
                      ]),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _cell(String label, String value, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        initialValue: value,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      ),
    );
  }
}
