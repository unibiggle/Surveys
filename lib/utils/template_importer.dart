import 'package:uuid/uuid.dart';

import '../models/template_schema.dart';

class TemplateImporter {
  static TemplateSchema parseLiftBasicTxt(String text) {
    final uuid = const Uuid();

    final lines = text
        .split(RegExp(r"\r?\n"))
        .map((l) => l.trimRight())
        .where((l) => l.trim().isNotEmpty)
        .where((l) => !RegExp(r'^\d+\/\d+$').hasMatch(l.trim()))
        .toList();

    final sections = <TemplateSection>[];
    TemplateSection? currentSection;

    bool isHeading(String l) {
      // Known section headings from the PDF
      const heads = {
        'Title Page',
        'Lift Details',
        'Doors',
        'Lift Motor room',
        'Hydraulic',
        'Counterweight',
      };
      return heads.contains(l.trim());
    }

    final qRe = RegExp(r'^(\*\s*)?(.*?)\s+(Text\s*answer|Select\s*one|Date\/?time)\s*(\*)?\s*$', caseSensitive: false);

    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();

      if (isHeading(line)) {
        currentSection = TemplateSection(id: uuid.v4(), title: line, items: []);
        sections.add(currentSection);
        i++;
        continue;
      }

      // Question start: prefer lines that explicitly include a type token,
      // or start with '* ' (required marker), or end with ' *' (user-edited required marker).
      // Avoid catching document title lines or option lines starting with '['.
      final looksLikeQuestion = qRe.hasMatch(line) || line.startsWith('* ') || line.endsWith(' *');
      if (looksLikeQuestion) {
        // Try regex parse first
        String? typeToken;
        String raw = line;
        int j = i;
        String label;
        bool requiredFlag = false;
        final m = qRe.firstMatch(line);
        if (m != null) {
          requiredFlag = (m.group(1) != null) || (m.group(4) != null);
          label = (m.group(2) ?? '').trim();
          final t = (m.group(3) ?? '').toLowerCase();
          if (t.contains('select') && t.contains('one')) typeToken = 'Select one';
          else if (t.contains('date')) typeToken = 'Date/time';
          else typeToken = 'Text answer';
        } else {
          // Fallback to previous heuristic across next couple of lines
          // capture label and type tokens possibly spread across lines
          int lookahead = 0;
          while (!raw.toLowerCase().contains('text answer') &&
              !raw.toLowerCase().contains('select one') &&
              !raw.toLowerCase().contains('date') &&
              j + 1 < lines.length &&
              lookahead < 2) {
            if (lines[j + 1].startsWith('[') || isHeading(lines[j + 1])) break;
            j++;
            lookahead++;
            raw = raw + ' ' + lines[j].trim();
          }
          if (raw.toLowerCase().contains('text answer')) typeToken = 'Text answer';
          if (raw.toLowerCase().contains('select one')) typeToken = 'Select one';
          if (raw.toLowerCase().contains('date')) typeToken = 'Date/time';

          // Extract label up to the type token (if present)
          label = raw;
          for (final t in ['Text answer', 'Select one', 'Date/time']) {
            if (label.contains(t)) {
              label = label.substring(0, label.indexOf(t)).trim();
              break;
            }
          }
          if (label.startsWith('*')) {
            label = label.substring(1).trim();
            requiredFlag = true;
          }
          if (label.endsWith(' *')) {
            label = label.substring(0, label.length - 2).trimRight();
            requiredFlag = true;
          }
        }

        // Determine type
        QuestionType qType = QuestionType.text;
        if (typeToken == 'Select one') qType = QuestionType.singleChoice;
        if (typeToken == 'Date/time') qType = QuestionType.text; // no date type in schema

        // Gather options if needed
        final options = <String>[];
        int k = j + 1;
        if (qType == QuestionType.singleChoice && k < lines.length) {
          while (k < lines.length) {
            final optLine = lines[k].trim();
            if (!optLine.startsWith('[') && !optLine.startsWith('(')) break;
            var text = optLine;
            // Strip [ ] or ( ) markers
            text = text.replaceFirst(RegExp(r'^\[\s*\]'), '').replaceFirst(RegExp(r'^\(\s*\)'), '').trim();
            if (text.toLowerCase().startsWith('score')) {
              k++;
              continue; // skip score rows
            }
            // Drop trailing ": _____" placeholders
            final cleaned = text.replaceAll(RegExp(r':\s*_+\s*$'), '').trim();
            options.add(cleaned);
            k++;
          }
        }

        // Detect yes/no/na set
        final yesNoSet = {'Yes', 'No', 'N/A'};
        if (options.isNotEmpty && options.toSet().containsAll(yesNoSet) && yesNoSet.containsAll(options.toSet())) {
          qType = QuestionType.yesNoNa;
        }

        // If singleChoice but no options parsed, fallback to text
        if (qType == QuestionType.singleChoice && options.isEmpty) {
          qType = QuestionType.text;
        }

        // Ensure we have a section
        currentSection ??= TemplateSection(id: uuid.v4(), title: 'General', items: []);
        if (!sections.contains(currentSection)) sections.add(currentSection!);

        currentSection!.items.add(QuestionItem(
          id: uuid.v4(),
          type: qType,
          label: label,
          required: requiredFlag,
          options: qType == QuestionType.singleChoice ? (options.isEmpty ? null : options) : null,
          allowAttachment: label.toLowerCase().contains('comment') || label.toLowerCase().contains('notes'),
        ));

        // advance pointer
        i = (qType == QuestionType.singleChoice) ? k : (j + 1);
        continue;
      }

      i++;
    }

    return TemplateSchema(
      id: '',
      name: 'Lift survey (BASIC)',
      version: 1,
      sections: sections.isEmpty
          ? [TemplateSection(id: uuid.v4(), title: 'Lift survey (BASIC)', items: [])]
          : sections,
    );
  }
}
