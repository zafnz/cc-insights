import 'package:flutter/foundation.dart';

import '../models/ticket.dart';

/// A group of one or more [ActivityEvent]s from the same actor, coalesced
/// for display purposes. Events within a 5-second window from the same actor
/// and actorType are combined into a single display entry.
@immutable
class CoalescedEvent {
  /// The underlying events in this group (always at least one).
  final List<ActivityEvent> events;

  /// Creates a [CoalescedEvent] wrapping the given [events].
  ///
  /// The list must not be empty.
  CoalescedEvent(this.events) : assert(events.isNotEmpty);

  /// The actor who performed all events in this group.
  String get actor => events.first.actor;

  /// The actor type for all events in this group.
  AuthorType get actorType => events.first.actorType;

  /// The timestamp of the first event in the group (used for display).
  DateTime get timestamp => events.first.timestamp;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CoalescedEvent && listEquals(other.events, events);
  }

  @override
  int get hashCode => Object.hashAll(events);

  @override
  String toString() =>
      'CoalescedEvent(actor: $actor, actorType: $actorType, '
      'events: ${events.length})';
}

/// The maximum time gap between consecutive events that can be coalesced.
const _coalescingWindow = Duration(seconds: 5);

/// Coalesces consecutive [ActivityEvent]s from the same actor within a
/// 5-second window into [CoalescedEvent] groups.
///
/// Rules:
/// - Same [ActivityEvent.actor] AND same [ActivityEvent.actorType] AND
///   timestamps within 5 seconds of the group's first event.
/// - Only adjacent events are coalesced (events from other actors break
///   the group).
/// - The underlying event list is not modified — this is display-only.
/// - The timestamp of the first event in each group is used for display.
List<CoalescedEvent> coalesceEvents(List<ActivityEvent> events) {
  if (events.isEmpty) return const [];

  final result = <CoalescedEvent>[];
  var group = <ActivityEvent>[events.first];

  for (var i = 1; i < events.length; i++) {
    final current = events[i];
    final groupFirst = group.first;

    final sameActor = current.actor == groupFirst.actor &&
        current.actorType == groupFirst.actorType;
    final withinWindow = current.timestamp.difference(groupFirst.timestamp).abs() <= _coalescingWindow;

    if (sameActor && withinWindow) {
      group.add(current);
    } else {
      result.add(CoalescedEvent(List.unmodifiable(group)));
      group = <ActivityEvent>[current];
    }
  }

  result.add(CoalescedEvent(List.unmodifiable(group)));
  return result;
}
