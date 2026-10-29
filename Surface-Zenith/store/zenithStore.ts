// =============================================================================
// Surface Zenith OS — Global State Store (Zustand)
// File: dashboard/src/store/zenithStore.ts
// =============================================================================

import { create } from 'zustand';
import { subscribeWithSelector } from 'zustand/middleware';
import { v4 as uuidv4 } from 'uuid';

// =============================================================================
// Types
// =============================================================================

export type DomainName = 'android' | 'windows' | 'ai' | 'quantum' | 'realtime' | 'cloud';

export type DomainHealth = 'Healthy' | 'Degraded' | 'Failed' | 'Initializing' | 'Suspended' | 'Unknown';

export type IntentClass =
  | 'Messaging' | 'Telephony' | 'Productivity' | 'Development'
  | 'Graphics'  | 'Inference' | 'Media'        | 'SensorFusion'
  | 'Quantum'   | 'CloudSync' | 'System'       | 'Unknown';

export type IntentState =
  | 'Pending' | 'Classifying' | 'Planning' | 'Queued'
  | 'Running' | 'Suspended'   | 'Migrating'| 'Completed'
  | 'Failed'  | 'Cancelled';

export type MigrationMode = 'FullSnapshot' | 'Incremental' | 'Live';

// =============================================================================
// Domain metrics
// =============================================================================

export interface DomainMetrics {
  domain:           DomainName;
  health:           DomainHealth;
  cpuUsagePct:      number;
  memoryUsagePct:   number;
  activeTaskCount:  number;
  completedTasks:   number;
  failedTasks:      number;
  uptimeMs:         number;
  lastUpdated:      number;
}

// =============================================================================
// Intent
// =============================================================================

export interface Intent {
  id:               string;
  sessionId:        string;
  goal:             string;
  class:            IntentClass;
  priority:         number;
  state:            IntentState;
  score:            number;
  preferredDomain:  DomainName | null;
  energyCost:       number;
  latencyBudgetMs:  number;
  submittedAt:      number;
  completedAt:      number | null;
  durationMs:       number | null;
  errorMessage:     string | null;
  tags:             string[];
}

// =============================================================================
// Task
// =============================================================================

export interface Task {
  id:           string;
  intentId:     string;
  description:  string;
  domain:       DomainName;
  hardware:     string;
  priority:     number;
  state:        'Queued' | 'Running' | 'Completed' | 'Failed' | 'Migrating';
  submittedAt:  number;
  startedAt:    number | null;
  completedAt:  number | null;
  migrationCount: number;
}

// =============================================================================
// Migration event
// =============================================================================

export interface MigrationEvent {
  id:             string;
  taskId:         string;
  fromDomain:     DomainName;
  toDomain:       DomainName;
  mode:           MigrationMode;
  trigger:        string;
  success:        boolean;
  downtimeMs:     number;
  bytesTransferred: number;
  timestamp:      number;
}

// =============================================================================
// Security event
// =============================================================================

export interface SecurityEvent {
  id:             string;
  sessionId:      string;
  violatingDomain: DomainName;
  violationType:  string;
  severity:       'Low' | 'Medium' | 'High' | 'Critical';
  detail:         string;
  timestamp:      number;
}

// =============================================================================
// Session
// =============================================================================

export interface Session {
  id:           string;
  identityName: string;
  formFactor:   string;
  activeDomain: DomainName;
  state:        'Active' | 'Idle' | 'Suspended' | 'Migrating' | 'Terminated';
  createdAt:    number;
  lastActive:   number;
  intentCount:  number;
  objectCount:  number;
}

// =============================================================================
// Scheduler stats
// =============================================================================

export interface SchedulerStats {
  queueDepth:         number;
  totalSubmitted:     number;
  totalScheduled:     number;
  totalCompleted:     number;
  totalFailed:        number;
  totalCancelled:     number;
  totalDropped:       number;
  totalTasksDispatched: number;
  totalMigrations:    number;
  completionRate:     number;
  failureRate:        number;
  dropRate:           number;
}

// =============================================================================
// Bus message
// =============================================================================

export interface BusMessage {
  id:         string;
  topic:      string;
  source:     DomainName;
  target:     DomainName | null;
  payloadSize: number;
  timestamp:  number;
  priority:   'Low' | 'Normal' | 'High' | 'Critical';
}

// =============================================================================
// Notification
// =============================================================================

export interface Notification {
  id:        string;
  type:      'info' | 'success' | 'warning' | 'error';
  title:     string;
  message:   string;
  timestamp: number;
  read:      boolean;
  domain:    DomainName | null;
}

// =============================================================================
// Store state
// =============================================================================

export interface ZenithState {
  // Connection
  isConnected:      boolean;
  connectionUrl:    string;
  lastHeartbeat:    number | null;

  // Domains
  domains:          Record<DomainName, DomainMetrics>;

  // Intents
  intents:          Intent[];
  activeIntents:    Intent[];

  // Tasks
  tasks:            Task[];
  activeTasks:      Task[];

  // Migrations
  migrations:       MigrationEvent[];

  // Security
  securityEvents:   SecurityEvent[];

  // Sessions
  sessions:         Session[];
  currentSession:   Session | null;

  // Scheduler
  schedulerStats:   SchedulerStats;

  // Bus messages
  busMessages:      BusMessage[];
  busMessageRate:   number; // messages per second

  // Notifications
  notifications:    Notification[];
  unreadCount:      number;

  // UI state
  selectedDomain:   DomainName | null;
  selectedIntent:   string | null;
  darkMode:         boolean;
  sidebarCollapsed: boolean;

  // Actions
  setConnected:     (connected: boolean) => void;
  updateDomain:     (metrics: DomainMetrics) => void;
  addIntent:        (intent: Intent) => void;
  updateIntent:     (id: string, updates: Partial<Intent>) => void;
  addTask:          (task: Task) => void;
  updateTask:       (id: string, updates: Partial<Task>) => void;
  addMigration:     (event: MigrationEvent) => void;
  addSecurityEvent: (event: SecurityEvent) => void;
  addSession:       (session: Session) => void;
  updateSession:    (id: string, updates: Partial<Session>) => void;
  setCurrentSession:(session: Session | null) => void;
  updateSchedulerStats: (stats: Partial<SchedulerStats>) => void;
  addBusMessage:    (msg: BusMessage) => void;
  addNotification:  (n: Omit<Notification, 'id' | 'timestamp' | 'read'>) => void;
  markNotificationRead: (id: string) => void;
  clearNotifications: () => void;
  setSelectedDomain:(domain: DomainName | null) => void;
  setSelectedIntent:(id: string | null) => void;
  toggleDarkMode:   () => void;
  toggleSidebar:    () => void;
  setLastHeartbeat: (ts: number) => void;
}

// =============================================================================
// Default domain metrics
// =============================================================================

const defaultDomainMetrics = (domain: DomainName): DomainMetrics => ({
  domain,
  health:          'Unknown',
  cpuUsagePct:     0,
  memoryUsagePct:  0,
  activeTaskCount: 0,
  completedTasks:  0,
  failedTasks:     0,
  uptimeMs:        0,
  lastUpdated:     Date.now(),
});

const defaultSchedulerStats: SchedulerStats = {
  queueDepth:           0,
  totalSubmitted:       0,
  totalScheduled:       0,
  totalCompleted:       0,
  totalFailed:          0,
  totalCancelled:       0,
  totalDropped:         0,
  totalTasksDispatched: 0,
  totalMigrations:      0,
  completionRate:       0,
  failureRate:          0,
  dropRate:             0,
};

// =============================================================================
// Store
// =============================================================================

export const useZenithStore = create<ZenithState>()(
  subscribeWithSelector((set, get) => ({
    // Connection
    isConnected:   false,
    connectionUrl: 'ws://localhost:7890/zib',
    lastHeartbeat: null,

    // Domains
    domains: {
      android:  defaultDomainMetrics('android'),
      windows:  defaultDomainMetrics('windows'),
      ai:       defaultDomainMetrics('ai'),
      quantum:  defaultDomainMetrics('quantum'),
      realtime: defaultDomainMetrics('realtime'),
      cloud:    defaultDomainMetrics('cloud'),
    },

    // Intents
    intents:       [],
    activeIntents: [],

    // Tasks
    tasks:       [],
    activeTasks: [],

    // Migrations
    migrations: [],

    // Security
    securityEvents: [],

    // Sessions
    sessions:       [],
    currentSession: null,

    // Scheduler
    schedulerStats: defaultSchedulerStats,

    // Bus
    busMessages:    [],
    busMessageRate: 0,

    // Notifications
    notifications: [],
    unreadCount:   0,

    // UI
    selectedDomain:   null,
    selectedIntent:   null,
    darkMode:         true,
    sidebarCollapsed: false,

    // ── Actions ──────────────────────────────────────────────────────────────

    setConnected: (connected) => set({ isConnected: connected }),

    updateDomain: (metrics) =>
      set((state) => ({
        domains: {
          ...state.domains,
          [metrics.domain]: { ...metrics, lastUpdated: Date.now() },
        },
      })),

    addIntent: (intent) =>
      set((state) => {
        const intents = [intent, ...state.intents].slice(0, 1000);
        const activeIntents = intents.filter(
          (i) => !['Completed', 'Failed', 'Cancelled'].includes(i.state)
        );
        return { intents, activeIntents };
      }),

    updateIntent: (id, updates) =>
      set((state) => {
        const intents = state.intents.map((i) =>
          i.id === id ? { ...i, ...updates } : i
        );
        const activeIntents = intents.filter(
          (i) => !['Completed', 'Failed', 'Cancelled'].includes(i.state)
        );
        return { intents, activeIntents };
      }),

    addTask: (task) =>
      set((state) => {
        const tasks = [task, ...state.tasks].slice(0, 2000);
        const activeTasks = tasks.filter(
          (t) => !['Completed', 'Failed'].includes(t.state)
        );
        return { tasks, activeTasks };
      }),

    updateTask: (id, updates) =>
      set((state) => {
        const tasks = state.tasks.map((t) =>
          t.id === id ? { ...t, ...updates } : t
        );
        const activeTasks = tasks.filter(
          (t) => !['Completed', 'Failed'].includes(t.state)
        );
        return { tasks, activeTasks };
      }),

    addMigration: (event) =>
      set((state) => ({
        migrations: [event, ...state.migrations].slice(0, 500),
      })),

    addSecurityEvent: (event) =>
      set((state) => ({
        securityEvents: [event, ...state.securityEvents].slice(0, 200),
      })),

    addSession: (session) =>
      set((state) => ({
        sessions: [session, ...state.sessions].slice(0, 100),
      })),

    updateSession: (id, updates) =>
      set((state) => {
        const sessions = state.sessions.map((s) =>
          s.id === id ? { ...s, ...updates } : s
        );
        const currentSession = state.currentSession?.id === id
          ? { ...state.currentSession, ...updates }
          : state.currentSession;
        return { sessions, currentSession };
      }),

    setCurrentSession: (session) => set({ currentSession: session }),

    updateSchedulerStats: (stats) =>
      set((state) => ({
        schedulerStats: { ...state.schedulerStats, ...stats },
      })),

    addBusMessage: (msg) =>
      set((state) => {
        const busMessages = [msg, ...state.busMessages].slice(0, 500);
        // Calculate message rate (messages in last second)
        const oneSecondAgo = Date.now() - 1000;
        const rate = busMessages.filter((m) => m.timestamp > oneSecondAgo).length;
        return { busMessages, busMessageRate: rate };
      }),

    addNotification: (n) =>
      set((state) => {
        const notification: Notification = {
          ...n,
          id:        uuidv4(),
          timestamp: Date.now(),
          read:      false,
        };
        const notifications = [notification, ...state.notifications].slice(0, 100);
        const unreadCount   = notifications.filter((n) => !n.read).length;
        return { notifications, unreadCount };
      }),

    markNotificationRead: (id) =>
      set((state) => {
        const notifications = state.notifications.map((n) =>
          n.id === id ? { ...n, read: true } : n
        );
        const unreadCount = notifications.filter((n) => !n.read).length;
        return { notifications, unreadCount };
      }),

    clearNotifications: () => set({ notifications: [], unreadCount: 0 }),

    setSelectedDomain: (domain) => set({ selectedDomain: domain }),
    setSelectedIntent: (id)     => set({ selectedIntent: id }),
    toggleDarkMode:    ()       => set((s) => ({ darkMode: !s.darkMode })),
    toggleSidebar:     ()       => set((s) => ({ sidebarCollapsed: !s.sidebarCollapsed })),
    setLastHeartbeat:  (ts)     => set({ lastHeartbeat: ts }),
  }))
);

// =============================================================================
// Selectors
// =============================================================================

export const selectDomainMetrics = (domain: DomainName) =>
  (state: ZenithState) => state.domains[domain];

export const selectHealthyDomains = (state: ZenithState) =>
  Object.values(state.domains).filter((d) => d.health === 'Healthy');

export const selectTotalActiveTasks = (state: ZenithState) =>
  Object.values(state.domains).reduce((sum, d) => sum + d.activeTaskCount, 0);

export const selectRecentIntents = (count: number) =>
  (state: ZenithState) => state.intents.slice(0, count);

export const selectRecentMigrations = (count: number) =>
  (state: ZenithState) => state.migrations.slice(0, count);

export const selectCriticalSecurityEvents = (state: ZenithState) =>
  state.securityEvents.filter((e) => e.severity === 'Critical');