// =============================================================================
// Surface Zenith OS — ZIB WebSocket Hook
// File: dashboard/src/hooks/useZenithBus.ts
//
// React hook that connects to the Zenith Interdomain Bus via WebSocket
// and dispatches incoming messages to the Zustand store.
// =============================================================================

import { useEffect, useRef, useCallback } from 'react';
import { v4 as uuidv4 } from 'uuid';
import {
  useZenithStore,
  DomainName,
  DomainMetrics,
  Intent,
  Task,
  MigrationEvent,
  SecurityEvent,
  Session,
  BusMessage,
} from '../store/zenithStore';

// =============================================================================
// Message types from ZIB
// =============================================================================

interface ZibMessage {
  topic:      string;
  source:     DomainName;
  target:     DomainName | null;
  payload:    Record<string, unknown>;
  timestamp:  number;
  priority:   'Low' | 'Normal' | 'High' | 'Critical';
  messageId:  string;
}

// =============================================================================
// Hook
// =============================================================================

export function useZenithBus(url: string = 'ws://localhost:7890/zib') {
  const wsRef           = useRef<WebSocket | null>(null);
  const reconnectTimer  = useRef<ReturnType<typeof setTimeout> | null>(null);
  const reconnectDelay  = useRef(1000);
  const isMounted       = useRef(true);

  const {
    setConnected,
    updateDomain,
    addIntent,
    updateIntent,
    addTask,
    updateTask,
    addMigration,
    addSecurityEvent,
    addSession,
    updateSession,
    setCurrentSession,
    updateSchedulerStats,
    addBusMessage,
    addNotification,
    setLastHeartbeat,
  } = useZenithStore();

  // ── Message dispatcher ────────────────────────────────────────────────────

  const dispatch = useCallback((msg: ZibMessage) => {
    const { topic, payload, source, target, timestamp, priority, messageId } = msg;

    // Record bus message for the message log
    const busMsg: BusMessage = {
      id:          messageId,
      topic,
      source,
      target,
      payloadSize: JSON.stringify(payload).length,
      timestamp,
      priority,
    };
    addBusMessage(busMsg);

    // Dispatch by topic
    switch (topic) {
      // ── Domain health ───────────────────────────────────────────────────
      case 'domain.health': {
        const metrics: DomainMetrics = {
          domain:          (payload.domain as DomainName) || source,
          health:          (payload.health as DomainMetrics['health']) || 'Unknown',
          cpuUsagePct:     (payload.cpu_usage_pct as number)    || 0,
          memoryUsagePct:  (payload.memory_usage_pct as number) || 0,
          activeTaskCount: (payload.active_task_count as number)|| 0,
          completedTasks:  (payload.completed_tasks as number)  || 0,
          failedTasks:     (payload.failed_tasks as number)     || 0,
          uptimeMs:        (payload.uptime_ms as number)        || 0,
          lastUpdated:     timestamp,
        };
        updateDomain(metrics);
        break;
      }

      // ── Intent lifecycle ────────────────────────────────────────────────
      case 'intent.submit': {
        const intent: Intent = {
          id:              (payload.intent_id as string)       || uuidv4(),
          sessionId:       (payload.session_id as string)      || '',
          goal:            (payload.goal as string)            || '',
          class:           (payload.class as Intent['class'])  || 'Unknown',
          priority:        (payload.priority as number)        || 128,
          state:           'Pending',
          score:           0,
          preferredDomain: (payload.preferred_domain as DomainName) || null,
          energyCost:      (payload.energy_cost as number)     || 50,
          latencyBudgetMs: (payload.latency_budget_ms as number) || 100,
          submittedAt:     timestamp,
          completedAt:     null,
          durationMs:      null,
          errorMessage:    null,
          tags:            (payload.tags as string[])          || [],
        };
        addIntent(intent);
        break;
      }

      case 'intent.planned':
        updateIntent(payload.intent_id as string, { state: 'Planning' });
        break;

      case 'intent.assigned':
        updateIntent(payload.intent_id as string, {
          state:           'Queued',
          preferredDomain: payload.domain as DomainName,
        });
        break;

      case 'intent.complete': {
        const completedAt = timestamp;
        const submittedAt = useZenithStore.getState().intents
          .find((i) => i.id === payload.intent_id)?.submittedAt || timestamp;
        updateIntent(payload.intent_id as string, {
          state:       'Completed',
          completedAt,
          durationMs:  completedAt - submittedAt,
        });
        updateSchedulerStats({
          totalCompleted: useZenithStore.getState().schedulerStats.totalCompleted + 1,
        });
        addNotification({
          type:    'success',
          title:   'Intent Completed',
          message: `Goal completed in ${completedAt - submittedAt}ms`,
          domain:  source,
        });
        break;
      }

      case 'intent.failed':
        updateIntent(payload.intent_id as string, {
          state:        'Failed',
          completedAt:  timestamp,
          errorMessage: payload.error_message as string,
        });
        updateSchedulerStats({
          totalFailed: useZenithStore.getState().schedulerStats.totalFailed + 1,
        });
        addNotification({
          type:    'error',
          title:   'Intent Failed',
          message: payload.error_message as string || 'Unknown error',
          domain:  source,
        });
        break;

      case 'intent.cancelled':
        updateIntent(payload.intent_id as string, { state: 'Cancelled' });
        break;

      // ── Task lifecycle ──────────────────────────────────────────────────
      case 'task.started': {
        const task: Task = {
          id:             (payload.task_id as string)       || uuidv4(),
          intentId:       (payload.intent_id as string)     || '',
          description:    (payload.description as string)   || '',
          domain:         (payload.domain as DomainName)    || source,
          hardware:       (payload.hardware as string)       || 'CPU',
          priority:       (payload.priority as number)       || 128,
          state:          'Running',
          submittedAt:    (payload.submitted_at as number)  || timestamp,
          startedAt:      timestamp,
          completedAt:    null,
          migrationCount: 0,
        };
        addTask(task);
        break;
      }

      case 'task.completed':
        updateTask(payload.task_id as string, {
          state:       'Completed',
          completedAt: timestamp,
        });
        break;

      case 'task.failed':
        updateTask(payload.task_id as string, { state: 'Failed', completedAt: timestamp });
        break;

      case 'task.migrating':
        updateTask(payload.task_id as string, { state: 'Migrating' });
        break;

      case 'task.migrated': {
        const migration: MigrationEvent = {
          id:               uuidv4(),
          taskId:           (payload.task_id as string)          || '',
          fromDomain:       (payload.from_domain as DomainName)  || 'android',
          toDomain:         (payload.to_domain as DomainName)    || 'windows',
          mode:             (payload.migration_mode as MigrationEvent['mode']) || 'FullSnapshot',
          trigger:          (payload.migration_reason as string) || 'Unknown',
          success:          true,
          downtimeMs:       (payload.downtime_ms as number)      || 0,
          bytesTransferred: (payload.bytes_transferred as number)|| 0,
          timestamp,
        };
        addMigration(migration);
        updateTask(payload.task_id as string, {
          state:          'Running',
          domain:         payload.to_domain as DomainName,
          migrationCount: ((useZenithStore.getState().tasks
            .find((t) => t.id === payload.task_id)?.migrationCount) || 0) + 1,
        });
        addNotification({
          type:    'info',
          title:   'Task Migrated',
          message: `Task moved from ${migration.fromDomain} → ${migration.toDomain}`,
          domain:  migration.toDomain,
        });
        break;
      }

      // ── Session lifecycle ───────────────────────────────────────────────
      case 'session.opened': {
        const session: Session = {
          id:           (payload.session_id as string)      || uuidv4(),
          identityName: (payload.identity_name as string)   || 'Unknown',
          formFactor:   (payload.form_factor as string)     || 'Desktop',
          activeDomain: (payload.active_domain as DomainName) || 'windows',
          state:        'Active',
          createdAt:    timestamp,
          lastActive:   timestamp,
          intentCount:  0,
          objectCount:  0,
        };
        addSession(session);
        setCurrentSession(session);
        break;
      }

      case 'session.suspended':
        updateSession(payload.session_id as string, { state: 'Suspended' });
        break;

      case 'session.resumed':
        updateSession(payload.session_id as string, { state: 'Active', lastActive: timestamp });
        break;

      case 'session.terminated':
        updateSession(payload.session_id as string, { state: 'Terminated' });
        setCurrentSession(null);
        break;

      // ── Security ────────────────────────────────────────────────────────
      case 'security.violation': {
        const secEvent: SecurityEvent = {
          id:              uuidv4(),
          sessionId:       (payload.session_id as string)          || '',
          violatingDomain: (payload.violating_domain as DomainName)|| source,
          violationType:   (payload.violation_type as string)      || 'Unknown',
          severity:        (payload.severity as SecurityEvent['severity']) || 'Medium',
          detail:          (payload.detail as string)              || '',
          timestamp,
        };
        addSecurityEvent(secEvent);
        addNotification({
          type:    'error',
          title:   `Security Violation [${secEvent.severity}]`,
          message: secEvent.detail,
          domain:  secEvent.violatingDomain,
        });
        break;
      }

      // ── Scheduler metrics ───────────────────────────────────────────────
      case 'system.metrics.snapshot': {
        const metrics = payload.metrics as Record<string, number> || {};
        updateSchedulerStats({
          queueDepth:           metrics.queue_depth           || 0,
          totalSubmitted:       metrics.total_submitted       || 0,
          totalScheduled:       metrics.total_scheduled       || 0,
          totalCompleted:       metrics.total_completed       || 0,
          totalFailed:          metrics.total_failed          || 0,
          totalCancelled:       metrics.total_cancelled       || 0,
          totalDropped:         metrics.total_dropped         || 0,
          totalTasksDispatched: metrics.total_tasks_dispatched|| 0,
          totalMigrations:      metrics.total_migrations      || 0,
          completionRate:       metrics.completion_rate       || 0,
          failureRate:          metrics.failure_rate          || 0,
          dropRate:             metrics.drop_rate             || 0,
        });
        break;
      }

      // ── Heartbeat ───────────────────────────────────────────────────────
      case 'system.heartbeat':
        setLastHeartbeat(timestamp);
        break;

      // ── Form factor change ──────────────────────────────────────────────
      case 'domain.formfactor.changed':
        addNotification({
          type:    'info',
          title:   'Form Factor Changed',
          message: `Device switched to ${payload.form_factor}`,
          domain:  null,
        });
        break;

      default:
        // Unknown topic — logged to bus message log only
        break;
    }
  }, [
    updateDomain, addIntent, updateIntent, addTask, updateTask,
    addMigration, addSecurityEvent, addSession, updateSession,
    setCurrentSession, updateSchedulerStats, addBusMessage,
    addNotification, setLastHeartbeat,
  ]);

  // ── WebSocket connection ──────────────────────────────────────────────────

  const connect = useCallback(() => {
    if (!isMounted.current) return;

    try {
      const ws = new WebSocket(url);
      wsRef.current = ws;

      ws.onopen = () => {
        if (!isMounted.current) return;
        setConnected(true);
        reconnectDelay.current = 1000;
        console.log('[ZIB] Connected to', url);

        // Subscribe to all topics
        ws.send(JSON.stringify({
          type:   'subscribe',
          topics: ['*'], // wildcard subscription
        }));
      };

      ws.onmessage = (event) => {
        if (!isMounted.current) return;
        try {
          const msg: ZibMessage = JSON.parse(event.data);
          dispatch(msg);
        } catch (err) {
          console.error('[ZIB] Failed to parse message:', err);
        }
      };

      ws.onclose = () => {
        if (!isMounted.current) return;
        setConnected(false);
        console.warn('[ZIB] Disconnected. Reconnecting in', reconnectDelay.current, 'ms');

        // Exponential backoff reconnect
        reconnectTimer.current = setTimeout(() => {
          reconnectDelay.current = Math.min(reconnectDelay.current * 2, 30000);
          connect();
        }, reconnectDelay.current);
      };

      ws.onerror = (err) => {
        console.error('[ZIB] WebSocket error:', err);
        ws.close();
      };
    } catch (err) {
      console.error('[ZIB] Failed to create WebSocket:', err);
      // Retry after delay
      reconnectTimer.current = setTimeout(connect, reconnectDelay.current);
    }
  }, [url, dispatch, setConnected]);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  useEffect(() => {
    isMounted.current = true;
    connect();

    return () => {
      isMounted.current = false;
      if (reconnectTimer.current) {
        clearTimeout(reconnectTimer.current);
      }
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
    };
  }, [connect]);

  // ── Public API ────────────────────────────────────────────────────────────

  const publish = useCallback((topic: string, payload: Record<string, unknown>) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ type: 'publish', topic, payload }));
    } else {
      console.warn('[ZIB] Cannot publish: not connected');
    }
  }, []);

  const submitIntent = useCallback((goal: string, priority: number = 128) => {
    publish('intent.submit', {
      intent_id: uuidv4(),
      goal,
      priority,
      timestamp: Date.now(),
    });
  }, [publish]);

  return { publish, submitIntent };
}