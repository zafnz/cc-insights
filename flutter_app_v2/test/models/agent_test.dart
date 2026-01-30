import 'package:cc_insights_v2/models/agent.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentStatus', () {
    test('has all expected values', () {
      // Assert
      check(AgentStatus.values).length.equals(5);
      check(AgentStatus.values).contains(AgentStatus.working);
      check(AgentStatus.values).contains(AgentStatus.waitingTool);
      check(AgentStatus.values).contains(AgentStatus.waitingUser);
      check(AgentStatus.values).contains(AgentStatus.completed);
      check(AgentStatus.values).contains(AgentStatus.error);
    });
  });

  group('Agent', () {
    group('working() factory', () {
      test('creates agent with working status', () {
        // Arrange & Act
        const agent = Agent.working(
          sdkAgentId: 'agent-123',
          conversationId: 'conv-456',
        );

        // Assert
        check(agent.sdkAgentId).equals('agent-123');
        check(agent.conversationId).equals('conv-456');
        check(agent.status).equals(AgentStatus.working);
        check(agent.result).isNull();
      });

      test('result is null for working agent', () {
        // Arrange & Act
        const agent = Agent.working(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
        );

        // Assert
        check(agent.result).isNull();
      });
    });

    group('isTerminal', () {
      test('returns true for completed status', () {
        // Arrange
        const agent = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.completed,
          result: 'Task completed successfully',
        );

        // Act & Assert
        check(agent.isTerminal).isTrue();
      });

      test('returns true for error status', () {
        // Arrange
        const agent = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.error,
          result: 'An error occurred',
        );

        // Act & Assert
        check(agent.isTerminal).isTrue();
      });

      test('returns false for working status', () {
        // Arrange
        const agent = Agent.working(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
        );

        // Act & Assert
        check(agent.isTerminal).isFalse();
      });

      test('returns false for waitingTool status', () {
        // Arrange
        const agent = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.waitingTool,
        );

        // Act & Assert
        check(agent.isTerminal).isFalse();
      });

      test('returns false for waitingUser status', () {
        // Arrange
        const agent = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.waitingUser,
        );

        // Act & Assert
        check(agent.isTerminal).isFalse();
      });
    });

    group('isWaiting', () {
      test('returns true for waitingTool status', () {
        // Arrange
        const agent = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.waitingTool,
        );

        // Act & Assert
        check(agent.isWaiting).isTrue();
      });

      test('returns true for waitingUser status', () {
        // Arrange
        const agent = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.waitingUser,
        );

        // Act & Assert
        check(agent.isWaiting).isTrue();
      });

      test('returns false for working status', () {
        // Arrange
        const agent = Agent.working(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
        );

        // Act & Assert
        check(agent.isWaiting).isFalse();
      });

      test('returns false for completed status', () {
        // Arrange
        const agent = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.completed,
        );

        // Act & Assert
        check(agent.isWaiting).isFalse();
      });
    });

    group('copyWith()', () {
      test('updates status', () {
        // Arrange
        const original = Agent.working(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
        );

        // Act
        final modified = original.copyWith(status: AgentStatus.completed);

        // Assert
        check(modified.status).equals(AgentStatus.completed);
        check(modified.sdkAgentId).equals('agent-1');
        check(modified.conversationId).equals('conv-1');
      });

      test('updates result', () {
        // Arrange
        const original = Agent.working(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
        );

        // Act
        final modified = original.copyWith(
          status: AgentStatus.completed,
          result: 'Done!',
        );

        // Assert
        check(modified.status).equals(AgentStatus.completed);
        check(modified.result).equals('Done!');
      });

      test('preserves unchanged fields', () {
        // Arrange
        const original = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.working,
          result: null,
        );

        // Act
        final modified = original.copyWith(status: AgentStatus.waitingTool);

        // Assert
        check(modified.sdkAgentId).equals('agent-1');
        check(modified.conversationId).equals('conv-1');
        check(modified.status).equals(AgentStatus.waitingTool);
        check(modified.result).isNull();
      });

      test('can update sdkAgentId', () {
        // Arrange
        const original = Agent.working(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
        );

        // Act
        final modified = original.copyWith(sdkAgentId: 'agent-2');

        // Assert
        check(modified.sdkAgentId).equals('agent-2');
      });
    });

    group('equality', () {
      test('equals returns true for identical values', () {
        // Arrange
        const agent1 = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.working,
          result: null,
        );
        const agent2 = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.working,
          result: null,
        );

        // Act & Assert
        check(agent1 == agent2).isTrue();
        check(agent1.hashCode).equals(agent2.hashCode);
      });

      test('equals returns false for different status', () {
        // Arrange
        const agent1 = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.working,
        );
        const agent2 = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.completed,
        );

        // Act & Assert
        check(agent1 == agent2).isFalse();
      });

      test('equals returns false for different result', () {
        // Arrange
        const agent1 = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.completed,
          result: 'Result A',
        );
        const agent2 = Agent(
          sdkAgentId: 'agent-1',
          conversationId: 'conv-1',
          status: AgentStatus.completed,
          result: 'Result B',
        );

        // Act & Assert
        check(agent1 == agent2).isFalse();
      });
    });

    group('toString()', () {
      test('includes key information', () {
        // Arrange
        const agent = Agent(
          sdkAgentId: 'agent-123',
          conversationId: 'conv-456',
          status: AgentStatus.completed,
          result: 'Success',
        );

        // Act
        final str = agent.toString();

        // Assert
        check(str).contains('agent-123');
        check(str).contains('conv-456');
        check(str).contains('completed');
        check(str).contains('Success');
      });
    });
  });
}
