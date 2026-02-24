import 'package:flutter_test/flutter_test.dart';
import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/widgets/ticket_timeline_utils.dart';

ActivityEvent _event({
  String id = '1',
  ActivityEventType type = ActivityEventType.tagAdded,
  String actor = 'zaf',
  AuthorType actorType = AuthorType.user,
  required DateTime timestamp,
  Map<String, dynamic> data = const {},
}) {
  return ActivityEvent(
    id: id,
    type: type,
    actor: actor,
    actorType: actorType,
    timestamp: timestamp,
    data: data,
  );
}

void main() {
  final base = DateTime(2026, 2, 25, 12, 0, 0);

  group('coalesceEvents', () {
    test('returns empty list for empty input', () {
      expect(coalesceEvents([]), isEmpty);
    });

    test('single event passes through as a single CoalescedEvent', () {
      final event = _event(timestamp: base);
      final result = coalesceEvents([event]);

      expect(result, hasLength(1));
      expect(result.first.events, [event]);
      expect(result.first.actor, 'zaf');
      expect(result.first.actorType, AuthorType.user);
      expect(result.first.timestamp, base);
    });

    test('same actor within 5 seconds coalesces', () {
      final e1 = _event(id: '1', timestamp: base);
      final e2 = _event(
        id: '2',
        type: ActivityEventType.tagRemoved,
        timestamp: base.add(const Duration(seconds: 3)),
      );
      final result = coalesceEvents([e1, e2]);

      expect(result, hasLength(1));
      expect(result.first.events, [e1, e2]);
      expect(result.first.timestamp, base);
    });

    test('same actor at exactly 5 seconds coalesces', () {
      final e1 = _event(id: '1', timestamp: base);
      final e2 = _event(
        id: '2',
        timestamp: base.add(const Duration(seconds: 5)),
      );
      final result = coalesceEvents([e1, e2]);

      expect(result, hasLength(1));
      expect(result.first.events, hasLength(2));
    });

    test('same actor at 6 seconds does NOT coalesce', () {
      final e1 = _event(id: '1', timestamp: base);
      final e2 = _event(
        id: '2',
        timestamp: base.add(const Duration(seconds: 6)),
      );
      final result = coalesceEvents([e1, e2]);

      expect(result, hasLength(2));
      expect(result[0].events, [e1]);
      expect(result[1].events, [e2]);
    });

    test('different actors do NOT coalesce even within 5 seconds', () {
      final e1 = _event(id: '1', actor: 'zaf', timestamp: base);
      final e2 = _event(
        id: '2',
        actor: 'agent auth-refactor',
        actorType: AuthorType.agent,
        timestamp: base.add(const Duration(seconds: 1)),
      );
      final result = coalesceEvents([e1, e2]);

      expect(result, hasLength(2));
      expect(result[0].actor, 'zaf');
      expect(result[1].actor, 'agent auth-refactor');
    });

    test('same actor but different actorType does NOT coalesce', () {
      final e1 = _event(
        id: '1',
        actor: 'zaf',
        actorType: AuthorType.user,
        timestamp: base,
      );
      final e2 = _event(
        id: '2',
        actor: 'zaf',
        actorType: AuthorType.agent,
        timestamp: base.add(const Duration(seconds: 1)),
      );
      final result = coalesceEvents([e1, e2]);

      expect(result, hasLength(2));
    });

    test('coalescing does not skip over other actors events', () {
      // A, A, B, A — the last A should NOT coalesce with the first two
      final e1 = _event(id: '1', actor: 'zaf', timestamp: base);
      final e2 = _event(
        id: '2',
        actor: 'zaf',
        timestamp: base.add(const Duration(seconds: 2)),
      );
      final e3 = _event(
        id: '3',
        actor: 'bot',
        actorType: AuthorType.agent,
        timestamp: base.add(const Duration(seconds: 3)),
      );
      final e4 = _event(
        id: '4',
        actor: 'zaf',
        timestamp: base.add(const Duration(seconds: 4)),
      );
      final result = coalesceEvents([e1, e2, e3, e4]);

      expect(result, hasLength(3));
      expect(result[0].events, [e1, e2]);
      expect(result[1].events, [e3]);
      expect(result[2].events, [e4]);
    });

    test('window is measured from first event in group, not previous', () {
      // Three events at 0s, 4s, 8s — all same actor.
      // 4s is within 5s of 0s → coalesces.
      // 8s is NOT within 5s of 0s (the group start) → new group.
      final e1 = _event(id: '1', timestamp: base);
      final e2 = _event(
        id: '2',
        timestamp: base.add(const Duration(seconds: 4)),
      );
      final e3 = _event(
        id: '3',
        timestamp: base.add(const Duration(seconds: 8)),
      );
      final result = coalesceEvents([e1, e2, e3]);

      expect(result, hasLength(2));
      expect(result[0].events, [e1, e2]);
      expect(result[1].events, [e3]);
    });

    test('multiple groups coalesce correctly', () {
      final e1 = _event(id: '1', actor: 'zaf', timestamp: base);
      final e2 = _event(
        id: '2',
        actor: 'zaf',
        timestamp: base.add(const Duration(seconds: 2)),
      );
      final e3 = _event(
        id: '3',
        actor: 'bot',
        actorType: AuthorType.agent,
        timestamp: base.add(const Duration(seconds: 10)),
      );
      final e4 = _event(
        id: '4',
        actor: 'bot',
        actorType: AuthorType.agent,
        timestamp: base.add(const Duration(seconds: 12)),
      );
      final result = coalesceEvents([e1, e2, e3, e4]);

      expect(result, hasLength(2));
      expect(result[0].events, [e1, e2]);
      expect(result[0].actor, 'zaf');
      expect(result[1].events, [e3, e4]);
      expect(result[1].actor, 'bot');
    });
  });

  group('CoalescedEvent', () {
    test('exposes actor, actorType, and timestamp from first event', () {
      final e1 = _event(
        id: '1',
        actor: 'zaf',
        actorType: AuthorType.user,
        timestamp: base,
      );
      final e2 = _event(
        id: '2',
        actor: 'zaf',
        actorType: AuthorType.user,
        timestamp: base.add(const Duration(seconds: 3)),
      );
      final coalesced = CoalescedEvent([e1, e2]);

      expect(coalesced.actor, 'zaf');
      expect(coalesced.actorType, AuthorType.user);
      expect(coalesced.timestamp, base);
    });

    test('equality works correctly', () {
      final e1 = _event(id: '1', timestamp: base);
      final a = CoalescedEvent([e1]);
      final b = CoalescedEvent([e1]);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString includes summary', () {
      final e1 = _event(id: '1', timestamp: base);
      final coalesced = CoalescedEvent([e1]);

      expect(coalesced.toString(), contains('actor: zaf'));
      expect(coalesced.toString(), contains('events: 1'));
    });
  });
}
