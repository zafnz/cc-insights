import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:test/test.dart';

void main() {
  test('parses resource_link content blocks', () {
    final block = ContentBlock.fromJson({
      'type': 'resource_link',
      'uri': 'file:///docs/readme.md',
      'mimeType': 'text/markdown',
    });

    expect(block, isA<ResourceLinkBlock>());
    final resource = block as ResourceLinkBlock;
    expect(resource.uri, 'file:///docs/readme.md');
    expect(resource.mimeType, 'text/markdown');
    expect(resource.toJson(), {
      'type': 'resource_link',
      'uri': 'file:///docs/readme.md',
      'mimeType': 'text/markdown',
    });
  });

  test('parses resource content blocks', () {
    final block = ContentBlock.fromJson({
      'type': 'resource',
      'uri': 'file:///docs/spec.pdf',
      'name': 'spec.pdf',
      'size': 120,
      'title': 'Spec',
      'contents': 'raw',
    });

    expect(block, isA<ResourceBlock>());
    final resource = block as ResourceBlock;
    expect(resource.uri, 'file:///docs/spec.pdf');
    expect(resource.name, 'spec.pdf');
    expect(resource.size, 120);
    expect(resource.title, 'Spec');
    expect(resource.contents, 'raw');
  });

  test('parses audio content blocks', () {
    final block = ContentBlock.fromJson({
      'type': 'audio',
      'data': 'abcd',
      'mimeType': 'audio/wav',
    });

    expect(block, isA<AudioBlock>());
    final audio = block as AudioBlock;
    expect(audio.data, 'abcd');
    expect(audio.mimeType, 'audio/wav');
    expect(audio.toJson(), {
      'type': 'audio',
      'data': 'abcd',
      'mimeType': 'audio/wav',
    });
  });

  test('parses ACP image blocks', () {
    final block = ContentBlock.fromJson({
      'type': 'image',
      'data': 'base64data',
      'mimeType': 'image/png',
    });

    expect(block, isA<ImageBlock>());
    final image = block as ImageBlock;
    expect(image.format, ImageBlockFormat.acp);
    expect(image.source.data, 'base64data');
    expect(image.source.mediaType, 'image/png');
    expect(image.toJson(), {
      'type': 'image',
      'data': 'base64data',
      'mimeType': 'image/png',
    });
  });

  test('parses anthropic image blocks', () {
    final block = ContentBlock.fromJson({
      'type': 'image',
      'source': {
        'type': 'base64',
        'media_type': 'image/png',
        'data': 'base64data',
      },
    });

    expect(block, isA<ImageBlock>());
    final image = block as ImageBlock;
    expect(image.format, ImageBlockFormat.anthropic);
    expect(image.toJson(), {
      'type': 'image',
      'source': {
        'type': 'base64',
        'media_type': 'image/png',
        'data': 'base64data',
      },
    });
  });
}
