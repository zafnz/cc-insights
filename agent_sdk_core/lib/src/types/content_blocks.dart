/// Content blocks that appear in assistant and user messages.
sealed class ContentBlock {
  const ContentBlock();

  String get type;

  /// Convert the content block to JSON.
  Map<String, dynamic> toJson();

  /// Parse a content block from JSON.
  static ContentBlock fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;

    switch (type) {
      case 'text':
        return TextBlock.fromJson(json);
      case 'thinking':
        return ThinkingBlock.fromJson(json);
      case 'tool_use':
        return ToolUseBlock.fromJson(json);
      case 'tool_result':
        return ToolResultBlock.fromJson(json);
      case 'image':
        return ImageBlock.fromJson(json);
      case 'audio':
        return AudioBlock.fromJson(json);
      case 'resource':
        return ResourceBlock.fromJson(json);
      case 'resource_link':
        return ResourceLinkBlock.fromJson(json);
      default:
        return UnknownBlock.fromJson(json);
    }
  }
}

/// Text content block.
class TextBlock extends ContentBlock {
  const TextBlock({required this.text});

  @override
  String get type => 'text';
  final String text;

  factory TextBlock.fromJson(Map<String, dynamic> json) {
    return TextBlock(text: json['text'] as String? ?? '');
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'text': text,
      };
}

/// Thinking content block (extended thinking).
class ThinkingBlock extends ContentBlock {
  const ThinkingBlock({
    required this.thinking,
    required this.signature,
  });

  @override
  String get type => 'thinking';
  final String thinking;
  final String signature;

  factory ThinkingBlock.fromJson(Map<String, dynamic> json) {
    return ThinkingBlock(
      thinking: json['thinking'] as String? ?? '',
      signature: json['signature'] as String? ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'thinking': thinking,
        'signature': signature,
      };
}

/// Tool use content block.
class ToolUseBlock extends ContentBlock {
  const ToolUseBlock({
    required this.id,
    required this.name,
    required this.input,
  });

  @override
  String get type => 'tool_use';
  final String id;
  final String name;
  final Map<String, dynamic> input;

  factory ToolUseBlock.fromJson(Map<String, dynamic> json) {
    return ToolUseBlock(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      input: json['input'] as Map<String, dynamic>? ?? {},
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'name': name,
        'input': input,
      };
}

/// Tool result content block.
class ToolResultBlock extends ContentBlock {
  const ToolResultBlock({
    required this.toolUseId,
    this.content,
    this.isError,
  });

  @override
  String get type => 'tool_result';
  final String toolUseId;
  final dynamic content; // String, List<ContentBlock>, or null
  final bool? isError;

  factory ToolResultBlock.fromJson(Map<String, dynamic> json) {
    return ToolResultBlock(
      toolUseId: json['tool_use_id'] as String? ?? '',
      content: json['content'],
      isError: json['is_error'] as bool?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'tool_use_id': toolUseId,
        if (content != null) 'content': content,
        if (isError != null) 'is_error': isError,
      };
}

/// Image content block.
class ImageBlock extends ContentBlock {
  const ImageBlock({
    required this.source,
    this.format = ImageBlockFormat.anthropic,
  });

  @override
  String get type => 'image';
  final ImageSource source;
  final ImageBlockFormat format;

  factory ImageBlock.fromJson(Map<String, dynamic> json) {
    final sourceRaw = json['source'];
    if (sourceRaw is Map<String, dynamic>) {
      return ImageBlock(
        source: ImageSource.fromJson(sourceRaw),
        format: ImageBlockFormat.anthropic,
      );
    }
    if (sourceRaw is Map) {
      return ImageBlock(
        source: ImageSource.fromJson(Map<String, dynamic>.from(sourceRaw)),
        format: ImageBlockFormat.anthropic,
      );
    }

    final data = json['data'] as String?;
    final uri = json['uri'] as String?;
    final mimeType =
        json['mimeType'] as String? ?? json['mime_type'] as String?;

    if (data != null && data.isNotEmpty) {
      return ImageBlock(
        source: ImageSource(
          type: 'base64',
          mediaType: mimeType,
          data: data,
        ),
        format: ImageBlockFormat.acp,
      );
    }
    if (uri != null && uri.isNotEmpty) {
      return ImageBlock(
        source: ImageSource(
          type: 'url',
          mediaType: mimeType,
          url: uri,
        ),
        format: ImageBlockFormat.acp,
      );
    }

    return ImageBlock(
      source: ImageSource.fromJson(const {}),
      format: ImageBlockFormat.anthropic,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    if (format == ImageBlockFormat.acp) {
      return {
        'type': type,
        if (source.data != null) 'data': source.data,
        if (source.url != null) 'uri': source.url,
        if (source.mediaType != null) 'mimeType': source.mediaType,
      };
    }
    return {
      'type': type,
      'source': source.toJson(),
    };
  }
}

enum ImageBlockFormat {
  anthropic,
  acp,
}

/// Image source (base64 or URL).
class ImageSource {
  const ImageSource({
    required this.type,
    this.mediaType,
    this.data,
    this.url,
  });

  final String type; // 'base64' or 'url'
  final String? mediaType;
  final String? data;
  final String? url;

  factory ImageSource.fromJson(Map<String, dynamic> json) {
    return ImageSource(
      type: json['type'] as String? ?? 'base64',
      mediaType: json['media_type'] as String?,
      data: json['data'] as String?,
      url: json['url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (mediaType != null) 'media_type': mediaType,
        if (data != null) 'data': data,
        if (url != null) 'url': url,
      };
}

/// Audio content block.
class AudioBlock extends ContentBlock {
  const AudioBlock({
    this.data,
    this.mimeType,
    this.uri,
  });

  @override
  String get type => 'audio';
  final String? data;
  final String? mimeType;
  final String? uri;

  factory AudioBlock.fromJson(Map<String, dynamic> json) {
    return AudioBlock(
      data: json['data'] as String?,
      mimeType: json['mimeType'] as String? ?? json['mime_type'] as String?,
      uri: json['uri'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (data != null) 'data': data,
        if (mimeType != null) 'mimeType': mimeType,
        if (uri != null) 'uri': uri,
      };
}

/// Resource content block.
class ResourceBlock extends ContentBlock {
  const ResourceBlock({
    required this.uri,
    required this.name,
    this.size,
    this.title,
    this.contents,
  });

  @override
  String get type => 'resource';
  final String uri;
  final String name;
  final int? size;
  final String? title;
  final dynamic contents;

  factory ResourceBlock.fromJson(Map<String, dynamic> json) {
    return ResourceBlock(
      uri: json['uri'] as String? ?? '',
      name: json['name'] as String? ?? '',
      size: (json['size'] as num?)?.toInt(),
      title: json['title'] as String?,
      contents: json['contents'],
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'uri': uri,
        'name': name,
        if (size != null) 'size': size,
        if (title != null) 'title': title,
        if (contents != null) 'contents': contents,
      };
}

/// Resource link content block.
class ResourceLinkBlock extends ContentBlock {
  const ResourceLinkBlock({
    required this.uri,
    this.mimeType,
  });

  @override
  String get type => 'resource_link';
  final String uri;
  final String? mimeType;

  factory ResourceLinkBlock.fromJson(Map<String, dynamic> json) {
    return ResourceLinkBlock(
      uri: json['uri'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? json['mime_type'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'uri': uri,
        if (mimeType != null) 'mimeType': mimeType,
      };
}

/// Unknown content block type (fallback).
class UnknownBlock extends ContentBlock {
  const UnknownBlock({
    required this.rawType,
    required this.raw,
  });

  final String rawType;
  @override
  String get type => rawType;
  final Map<String, dynamic> raw;

  factory UnknownBlock.fromJson(Map<String, dynamic> json) {
    return UnknownBlock(
      rawType: json['type'] as String? ?? 'unknown',
      raw: json,
    );
  }

  @override
  Map<String, dynamic> toJson() => raw;
}
