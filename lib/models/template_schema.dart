import 'dart:convert';

enum QuestionType {
  text,
  yesNoNa,
  singleChoice,
  multiChoice,
  dropdown,
  likert5,
  dateTime,
  // Future types: rating custom, ranking, matrix, number, date, signature, photo, sketch
}

QuestionType questionTypeFromString(String s) {
  switch (s) {
    case 'text':
      return QuestionType.text;
    case 'yesNoNa':
      return QuestionType.yesNoNa;
    case 'singleChoice':
      return QuestionType.singleChoice;
    case 'multiChoice':
      return QuestionType.multiChoice;
    case 'dropdown':
      return QuestionType.dropdown;
    case 'likert5':
      return QuestionType.likert5;
    case 'dateTime':
      return QuestionType.dateTime;
    default:
      return QuestionType.text;
  }
}

String questionTypeToString(QuestionType t) {
  switch (t) {
    case QuestionType.text:
      return 'text';
    case QuestionType.yesNoNa:
      return 'yesNoNa';
    case QuestionType.singleChoice:
      return 'singleChoice';
    case QuestionType.multiChoice:
      return 'multiChoice';
    case QuestionType.dropdown:
      return 'dropdown';
    case QuestionType.likert5:
      return 'likert5';
    case QuestionType.dateTime:
      return 'dateTime';
  }
}

class TemplateSchema {
  final String id; // UUID (same as template id in DB)
  final String name;
  final int version;
  final List<TemplateSection> sections;
  final String? brandName;
  final String? brandLogoUrl;
  final String? brandLogoStoragePath;

  TemplateSchema({
    required this.id,
    required this.name,
    required this.version,
    required this.sections,
    this.brandName,
    this.brandLogoUrl,
    this.brandLogoStoragePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'sections': sections.map((e) => e.toJson()).toList(),
        if (brandName != null) 'brandName': brandName,
        if (brandLogoUrl != null) 'brandLogoUrl': brandLogoUrl,
        if (brandLogoStoragePath != null) 'brandLogoStoragePath': brandLogoStoragePath,
      };

  static TemplateSchema fromJson(Map<String, dynamic> json) => TemplateSchema(
        id: json['id'] as String,
        name: json['name'] as String,
        version: (json['version'] as num).toInt(),
        sections: (json['sections'] as List<dynamic>)
            .map((e) => TemplateSection.fromJson(e as Map<String, dynamic>))
            .toList(),
        brandName: json['brandName'] as String?,
        brandLogoUrl: json['brandLogoUrl'] as String?,
        brandLogoStoragePath: json['brandLogoStoragePath'] as String?,
      );

  static String encode(TemplateSchema schema) => jsonEncode(schema.toJson());
  static TemplateSchema decode(String s) => fromJson(jsonDecode(s) as Map<String, dynamic>);
}

class TemplateSection {
  final String id; // UUID
  final String title;
  final String? description;
  final List<QuestionItem> items;

  TemplateSection({
    required this.id,
    required this.title,
    this.description,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'items': items.map((e) => e.toJson()).toList(),
      };

  static TemplateSection fromJson(Map<String, dynamic> json) => TemplateSection(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        items: (json['items'] as List<dynamic>)
            .map((e) => QuestionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class QuestionItem {
  final String id; // UUID
  final QuestionType type;
  final String label;
  final bool required; // enforce required answers
  final List<String>? options; // used for singleChoice
  final bool allowAttachment; // allow photo attachments on this question

  QuestionItem({
    required this.id,
    required this.type,
    required this.label,
    this.required = false,
    this.options,
    this.allowAttachment = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': questionTypeToString(type),
        'label': label,
        'required': required,
        'options': options,
        'allowAttachment': allowAttachment,
      };

  static QuestionItem fromJson(Map<String, dynamic> json) => QuestionItem(
        id: json['id'] as String,
        type: questionTypeFromString(json['type'] as String),
        label: json['label'] as String,
        required: (json['required'] as bool?) ?? false,
        options: (json['options'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
        allowAttachment: (json['allowAttachment'] as bool?) ?? false,
      );
}
