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
      title: 'Image to Excel',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff1f7568)),
      home: const Directionality(textDirection: TextDirection.rtl, child: HomePage()),
    );
  }
}

class InvoiceRow {
  String item;
  String qty;
  String price;
  String total;
  InvoiceRow(this.item, {this.qty = '', this.price = '', this.total = ''});
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final picker = ImagePicker();
  final textController = TextEditingController();
  final rows = <InvoiceRow>[];
  bool ready = false;
  bool busy = false;
  String status = 'اضغط تجهيز التطبيق ثم اختر صورة أو صوّر فاتورة.';

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  void prepareApp() {
    setState(() {
      ready = true;
      status = 'جاهز. اختر صورة أو صوّر فاتورة.';
    });
  }

  Future<void> scan(ImageSource source) async {
    try {
      setState(() { busy = true; status = 'جاري قراءة الصورة...'; });
      final file = await picker.pickImage(source: source, imageQuality: 95);
      if (file == null) {
        setState(() => status = 'لم يتم اختيار صورة.');
        return;
      }
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(InputImage.fromFilePath(file.path));
      await recognizer.close();
      textController.text = normalizeNumbers(result.text.trim());
      parseText();
    } catch (_) {
      setState(() => status = 'تعذر قراءة الصورة. جرّب صورة أوضح.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void parseText() {
    final parsed = parseInvoice(textController.text);
    setState(() {
      rows.clear();
      rows.addAll(parsed);
      status = parsed.isEmpty ? 'لم يتم تكوين جدول. عدّل النص أو أضف صفوفًا يدويًا.' : 'تم استخراج ${parsed.length} صف.';
    });
  }

  String normalizeNumbers(String v) {
    const a = '٠١٢٣٤٥٦٧٨٩';
    const p = '۰۱۲۳۴۵۶۷۸۹';
    var out = v;
    for (var i = 0; i < 10; i++) {
      out = out.replaceAll(a[i], '$i').replaceAll(p[i], '$i');
    }
    return out;
  }

  List<InvoiceRow> parseInvoice(String text) {
    final result = <InvoiceRow>[];
    final ignore = RegExp(r'(total|subtotal|tax|vat|receipt|invoice|المجموع|الاجمالي|الإجمالي|الضريبة|فاتورة)', caseSensitive: false);
    final lines = text.split('\n').map((e) => e.trim()).where((e) => e.length > 1);
    for (final line in lines) {
      if (ignore.hasMatch(line)) continue;
      final nums = RegExp(r'\d+(?:[\.,]\d+)?').allMatches(line).map((m) => m.group(0)!.replaceAll(',', '.')).toList();
      if (nums.isEmpty) continue;
      var item = line.replaceAll(RegExp(r'\d+(?:[\.,]\d+)?'), ' ');
      item = item.replaceAll(RegExp(r'[xX×*=]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (item.isEmpty) item = 'صنف ${result.length + 1}';
      if (nums.length >= 3) {
        result.add(InvoiceRow(item, qty: nums[0], price: nums[1], total: nums.last));
      } else if (nums.length == 2) {
        result.add(InvoiceRow(item, price: nums[0], total: nums[1]));
      } else {
        result.add(InvoiceRow(item, total: nums[0]));
      }
    }
    return result;
  }

  Future<void> exportExcel() async {
    if (rows.isEmpty) return;
    final book = xls.Excel.createExcel();
    final sheet = book['Invoice'];
    sheet.appendRow(['Item', 'Qty', 'Price', 'Total']);
    for (final r in rows) {
      sheet.appendRow([r.item, r.qty, r.price, r.total]);
    }
    final bytes = book.encode();
    if (bytes == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/invoice_table.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> exportCsv() async {
    if (rows.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/invoice_table.csv');
    final b = StringBuffer('Item,Qty,Price,Total\n');
    for (final r in rows) {
      b.writeln('"${csv(r.item)}","${csv(r.qty)}","${csv(r.price)}","${csv(r.total)}"');
    }
    await file.writeAsString(b.toString());
    await Share.shareXFiles([XFile(file.path)]);
  }

  String csv(String s) => s.replaceAll('"', '""');

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
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('تحويل الفاتورة إلى جدول Excel', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(status),
                  const SizedBox(height: 12),
                  if (!ready) FilledButton.icon(onPressed: prepareApp, icon: const Icon(Icons.verified_user), label: const Text('تجهيز التطبيق')),
                  if (ready) ...[
                    FilledButton.icon(onPressed: busy ? null : () => scan(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('تصوير فاتورة')),
                    OutlinedButton.icon(onPressed: busy ? null : () => scan(ImageSource.gallery), icon: const Icon(Icons.photo), label: const Text('اختيار صورة')),
                  ],
                  if (busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: textController, minLines: 4, maxLines: 8, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'النص المقروء')),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(onPressed: parseText, icon: const Icon(Icons.auto_fix_high), label: const Text('تحليل النص')),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: rows.isEmpty ? null : exportExcel, icon: const Icon(Icons.table_chart), label: const Text('Excel'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: rows.isEmpty ? null : exportCsv, icon: const Icon(Icons.description), label: const Text('CSV'))),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => setState(() => rows.add(InvoiceRow('صنف جديد'))), icon: const Icon(Icons.add), label: const Text('إضافة صف')),
            ...rows.asMap().entries.map((e) => rowCard(e.key, e.value)),
          ],
        ),
      ),
    );
  }

  Widget rowCard(int index, InvoiceRow row) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [Text('صف ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)), const Spacer(), IconButton(onPressed: () => setState(() => rows.removeAt(index)), icon: const Icon(Icons.delete_outline))]),
          field('الصنف', row.item, (v) => row.item = v),
          Row(children: [Expanded(child: field('الكمية', row.qty, (v) => row.qty = v)), const SizedBox(width: 6), Expanded(child: field('السعر', row.price, (v) => row.price = v)), const SizedBox(width: 6), Expanded(child: field('الإجمالي', row.total, (v) => row.total = v))]),
        ]),
      ),
    );
  }

  Widget field(String label, String value, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(initialValue: value, onChanged: onChanged, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true)),
    );
  }
}
