import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:test/test.dart';

/// Fixed timestamp for tests.
final _ts = DateTime.utc(2025, 1, 15, 10, 30, 0);
const _provider = BackendProvider.claude;

void main() {
  group('InsightsEvent round-trip serialization', () {
    group('SessionInitEvent', () {
      test('with all fields', () {
        final event = SessionInitEvent(
          id: 'evt-1',
          timestamp: _ts,
          provider: _provider,
          raw: {'orig': 'data'},
          extensions: {'ext': 'value'},
          sessionId: 'session-abc',
          model: 'claude-sonnet-4-5',
          cwd: '/home/user/project',
          availableTools: ['Bash', 'Read', 'Write'],
          mcpServers: [
            McpServerStatus(
              name: 'my-server',
              status: McpStatus.connected,
              serverInfo: McpServerInfo(name: 'srv', version: '1.0'),
            ),
          ],
          permissionMode: 'default',
          account: AccountInfo(
            email: 'test@example.com',
            organization: 'TestOrg',
          ),
          slashCommands: [
            SlashCommand(
              name: 'help',
              description: 'Show help',
              argumentHint: '',
            ),
          ],
          availableModels: [
            ModelInfo(
              value: 'claude-sonnet-4-5',
              displayName: 'Sonnet',
              description: 'Fast model',
            ),
          ],
        );

        final json = event.toJson();
        expect(json['event'], 'session_init');
        expect(json['id'], 'evt-1');
        expect(json['provider'], 'claude');
        expect(json['raw'], {'orig': 'data'});
        expect(json['extensions'], {'ext': 'value'});

        final restored =
            InsightsEvent.fromJson(json) as SessionInitEvent;
        expect(restored.id, 'evt-1');
        expect(restored.timestamp, _ts);
        expect(restored.provider, _provider);
        expect(restored.raw, {'orig': 'data'});
        expect(restored.extensions, {'ext': 'value'});
        expect(restored.sessionId, 'session-abc');
        expect(restored.model, 'claude-sonnet-4-5');
        expect(restored.cwd, '/home/user/project');
        expect(restored.availableTools, ['Bash', 'Read', 'Write']);
        expect(restored.mcpServers, hasLength(1));
        expect(restored.mcpServers![0].name, 'my-server');
        expect(restored.mcpServers![0].status, McpStatus.connected);
        expect(restored.mcpServers![0].serverInfo!.name, 'srv');
        expect(restored.permissionMode, 'default');
        expect(restored.account!.email, 'test@example.com');
        expect(restored.slashCommands, hasLength(1));
        expect(restored.availableModels, hasLength(1));
      });

      test('with minimal fields', () {
        final event = SessionInitEvent(
          id: 'evt-1',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
        );

        final json = event.toJson();
        expect(json.containsKey('model'), isFalse);
        expect(json.containsKey('raw'), isFalse);

        final restored =
            InsightsEvent.fromJson(json) as SessionInitEvent;
        expect(restored.sessionId, 'session-abc');
        expect(restored.model, isNull);
        expect(restored.cwd, isNull);
        expect(restored.availableTools, isNull);
        expect(restored.mcpServers, isNull);
        expect(restored.account, isNull);
      });
    });

    group('SessionStatusEvent', () {
      test('with all fields', () {
        final event = SessionStatusEvent(
          id: 'evt-2',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          status: SessionStatus.compacting,
          message: 'Compacting context',
        );

        final json = event.toJson();
        expect(json['event'], 'session_status');
        expect(json['status'], 'compacting');

        final restored =
            InsightsEvent.fromJson(json) as SessionStatusEvent;
        expect(restored.sessionId, 'session-abc');
        expect(restored.status, SessionStatus.compacting);
        expect(restored.message, 'Compacting context');
      });

      test('with minimal fields', () {
        final event = SessionStatusEvent(
          id: 'evt-2',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          status: SessionStatus.ended,
        );

        final json = event.toJson();
        expect(json.containsKey('message'), isFalse);

        final restored =
            InsightsEvent.fromJson(json) as SessionStatusEvent;
        expect(restored.message, isNull);
      });

      test('all status values round-trip', () {
        for (final status in SessionStatus.values) {
          final event = SessionStatusEvent(
            id: 'evt-s',
            timestamp: _ts,
            provider: _provider,
            sessionId: 's',
            status: status,
          );
          final restored =
              InsightsEvent.fromJson(event.toJson()) as SessionStatusEvent;
          expect(restored.status, status);
        }
      });
    });

    group('TextEvent', () {
      test('with all fields', () {
        final event = TextEvent(
          id: 'evt-3',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          text: 'Hello world',
          kind: TextKind.text,
          parentCallId: 'tu-1',
          model: 'claude-sonnet-4-5',
        );

        final json = event.toJson();
        expect(json['event'], 'text');
        expect(json['kind'], 'text');

        final restored = InsightsEvent.fromJson(json) as TextEvent;
        expect(restored.text, 'Hello world');
        expect(restored.kind, TextKind.text);
        expect(restored.parentCallId, 'tu-1');
        expect(restored.model, 'claude-sonnet-4-5');
      });

      test('with minimal fields', () {
        final event = TextEvent(
          id: 'evt-3',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          text: 'Hi',
          kind: TextKind.thinking,
        );

        final json = event.toJson();
        expect(json.containsKey('parentCallId'), isFalse);
        expect(json.containsKey('model'), isFalse);

        final restored = InsightsEvent.fromJson(json) as TextEvent;
        expect(restored.kind, TextKind.thinking);
        expect(restored.parentCallId, isNull);
        expect(restored.model, isNull);
      });

      test('all TextKind values round-trip', () {
        for (final kind in TextKind.values) {
          final event = TextEvent(
            id: 'evt-k',
            timestamp: _ts,
            provider: _provider,
            sessionId: 's',
            text: 't',
            kind: kind,
          );
          final restored =
              InsightsEvent.fromJson(event.toJson()) as TextEvent;
          expect(restored.kind, kind);
        }
      });
    });

    group('UserInputEvent', () {
      test('with all fields', () {
        final event = UserInputEvent(
          id: 'evt-4',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          text: 'Fix the bug',
          images: [
            ImageData(mediaType: 'image/png', data: 'base64data'),
          ],
          isSynthetic: true,
        );

        final json = event.toJson();
        expect(json['event'], 'user_input');
        expect(json['isSynthetic'], true);

        final restored =
            InsightsEvent.fromJson(json) as UserInputEvent;
        expect(restored.text, 'Fix the bug');
        expect(restored.images, hasLength(1));
        expect(restored.images![0].mediaType, 'image/png');
        expect(restored.images![0].data, 'base64data');
        expect(restored.isSynthetic, true);
      });

      test('with minimal fields', () {
        final event = UserInputEvent(
          id: 'evt-4',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          text: 'Hello',
        );

        final json = event.toJson();
        expect(json.containsKey('images'), isFalse);
        expect(json.containsKey('isSynthetic'), isFalse);

        final restored =
            InsightsEvent.fromJson(json) as UserInputEvent;
        expect(restored.images, isNull);
        expect(restored.isSynthetic, false);
      });
    });

    group('ToolInvocationEvent', () {
      test('with all fields', () {
        final event = ToolInvocationEvent(
          id: 'evt-5',
          timestamp: _ts,
          provider: _provider,
          callId: 'tu-1',
          parentCallId: 'tu-0',
          sessionId: 'session-abc',
          kind: ToolKind.execute,
          toolName: 'Bash',
          title: 'Run tests',
          input: {'command': 'flutter test'},
          locations: ['/path/to/file.dart:10'],
          model: 'claude-sonnet-4-5',
        );

        final json = event.toJson();
        expect(json['event'], 'tool_invocation');
        expect(json['kind'], 'execute');

        final restored =
            InsightsEvent.fromJson(json) as ToolInvocationEvent;
        expect(restored.callId, 'tu-1');
        expect(restored.parentCallId, 'tu-0');
        expect(restored.kind, ToolKind.execute);
        expect(restored.toolName, 'Bash');
        expect(restored.title, 'Run tests');
        expect(restored.input, {'command': 'flutter test'});
        expect(restored.locations, ['/path/to/file.dart:10']);
        expect(restored.model, 'claude-sonnet-4-5');
      });

      test('with minimal fields', () {
        final event = ToolInvocationEvent(
          id: 'evt-5',
          timestamp: _ts,
          provider: _provider,
          callId: 'tu-1',
          sessionId: 'session-abc',
          kind: ToolKind.read,
          toolName: 'Read',
          input: {'file_path': '/tmp/test.txt'},
        );

        final json = event.toJson();
        expect(json.containsKey('parentCallId'), isFalse);
        expect(json.containsKey('title'), isFalse);
        expect(json.containsKey('locations'), isFalse);

        final restored =
            InsightsEvent.fromJson(json) as ToolInvocationEvent;
        expect(restored.parentCallId, isNull);
        expect(restored.title, isNull);
        expect(restored.locations, isNull);
      });
    });

    group('ToolCompletionEvent', () {
      test('with all fields', () {
        final event = ToolCompletionEvent(
          id: 'evt-6',
          timestamp: _ts,
          provider: _provider,
          callId: 'tu-1',
          sessionId: 'session-abc',
          status: ToolCallStatus.completed,
          output: 'file contents here',
          isError: false,
          content: [TextBlock(text: 'result text')],
          locations: ['/tmp/file.dart'],
        );

        final json = event.toJson();
        expect(json['event'], 'tool_completion');
        expect(json['status'], 'completed');

        final restored =
            InsightsEvent.fromJson(json) as ToolCompletionEvent;
        expect(restored.callId, 'tu-1');
        expect(restored.status, ToolCallStatus.completed);
        expect(restored.output, 'file contents here');
        expect(restored.isError, false);
        expect(restored.content, hasLength(1));
        expect(restored.content![0], isA<TextBlock>());
        expect((restored.content![0] as TextBlock).text, 'result text');
        expect(restored.locations, ['/tmp/file.dart']);
      });

      test('with minimal fields', () {
        final event = ToolCompletionEvent(
          id: 'evt-6',
          timestamp: _ts,
          provider: _provider,
          callId: 'tu-1',
          sessionId: 'session-abc',
          status: ToolCallStatus.failed,
        );

        final json = event.toJson();
        expect(json.containsKey('output'), isFalse);
        expect(json.containsKey('isError'), isFalse);
        expect(json.containsKey('content'), isFalse);

        final restored =
            InsightsEvent.fromJson(json) as ToolCompletionEvent;
        expect(restored.output, isNull);
        expect(restored.isError, false);
        expect(restored.content, isNull);
      });

      test('with dynamic output (map)', () {
        final event = ToolCompletionEvent(
          id: 'evt-6',
          timestamp: _ts,
          provider: _provider,
          callId: 'tu-1',
          sessionId: 'session-abc',
          status: ToolCallStatus.completed,
          output: {'key': 'value', 'count': 42},
        );

        final restored =
            InsightsEvent.fromJson(event.toJson()) as ToolCompletionEvent;
        expect(restored.output, {'key': 'value', 'count': 42});
      });

      test('with isError true', () {
        final event = ToolCompletionEvent(
          id: 'evt-6',
          timestamp: _ts,
          provider: _provider,
          callId: 'tu-1',
          sessionId: 'session-abc',
          status: ToolCallStatus.failed,
          isError: true,
          output: 'Error: command failed',
        );

        final json = event.toJson();
        expect(json['isError'], true);

        final restored =
            InsightsEvent.fromJson(json) as ToolCompletionEvent;
        expect(restored.isError, true);
      });
    });

    group('SubagentSpawnEvent', () {
      test('with all fields', () {
        final event = SubagentSpawnEvent(
          id: 'evt-7',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          callId: 'tu-2',
          agentType: 'flutter-engineer',
          description: 'Implement dark mode',
          isResume: true,
          resumeAgentId: 'agent-prev',
        );

        final json = event.toJson();
        expect(json['event'], 'subagent_spawn');

        final restored =
            InsightsEvent.fromJson(json) as SubagentSpawnEvent;
        expect(restored.callId, 'tu-2');
        expect(restored.agentType, 'flutter-engineer');
        expect(restored.description, 'Implement dark mode');
        expect(restored.isResume, true);
        expect(restored.resumeAgentId, 'agent-prev');
      });

      test('with minimal fields', () {
        final event = SubagentSpawnEvent(
          id: 'evt-7',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          callId: 'tu-2',
        );

        final json = event.toJson();
        expect(json.containsKey('agentType'), isFalse);
        expect(json.containsKey('isResume'), isFalse);

        final restored =
            InsightsEvent.fromJson(json) as SubagentSpawnEvent;
        expect(restored.agentType, isNull);
        expect(restored.isResume, false);
        expect(restored.resumeAgentId, isNull);
      });
    });

    group('SubagentCompleteEvent', () {
      test('with all fields', () {
        final event = SubagentCompleteEvent(
          id: 'evt-8',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          callId: 'tu-2',
          agentId: 'agent-123',
          status: 'completed',
          summary: 'Dark mode implemented successfully',
        );

        final json = event.toJson();
        expect(json['event'], 'subagent_complete');

        final restored =
            InsightsEvent.fromJson(json) as SubagentCompleteEvent;
        expect(restored.callId, 'tu-2');
        expect(restored.agentId, 'agent-123');
        expect(restored.status, 'completed');
        expect(restored.summary, 'Dark mode implemented successfully');
      });

      test('with minimal fields', () {
        final event = SubagentCompleteEvent(
          id: 'evt-8',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          callId: 'tu-2',
        );

        final json = event.toJson();
        expect(json.containsKey('agentId'), isFalse);
        expect(json.containsKey('status'), isFalse);
        expect(json.containsKey('summary'), isFalse);

        final restored =
            InsightsEvent.fromJson(json) as SubagentCompleteEvent;
        expect(restored.agentId, isNull);
        expect(restored.status, isNull);
        expect(restored.summary, isNull);
      });
    });

    group('TurnCompleteEvent', () {
      test('with all fields', () {
        final event = TurnCompleteEvent(
          id: 'evt-9',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          isError: true,
          subtype: 'error',
          errors: ['Something failed', 'Another error'],
          result: 'Turn completed with errors',
          costUsd: 0.0123,
          durationMs: 5000,
          durationApiMs: 4500,
          numTurns: 3,
          usage: TokenUsage(
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 200,
            cacheCreationTokens: 100,
          ),
          modelUsage: {
            'claude-sonnet-4-5': ModelTokenUsage(
              inputTokens: 1000,
              outputTokens: 500,
              cacheReadTokens: 200,
              cacheCreationTokens: 100,
              costUsd: 0.0123,
              contextWindow: 200000,
              webSearchRequests: 2,
            ),
          },
          permissionDenials: [
            PermissionDenial(
              toolName: 'Bash',
              toolUseId: 'tu-denied',
              toolInput: {'command': 'rm -rf /'},
            ),
          ],
        );

        final json = event.toJson();
        expect(json['event'], 'turn_complete');
        expect(json['isError'], true);
        expect(json['costUsd'], 0.0123);

        final restored =
            InsightsEvent.fromJson(json) as TurnCompleteEvent;
        expect(restored.sessionId, 'session-abc');
        expect(restored.isError, true);
        expect(restored.subtype, 'error');
        expect(restored.errors, ['Something failed', 'Another error']);
        expect(restored.result, 'Turn completed with errors');
        expect(restored.costUsd, 0.0123);
        expect(restored.durationMs, 5000);
        expect(restored.durationApiMs, 4500);
        expect(restored.numTurns, 3);
        expect(restored.usage!.inputTokens, 1000);
        expect(restored.usage!.outputTokens, 500);
        expect(restored.usage!.cacheReadTokens, 200);
        expect(restored.usage!.cacheCreationTokens, 100);
        expect(restored.modelUsage!['claude-sonnet-4-5']!.costUsd, 0.0123);
        expect(
          restored.modelUsage!['claude-sonnet-4-5']!.contextWindow,
          200000,
        );
        expect(
          restored.modelUsage!['claude-sonnet-4-5']!.webSearchRequests,
          2,
        );
        expect(restored.permissionDenials, hasLength(1));
        expect(restored.permissionDenials![0].toolName, 'Bash');
        expect(restored.permissionDenials![0].toolUseId, 'tu-denied');
      });

      test('with minimal fields', () {
        final event = TurnCompleteEvent(
          id: 'evt-9',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
        );

        final json = event.toJson();
        expect(json.containsKey('isError'), isFalse);
        expect(json.containsKey('costUsd'), isFalse);
        expect(json.containsKey('usage'), isFalse);
        expect(json.containsKey('modelUsage'), isFalse);

        final restored =
            InsightsEvent.fromJson(json) as TurnCompleteEvent;
        expect(restored.isError, false);
        expect(restored.costUsd, isNull);
        expect(restored.usage, isNull);
        expect(restored.modelUsage, isNull);
        expect(restored.permissionDenials, isNull);
      });
    });

    group('ContextCompactionEvent', () {
      test('with all fields', () {
        final event = ContextCompactionEvent(
          id: 'evt-10',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          trigger: CompactionTrigger.auto,
          preTokens: 150000,
          summary: 'Context was automatically compacted',
        );

        final json = event.toJson();
        expect(json['event'], 'context_compaction');
        expect(json['trigger'], 'auto');

        final restored =
            InsightsEvent.fromJson(json) as ContextCompactionEvent;
        expect(restored.trigger, CompactionTrigger.auto);
        expect(restored.preTokens, 150000);
        expect(restored.summary, 'Context was automatically compacted');
      });

      test('with minimal fields', () {
        final event = ContextCompactionEvent(
          id: 'evt-10',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          trigger: CompactionTrigger.manual,
        );

        final json = event.toJson();
        expect(json.containsKey('preTokens'), isFalse);
        expect(json.containsKey('summary'), isFalse);

        final restored =
            InsightsEvent.fromJson(json) as ContextCompactionEvent;
        expect(restored.preTokens, isNull);
        expect(restored.summary, isNull);
      });

      test('all CompactionTrigger values round-trip', () {
        for (final trigger in CompactionTrigger.values) {
          final event = ContextCompactionEvent(
            id: 'evt-t',
            timestamp: _ts,
            provider: _provider,
            sessionId: 's',
            trigger: trigger,
          );
          final restored = InsightsEvent.fromJson(event.toJson())
              as ContextCompactionEvent;
          expect(restored.trigger, trigger);
        }
      });
    });

    group('PermissionRequestEvent', () {
      test('with all fields', () {
        final event = PermissionRequestEvent(
          id: 'evt-11',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          requestId: 'req-42',
          toolName: 'Bash',
          toolKind: ToolKind.execute,
          toolInput: {'command': 'flutter test'},
          toolUseId: 'tu-5',
          reason: 'Needs shell access',
          blockedPath: '/restricted/path',
          suggestions: [
            PermissionSuggestionData(
              type: 'addRules',
              toolName: 'Bash',
              description: 'Allow Bash execution',
            ),
          ],
        );

        final json = event.toJson();
        expect(json['event'], 'permission_request');
        expect(json['toolKind'], 'execute');

        final restored =
            InsightsEvent.fromJson(json) as PermissionRequestEvent;
        expect(restored.requestId, 'req-42');
        expect(restored.toolName, 'Bash');
        expect(restored.toolKind, ToolKind.execute);
        expect(restored.toolInput, {'command': 'flutter test'});
        expect(restored.toolUseId, 'tu-5');
        expect(restored.reason, 'Needs shell access');
        expect(restored.blockedPath, '/restricted/path');
        expect(restored.suggestions, hasLength(1));
        expect(restored.suggestions![0].type, 'addRules');
        expect(restored.suggestions![0].toolName, 'Bash');
        expect(restored.suggestions![0].description, 'Allow Bash execution');
      });

      test('with minimal fields', () {
        final event = PermissionRequestEvent(
          id: 'evt-11',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          requestId: 'req-42',
          toolName: 'Read',
          toolKind: ToolKind.read,
          toolInput: {'file_path': '/tmp/test'},
        );

        final json = event.toJson();
        expect(json.containsKey('toolUseId'), isFalse);
        expect(json.containsKey('reason'), isFalse);
        expect(json.containsKey('blockedPath'), isFalse);
        expect(json.containsKey('suggestions'), isFalse);

        final restored =
            InsightsEvent.fromJson(json) as PermissionRequestEvent;
        expect(restored.toolUseId, isNull);
        expect(restored.reason, isNull);
        expect(restored.blockedPath, isNull);
        expect(restored.suggestions, isNull);
      });
    });

    group('StreamDeltaEvent', () {
      test('with all fields', () {
        final event = StreamDeltaEvent(
          id: 'evt-12',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          parentCallId: 'tu-1',
          kind: StreamDeltaKind.text,
          textDelta: 'Hello ',
          jsonDelta: '{"partial": true}',
          blockIndex: 0,
          callId: 'call-1',
        );

        final json = event.toJson();
        expect(json['event'], 'stream_delta');
        expect(json['kind'], 'text');

        final restored =
            InsightsEvent.fromJson(json) as StreamDeltaEvent;
        expect(restored.parentCallId, 'tu-1');
        expect(restored.kind, StreamDeltaKind.text);
        expect(restored.textDelta, 'Hello ');
        expect(restored.jsonDelta, '{"partial": true}');
        expect(restored.blockIndex, 0);
        expect(restored.callId, 'call-1');
      });

      test('with minimal fields', () {
        final event = StreamDeltaEvent(
          id: 'evt-12',
          timestamp: _ts,
          provider: _provider,
          sessionId: 'session-abc',
          kind: StreamDeltaKind.thinking,
        );

        final json = event.toJson();
        expect(json.containsKey('parentCallId'), isFalse);
        expect(json.containsKey('textDelta'), isFalse);
        expect(json.containsKey('jsonDelta'), isFalse);
        expect(json.containsKey('blockIndex'), isFalse);
        expect(json.containsKey('callId'), isFalse);

        final restored =
            InsightsEvent.fromJson(json) as StreamDeltaEvent;
        expect(restored.parentCallId, isNull);
        expect(restored.textDelta, isNull);
        expect(restored.jsonDelta, isNull);
        expect(restored.blockIndex, isNull);
        expect(restored.callId, isNull);
      });

      test('all StreamDeltaKind values round-trip', () {
        for (final kind in StreamDeltaKind.values) {
          final event = StreamDeltaEvent(
            id: 'evt-k',
            timestamp: _ts,
            provider: _provider,
            sessionId: 's',
            kind: kind,
          );
          final restored =
              InsightsEvent.fromJson(event.toJson()) as StreamDeltaEvent;
          expect(restored.kind, kind);
        }
      });
    });
  });

  group('InsightsEvent.fromJson error handling', () {
    test('throws ArgumentError for unknown event type', () {
      expect(
        () => InsightsEvent.fromJson({
          'event': 'unknown_event',
          'id': '1',
          'timestamp': _ts.toIso8601String(),
          'provider': 'claude',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('BackendProvider round-trip', () {
    test('all providers round-trip', () {
      for (final provider in BackendProvider.values) {
        final event = TextEvent(
          id: 'evt-p',
          timestamp: _ts,
          provider: provider,
          sessionId: 's',
          text: 't',
          kind: TextKind.text,
        );
        final restored = InsightsEvent.fromJson(event.toJson()) as TextEvent;
        expect(restored.provider, provider);
      }
    });
  });

  group('Supporting type serialization', () {
    test('TokenUsage round-trip', () {
      final usage = TokenUsage(
        inputTokens: 100,
        outputTokens: 50,
        cacheReadTokens: 20,
        cacheCreationTokens: 10,
      );
      final json = usage.toJson();
      final restored = TokenUsage.fromJson(json);
      expect(restored.inputTokens, 100);
      expect(restored.outputTokens, 50);
      expect(restored.cacheReadTokens, 20);
      expect(restored.cacheCreationTokens, 10);
    });

    test('TokenUsage minimal round-trip', () {
      final usage = TokenUsage(inputTokens: 100, outputTokens: 50);
      final json = usage.toJson();
      expect(json.containsKey('cacheReadTokens'), isFalse);
      final restored = TokenUsage.fromJson(json);
      expect(restored.cacheReadTokens, isNull);
      expect(restored.cacheCreationTokens, isNull);
    });

    test('ModelTokenUsage round-trip', () {
      final usage = ModelTokenUsage(
        inputTokens: 100,
        outputTokens: 50,
        cacheReadTokens: 20,
        cacheCreationTokens: 10,
        costUsd: 0.005,
        contextWindow: 200000,
        webSearchRequests: 3,
      );
      final json = usage.toJson();
      final restored = ModelTokenUsage.fromJson(json);
      expect(restored.inputTokens, 100);
      expect(restored.outputTokens, 50);
      expect(restored.costUsd, 0.005);
      expect(restored.contextWindow, 200000);
      expect(restored.webSearchRequests, 3);
    });

    test('PermissionDenial round-trip', () {
      final denial = PermissionDenial(
        toolName: 'Bash',
        toolUseId: 'tu-1',
        toolInput: {'command': 'rm -rf /'},
      );
      final json = denial.toJson();
      expect(json['tool_name'], 'Bash');
      final restored = PermissionDenial.fromJson(json);
      expect(restored.toolName, 'Bash');
      expect(restored.toolUseId, 'tu-1');
      expect(restored.toolInput, {'command': 'rm -rf /'});
    });

    test('ImageData round-trip', () {
      final img = ImageData(mediaType: 'image/png', data: 'abc123');
      final json = img.toJson();
      final restored = ImageData.fromJson(json);
      expect(restored.mediaType, 'image/png');
      expect(restored.data, 'abc123');
    });

    test('PermissionSuggestionData round-trip with all fields', () {
      final suggestion = PermissionSuggestionData(
        type: 'addRules',
        toolName: 'Bash',
        directory: '/home/user',
        mode: 'acceptEdits',
        description: 'Allow Bash',
      );
      final json = suggestion.toJson();
      final restored = PermissionSuggestionData.fromJson(json);
      expect(restored.type, 'addRules');
      expect(restored.toolName, 'Bash');
      expect(restored.directory, '/home/user');
      expect(restored.mode, 'acceptEdits');
      expect(restored.description, 'Allow Bash');
    });

    test('PermissionSuggestionData round-trip with minimal fields', () {
      final suggestion = PermissionSuggestionData(
        type: 'setMode',
        description: 'Set mode',
      );
      final json = suggestion.toJson();
      expect(json.containsKey('toolName'), isFalse);
      expect(json.containsKey('directory'), isFalse);
      expect(json.containsKey('mode'), isFalse);
      final restored = PermissionSuggestionData.fromJson(json);
      expect(restored.toolName, isNull);
      expect(restored.directory, isNull);
      expect(restored.mode, isNull);
    });
  });
}
