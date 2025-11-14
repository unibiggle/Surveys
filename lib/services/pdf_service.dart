import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfService {
  static Future<Uint8List> buildSurveyPdf({
    required String title,
    required List<Map<String, String>> qaPairs, // [{question, answer}]
  }) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(title, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Divider(),
          ...qaPairs.map((qa) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(qa['question'] ?? '', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.Text(qa['answer'] ?? '-', style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              )),
        ],
      ),
    );
    return pdf.save();
  }

  static Future<void> shareSurveyPdf({required String title, required List<Map<String, String>> qaPairs}) async {
    final bytes = await buildSurveyPdf(title: title, qaPairs: qaPairs);
    await Printing.sharePdf(bytes: bytes, filename: '${title.replaceAll(' ', '_')}.pdf');
  }

  // Rich export that supports notes, actions (summary), and embedded images per question.
  // items: [{ 'question': String, 'answer': String, 'note': String?, 'images': List<Uint8List> }]
  // actions: [{ 'question': String, 'action': String }]
  static Future<Uint8List> buildSurveyPdfRich({
    required String title,
    required List<Map<String, dynamic>> items,
    List<Map<String, String>>? actions,
  }) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          final widgets = <pw.Widget>[];
          widgets.add(pw.Text(title, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)));
          widgets.add(pw.SizedBox(height: 8));
          if (actions != null && actions.isNotEmpty) {
            widgets.add(pw.Text('Actions', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)));
            widgets.add(pw.SizedBox(height: 4));
            widgets.addAll(actions.map((a) => pw.Bullet(text: "${a['question']}: ${a['action']}")));
            widgets.add(pw.SizedBox(height: 12));
          }
          widgets.add(pw.Divider());

          for (final it in items) {
            final question = (it['question'] as String?) ?? '';
            final answer = (it['answer'] as String?) ?? '-';
            final note = (it['note'] as String?) ?? '';
            final imgs = (it['images'] as List<Uint8List>? ?? const []);

            widgets.add(pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(question, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(answer, style: const pw.TextStyle(fontSize: 12)),
                  if (note.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text('Note: $note', style: const pw.TextStyle(fontSize: 11)),
                  ],
                  if (imgs.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: imgs
                          .map((b) => pw.Container(
                                width: 150,
                                height: 150,
                                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
                                child: pw.FittedBox(child: pw.Image(pw.MemoryImage(b), fit: pw.BoxFit.cover)),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ));
          }
          return widgets;
        },
      ),
    );
    return pdf.save();
  }

  static Future<void> shareSurveyPdfRich({
    required String title,
    required List<Map<String, dynamic>> items,
    List<Map<String, String>>? actions,
  }) async {
    final bytes = await buildSurveyPdfRich(title: title, items: items, actions: actions);
    await Printing.sharePdf(bytes: bytes, filename: '${title.replaceAll(' ', '_')}.pdf');
  }
}
