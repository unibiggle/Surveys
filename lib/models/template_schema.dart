import 'dart:convert';

enum QuestionType {
  text,
  yesNoNa,
  singleChoice,
  multiChoice,
  dropdown,
  likert5,
  dateTime,
  number,
  checkbox,
  media,
  slider,
  annotation,
  signature,
  sketch,
  location,
  person,
  instruction,
  // Future types: rating custom, ranking, matrix, number, date, signature, photo, sketch
}

class VisibleCondition {
  final String questionId;
  final String op; // equals | notEquals | contains
  final String value;
  const VisibleCondition({required this.questionId, required this.op, required this.value});

  Map<String, dynamic> toJson() => {
        'questionId': questionId,
        'op': op,
        'value': value,
      };

  static VisibleCondition fromJson(Map<String, dynamic> json) => VisibleCondition(
        questionId: json['questionId'] as String,
        op: (json['op'] as String?) ?? 'equals',
        value: (json['value']?.toString() ?? ''),
      );
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
    case 'number':
      return QuestionType.number;
    case 'checkbox':
      return QuestionType.checkbox;
    case 'media':
      return QuestionType.media;
    case 'slider':
      return QuestionType.slider;
    case 'annotation':
      return QuestionType.annotation;
    case 'signature':
      return QuestionType.signature;
    case 'sketch':
      return QuestionType.sketch;
    case 'location':
      return QuestionType.location;
    case 'person':
      return QuestionType.person;
    case 'instruction':
      return QuestionType.instruction;
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
    case QuestionType.number:
      return 'number';
    case QuestionType.checkbox:
      return 'checkbox';
    case QuestionType.media:
      return 'media';
    case QuestionType.slider:
      return 'slider';
    case QuestionType.annotation:
      return 'annotation';
    case QuestionType.signature:
      return 'signature';
    case QuestionType.sketch:
      return 'sketch';
    case QuestionType.location:
      return 'location';
    case QuestionType.person:
      return 'person';
    case QuestionType.instruction:
      return 'instruction';
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
  final List<VisibleCondition>? visibleIf;

  TemplateSection({
    required this.id,
    required this.title,
    this.description,
    required this.items,
    this.visibleIf,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'items': items.map((e) => e.toJson()).toList(),
        if (visibleIf != null) 'visibleIf': visibleIf!.map((e) => e.toJson()).toList(),
      };

  static TemplateSection fromJson(Map<String, dynamic> json) => TemplateSection(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        items: (json['items'] as List<dynamic>)
            .map((e) => QuestionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        visibleIf: (json['visibleIf'] as List<dynamic>?)
            ?.map((e) => VisibleCondition.fromJson(e as Map<String, dynamic>))
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
  final bool multiLine; // for long text answers
  final List<VisibleCondition>? visibleIf; // AND semantics

  QuestionItem({
    required this.id,
    required this.type,
    required this.label,
    this.required = false,
    this.options,
    this.allowAttachment = false,
    this.multiLine = false,
    this.visibleIf,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': questionTypeToString(type),
        'label': label,
        'required': required,
        'options': options,
        'allowAttachment': allowAttachment,
        'multiLine': multiLine,
        if (visibleIf != null) 'visibleIf': visibleIf!.map((e) => e.toJson()).toList(),
      };

  static QuestionItem fromJson(Map<String, dynamic> json) => QuestionItem(
        id: json['id'] as String,
        type: questionTypeFromString(json['type'] as String),
        label: json['label'] as String,
        required: (json['required'] as bool?) ?? false,
        options: (json['options'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
        allowAttachment: (json['allowAttachment'] as bool?) ?? false,
        multiLine: (json['multiLine'] as bool?) ?? false,
        visibleIf: (json['visibleIf'] as List<dynamic>?)
            ?.map((e) => VisibleCondition.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
