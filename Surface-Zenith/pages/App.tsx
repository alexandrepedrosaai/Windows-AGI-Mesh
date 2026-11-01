// =============================================================================
// Surface Zenith OS — Main Dashboard App (React/TypeScript)
// File: dashboard/src/pages/App.tsx
// =============================================================================

import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Activity, Cpu, Shield, Zap, Bell, Settings,
  ChevronLeft, ChevronRight, BarChart2, GitBranch,
  Radio, Terminal, Moon, Sun, Wifi, WifiOff,
} from 'lucide-react';
import { useZenithStore } from '../store/zenithStore';
import { useZenithBus } from '../hooks/useZenithBus';
import { DomainMonitor } from '../components/DomainMonitor';
import { IntentDashboard } from '../components/IntentDashboard';

// =============================================================================
// Navigation items
// =============================================================================

interface NavItem {
  id:    string;
  label: string;
  icon:  React.ReactNode;
  badge?: number;
}

// =============================================================================
// Sidebar
// =============================================================================

const Sidebar: React.FC<{
  activeTab:    string;
  onTabChange:  (tab: string) => void;
  collapsed:    boolean;
  onToggle:     () => void;
  navItems:     NavItem[];
}> = ({ activeTab, onTabChange, collapsed, onToggle, navItems }) => (
  <motion.aside
    animate={{ width: collapsed ? 64 : 220 }}
    transition={{ duration: 0.2, ease: 'easeInOut' }}
    className="flex-shrink-0 bg-gray-900 border-r border-gray-800 flex flex-col overflow-hidden"
  >
    {/* Logo */}
    <div className="flex items-center gap-3 px-4 py-5 border-b border-gray-800">
      <div className="w-8 h-8 rounded-lg bg-blue-600 flex items-center justify-center flex-shrink-0">
        <Zap size={16} className="text-white" />
      </div>
      <AnimatePresence>
        {!collapsed && (
          <motion.div
            initial={{ opacity: 0, x: -10 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -10 }}
            className="overflow-hidden"
          >
            <div className="text-sm font-bold text-white whitespace-nowrap">Surface Zenith</div>
            <div className="text-xs text-gray-500 whitespace-nowrap">OS Dashboard</div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>

    {/* Nav items */}
    <nav className="flex-1 py-4 space-y-1 px-2">
      {navItems.map((item) => (
        <button
          key={item.id}
          onClick={() => onTabChange(item.id)}
          className={`
            w-full flex items-center gap-3 px-3 py-2.5 rounded-lg transition-colors text-left
            ${activeTab === item.id
              ? 'bg-blue-600 text-white'
              : 'text-gray-400 hover:bg-gray-800 hover:text-white'}
          `}
        >
          <div className="flex-shrink-0">{item.icon}</div>
          <AnimatePresence>
            {!collapsed && (
              <motion.span
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="text-sm font-medium whitespace-nowrap flex-1"
              >
                {item.label}
              </motion.span>
            )}
          </AnimatePresence>
          {item.badge !== undefined && item.badge > 0 && (
            <span className="ml-auto bg-red-500 text-white text-xs rounded-full w-5 h-5 flex items-center justify-center flex-shrink-0">
              {item.badge > 9 ? '9+' : item.badge}
            </span>
          )}
        </button>
      ))}
    </nav>

    {/* Collapse toggle */}
    <button
      onClick={onToggle}
      className="flex items-center justify-center p-3 border-t border-gray-800 text-gray-500 hover:text-white transition-colors"
    >
      {collapsed ? <ChevronRight size={16} /> : <ChevronLeft size={16} />}
    </button>
  </motion.aside>
);

// =============================================================================
// Header
// =============================================================================

const Header: React.FC<{
  activeTab:   string;
  isConnected: boolean;
  darkMode:    boolean;
  onToggleDark: () => void;
  unreadCount: number;
}> = ({ activeTab, isConnected, darkMode, onToggleDark, unreadCount }) => {
  const lastHeartbeat = useZenithStore((s) => s.lastHeartbeat);
  const schedulerStats = useZenithStore((s) => s.schedulerStats);

  const tabLabels: Record<string, string> = {
    domains:    'Domain Monitor',
    intents:    'Intent Dashboard',
    migrations: 'Migration Events',
    security:   'Security Center',
    bus:        'Message Bus',
    scheduler:  'Scheduler Stats',
    terminal:   'Terminal',
  };

  return (
    <header className="flex items-center gap-4 px-6 py-3 bg-gray-900 border-b border-gray-800">
      <h1 className="text-base font-semibold text-white">{tabLabels[activeTab] || activeTab}</h1>

      <div className="flex items-center gap-2 ml-auto">
        {/* Queue depth */}
        <div className="flex items-center gap-1.5 px-3 py-1 bg-gray-800 rounded-lg">
          <BarChart2 size={12} className="text-blue-400" />
          <span className="text-xs text-gray-300">Queue: {schedulerStats.queueDepth}</span>
        </div>

        {/* Connection status */}
        <div className={`flex items-center gap-1.5 px-3 py-1 rounded-lg ${isConnected ? 'bg-green-900/30' : 'bg-red-900/30'}`}>
          {isConnected
            ? <Wifi size={12} className="text-green-400" />
            : <WifiOff size={12} className="text-red-400" />}
          <span className={`text-xs ${isConnected ? 'text-green-400' : 'text-red-400'}`}>
            {isConnected ? 'ZIB Connected' : 'Disconnected'}
          </span>
        </div>

        {/* Last heartbeat */}
        {lastHeartbeat && (
          <div className="flex items-center gap-1 text-xs text-gray-500">
            <div className="w-1.5 h-1.5 rounded-full bg-green-400 animate-pulse" />
            <span>{new Date(lastHeartbeat).toLocaleTimeString()}</span>
          </div>
        )}

        {/* Dark mode toggle */}
        <button
          onClick={onToggleDark}
          className="p-2 rounded-lg text-gray-400 hover:text-white hover:bg-gray-800 transition-colors"
        >
          {darkMode ? <Sun size={16} /> : <Moon size={16} />}
        </button>

        {/* Notifications */}
        <button className="relative p-2 rounded-lg text-gray-400 hover:text-white hover:bg-gray-800 transition-colors">
          <Bell size={16} />
          {unreadCount > 0 && (
            <span className="absolute top-1 right-1 w-2 h-2 bg-red-500 rounded-full" />
          )}
        </button>

        {/* Settings */}
        <button className="p-2 rounded-lg text-gray-400 hover:text-white hover:bg-gray-800 transition-colors">
          <Settings size={16} />
        </button>
      </div>
    </header>
  );
};

// =============================================================================
// Migration events tab
// =============================================================================

const MigrationEvents: React.FC = () => {
  const migrations = useZenithStore((s) => s.migrations);

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-3 gap-3">
        {[
          { label: 'Total Migrations', value: migrations.length, color: '#9B59B6' },
          { label: 'Successful',       value: migrations.filter((m) => m.success).length, color: '#00C851' },
          { label: 'Failed',           value: migrations.filter((m) => !m.success).length, color: '#FF4444' },
        ].map(({ label, value, color }) => (
          <div key={label} className="bg-gray-800 rounded-xl border border-gray-700 p-4">
            <div className="text-xs text-gray-400 mb-1">{label}</div>
            <div className="text-2xl font-bold" style={{ color }}>{value}</div>
          </div>
        ))}
      </div>

      <div className="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden">
        <div className="px-4 py-3 border-b border-gray-700">
          <h3 className="text-sm font-semibold text-white">Recent Migrations</h3>
        </div>
        <div className="divide-y divide-gray-700/50 max-h-96 overflow-y-auto">
          {migrations.length === 0 ? (
            <div className="flex items-center justify-center py-12 text-gray-500 text-sm">
              No migrations yet
            </div>
          ) : (
            migrations.slice(0, 50).map((m) => (
              <div key={m.id} className="flex items-center gap-3 p-3">
                <div className={`w-2 h-2 rounded-full flex-shrink-0 ${m.success ? 'bg-green-400' : 'bg-red-400'}`} />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 text-sm">
                    <span className="text-gray-300">{m.fromDomain}</span>
                    <span className="text-gray-500">→</span>
                    <span className="text-white font-medium">{m.toDomain}</span>
                    <span className="text-xs text-gray-500 ml-auto">{m.mode}</span>
                  </div>
                  <div className="flex items-center gap-3 mt-0.5 text-xs text-gray-500">
                    <span>{m.trigger}</span>
                    <span>·</span>
                    <span>{m.downtimeMs}ms downtime</span>
                    <span>·</span>
                    <span>{(m.bytesTransferred / 1024).toFixed(1)} KB</span>
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
};

// =============================================================================
// Security center tab
// =============================================================================

const SecurityCenter: React.FC = () => {
  const events = useZenithStore((s) => s.securityEvents);

  const severityColors = { Low: '#888888', Medium: '#FF9800', High: '#FF6B35', Critical: '#FF4444' };

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-4 gap-3">
        {(['Low', 'Medium', 'High', 'Critical'] as const).map((sev) => {
          const count = events.filter((e) => e.severity === sev).length;
          return (
            <div key={sev} className="bg-gray-800 rounded-xl border border-gray-700 p-4">
              <div className="text-xs text-gray-400 mb-1">{sev}</div>
              <div className="text-2xl font-bold" style={{ color: severityColors[sev] }}>{count}</div>
            </div>
          );
        })}
      </div>

      <div className="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden">
        <div className="px-4 py-3 border-b border-gray-700 flex items-center gap-2">
          <Shield size={14} className="text-red-400" />
          <h3 className="text-sm font-semibold text-white">Security Events</h3>
        </div>
        <div className="divide-y divide-gray-700/50 max-h-96 overflow-y-auto">
          {events.length === 0 ? (
            <div className="flex items-center justify-center py-12 text-gray-500 text-sm">
              No security events
            </div>
          ) : (
            events.slice(0, 50).map((e) => (
              <div key={e.id} className="flex items-start gap-3 p-3">
                <div
                  className="w-2 h-2 rounded-full flex-shrink-0 mt-1.5"
                  style={{ backgroundColor: severityColors[e.severity] }}
                />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-sm text-white font-medium">{e.violationType}</span>
                    <span
                      className="text-xs px-1.5 py-0.5 rounded"
                      style={{ backgroundColor: `${severityColors[e.severity]}22`, color: severityColors[e.severity] }}
                    >
                      {e.severity}
                    </span>
                  </div>
                  <p className="text-xs text-gray-400 mt-0.5 truncate">{e.detail}</p>
                  <div className="flex items-center gap-2 mt-0.5 text-xs text-gray-500">
                    <span>{e.violatingDomain}</span>
                    <span>·</span>
                    <span>{new Date(e.timestamp).toLocaleTimeString()}</span>
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
};

// =============================================================================
// Bus message log tab
// =============================================================================

const BusMessageLog: React.FC = () => {
  const messages     = useZenithStore((s) => s.busMessages);
  const messageRate  = useZenithStore((s) => s.busMessageRate);

  const priorityColors = { Low: '#888888', Normal: '#0078D4', High: '#FF9800', Critical: '#FF4444' };

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3 p-3 bg-gray-800 rounded-xl border border-gray-700">
        <Radio size={14} className="text-blue-400 animate-pulse" />
        <span className="text-sm text-gray-300">
          <span className="font-bold text-white">{messageRate}</span> msg/s
        </span>
        <span className="text-gray-500">·</span>
        <span className="text-sm text-gray-300">
          <span className="font-bold text-white">{messages.length}</span> total messages
        </span>
      </div>

      <div className="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden">
        <div className="px-4 py-3 border-b border-gray-700">
          <h3 className="text-sm font-semibold text-white">ZIB Message Stream</h3>
        </div>
        <div className="divide-y divide-gray-700/50 max-h-[500px] overflow-y-auto font-mono">
          {messages.slice(0, 100).map((msg) => (
            <div key={msg.id} className="flex items-center gap-3 px-4 py-2 hover:bg-gray-700/30">
              <span className="text-xs text-gray-600 w-20 flex-shrink-0">
                {new Date(msg.timestamp).toLocaleTimeString()}
              </span>
              <span
                className="text-xs w-16 flex-shrink-0 font-medium"
                style={{ color: priorityColors[msg.priority] }}
              >
                {msg.priority}
              </span>
              <span className="text-xs text-blue-400 w-32 flex-shrink-0 truncate">{msg.source}</span>
              <span className="text-xs text-gray-300 flex-1 truncate">{msg.topic}</span>
              <span className="text-xs text-gray-600 flex-shrink-0">{msg.payloadSize}B</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

// =============================================================================
// Scheduler stats tab
// =============================================================================

const SchedulerStatsView: React.FC = () => {
  const stats = useZenithStore((s) => s.schedulerStats);

  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
      {[
        { label: 'Queue Depth',       value: stats.queueDepth,           color: '#0078D4' },
        { label: 'Total Submitted',   value: stats.totalSubmitted,       color: '#888888' },
        { label: 'Total Scheduled',   value: stats.totalScheduled,       color: '#FF9800' },
        { label: 'Total Completed',   value: stats.totalCompleted,       color: '#00C851' },
        { label: 'Total Failed',      value: stats.totalFailed,          color: '#FF4444' },
        { label: 'Total Cancelled',   value: stats.totalCancelled,       color: '#888888' },
        { label: 'Total Dropped',     value: stats.totalDropped,         color: '#FF6B35' },
        { label: 'Tasks Dispatched',  value: stats.totalTasksDispatched, color: '#3DDC84' },
        { label: 'Migrations',        value: stats.totalMigrations,      color: '#9B59B6' },
        { label: 'Completion Rate',   value: `${(stats.completionRate * 100).toFixed(1)}%`, color: '#00C851' },
        { label: 'Failure Rate',      value: `${(stats.failureRate * 100).toFixed(1)}%`,   color: '#FF4444' },
        { label: 'Drop Rate',         value: `${(stats.dropRate * 100).toFixed(1)}%`,      color: '#FF9800' },
      ].map(({ label, value, color }) => (
        <div key={label} className="bg-gray-800 rounded-xl border border-gray-700 p-4">
          <div className="text-xs text-gray-400 mb-1 uppercase tracking-wider">{label}</div>
          <div className="text-xl font-bold" style={{ color }}>{value}</div>
        </div>
      ))}
    </div>
  );
};

// =============================================================================
// Main App
// =============================================================================

const App: React.FC = () => {
  const [activeTab, setActiveTab] = useState('domains');
  const isConnected    = useZenithStore((s) => s.isConnected);
  const darkMode       = useZenithStore((s) => s.darkMode);
  const sidebarCollapsed = useZenithStore((s) => s.sidebarCollapsed);
  const unreadCount    = useZenithStore((s) => s.unreadCount);
  const securityEvents = useZenithStore((s) => s.securityEvents);
  const toggleDark     = useZenithStore((s) => s.toggleDarkMode);
  const toggleSidebar  = useZenithStore((s) => s.toggleSidebar);

  // Connect to ZIB
  useZenithBus('ws://localhost:7890/zib');

  // Apply dark mode class
  useEffect(() => {
    document.documentElement.classList.toggle('dark', darkMode);
  }, [darkMode]);

  const criticalSecurityCount = securityEvents.filter(
    (e) => e.severity === 'Critical'
  ).length;

  const navItems: NavItem[] = [
    { id: 'domains',    label: 'Domains',    icon: <Cpu size={16} />,      },
    { id: 'intents',    label: 'Intents',    icon: <Target size={16} />,   },
    { id: 'migrations', label: 'Migrations', icon: <GitBranch size={16} />,},
    { id: 'security',   label: 'Security',   icon: <Shield size={16} />,   badge: criticalSecurityCount },
    { id: 'bus',        label: 'Message Bus', icon: <Radio size={16} />,   },
    { id: 'scheduler',  label: 'Scheduler',  icon: <BarChart2 size={16} />,},
    { id: 'terminal',   label: 'Terminal',   icon: <Terminal size={16} />, },
  ];

  const renderContent = () => {
    switch (activeTab) {
      case 'domains':    return <DomainMonitor />;
      case 'intents':    return <IntentDashboard />;
      case 'migrations': return <MigrationEvents />;
      case 'security':   return <SecurityCenter />;
      case 'bus':        return <BusMessageLog />;
      case 'scheduler':  return <SchedulerStatsView />;
      case 'terminal':   return (
        <div className="bg-gray-900 rounded-xl border border-gray-700 p-4 font-mono text-sm text-green-400 h-96 overflow-y-auto">
          <div>Surface Zenith OS v0.1.0-alpha</div>
          <div className="text-gray-500">Zenith Intent Scheduler (ZIS) active</div>
          <div className="text-gray-500">Zenith Interdomain Bus (ZIB) {isConnected ? 'connected' : 'disconnected'}</div>
          <div className="mt-2">$ _</div>
        </div>
      );
      default: return null;
    }
  };

  return (
    <div className={`flex h-screen overflow-hidden ${darkMode ? 'bg-gray-950 text-white' : 'bg-gray-100 text-gray-900'}`}>
      <Sidebar
        activeTab={activeTab}
        onTabChange={setActiveTab}
        collapsed={sidebarCollapsed}
        onToggle={toggleSidebar}
        navItems={navItems}
      />

      <div className="flex-1 flex flex-col overflow-hidden">
        <Header
          activeTab={activeTab}
          isConnected={isConnected}
          darkMode={darkMode}
          onToggleDark={toggleDark}
          unreadCount={unreadCount}
        />

        <main className="flex-1 overflow-y-auto p-6">
          <AnimatePresence mode="wait">
            <motion.div
              key={activeTab}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              transition={{ duration: 0.15 }}
            >
              {renderContent()}
            </motion.div>
          </AnimatePresence>
        </main>
      </div>
    </div>
  );
};

// Fix missing import
const Target = ({ size }: { size: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
    <circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/>
  </svg>
);

export default App;
