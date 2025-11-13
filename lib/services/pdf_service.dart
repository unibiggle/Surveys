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
}

