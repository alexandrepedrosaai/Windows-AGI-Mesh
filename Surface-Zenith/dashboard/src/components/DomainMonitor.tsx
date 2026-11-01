// =============================================================================
// Surface Zenith OS — Domain Monitor Component (React/TypeScript)
// File: dashboard/src/components/DomainMonitor.tsx
//
// Real-time visualization of all domain health metrics.
// Displays CPU, memory, task counts, and health status for each domain.
// =============================================================================

import React, { useMemo } from 'react';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, RadialBarChart, RadialBar, Legend,
} from 'recharts';
import { motion, AnimatePresence } from 'framer-motion';
import { Activity, Cpu, HardDrive, Zap, AlertTriangle, CheckCircle, Clock } from 'lucide-react';
import { useZenithStore, DomainName, DomainMetrics, DomainHealth } from '../store/zenithStore';

// =============================================================================
// Domain configuration
// =============================================================================

interface DomainConfig {
  name:        DomainName;
  label:       string;
  icon:        string;
  color:       string;
  description: string;
}

const DOMAIN_CONFIGS: DomainConfig[] = [
  { name: 'android',  label: 'Android',  icon: '🤖', color: '#3DDC84', description: 'Mobile apps, telephony, sensors' },
  { name: 'windows',  label: 'Windows',  icon: '🪟', color: '#0078D4', description: 'Desktop productivity, Win32, .NET' },
  { name: 'ai',       label: 'AI',       icon: '🧠', color: '#FF6B35', description: 'LLM inference, Copilot, NPU' },
  { name: 'quantum',  label: 'Quantum',  icon: '⚛',  color: '#9B59B6', description: 'QPU circuits, QKD security' },
  { name: 'realtime', label: 'RealTime', icon: '⚡', color: '#FFC107', description: 'DSP, audio, sensor fusion' },
  { name: 'cloud',    label: 'Cloud',    icon: '☁',  color: '#17A2B8', description: 'Azure offload, sync, edge' },
];

// =============================================================================
// Health badge
// =============================================================================

const HealthBadge: React.FC<{ health: DomainHealth }> = ({ health }) => {
  const config = useMemo(() => {
    switch (health) {
      case 'Healthy':      return { color: 'bg-green-500',  text: 'Healthy',      icon: <CheckCircle size={12} /> };
      case 'Degraded':     return { color: 'bg-yellow-500', text: 'Degraded',     icon: <AlertTriangle size={12} /> };
      case 'Failed':       return { color: 'bg-red-500',    text: 'Failed',       icon: <AlertTriangle size={12} /> };
      case 'Initializing': return { color: 'bg-blue-500',   text: 'Starting',     icon: <Clock size={12} /> };
      case 'Suspended':    return { color: 'bg-gray-500',   text: 'Suspended',    icon: <Clock size={12} /> };
      default:             return { color: 'bg-gray-600',   text: 'Unknown',      icon: <Activity size={12} /> };
    }
  }, [health]);

  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium text-white ${config.color}`}>
      {config.icon}
      {config.text}
    </span>
  );
};

// =============================================================================
// Metric bar
// =============================================================================

const MetricBar: React.FC<{
  label:   string;
  value:   number;
  color:   string;
  icon:    React.ReactNode;
}> = ({ label, value, color, icon }) => {
  const clampedValue = Math.min(100, Math.max(0, value));
  const isHigh = clampedValue > 85;

  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between text-xs text-gray-400">
        <span className="flex items-center gap-1">{icon}{label}</span>
        <span className={isHigh ? 'text-red-400 font-bold' : 'text-gray-300'}>
          {clampedValue.toFixed(1)}%
        </span>
      </div>
      <div className="h-1.5 bg-gray-700 rounded-full overflow-hidden">
        <motion.div
          className="h-full rounded-full"
          style={{ backgroundColor: isHigh ? '#EF4444' : color }}
          initial={{ width: 0 }}
          animate={{ width: `${clampedValue}%` }}
          transition={{ duration: 0.5, ease: 'easeOut' }}
        />
      </div>
    </div>
  );
};

// =============================================================================
// Domain card
// =============================================================================

const DomainCard: React.FC<{
  config:  DomainConfig;
  metrics: DomainMetrics;
  onClick: () => void;
  selected: boolean;
}> = ({ config, metrics, onClick, selected }) => {
  const isHealthy = metrics.health === 'Healthy';
  const isFailed  = metrics.health === 'Failed';

  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className={`
        relative p-4 rounded-xl cursor-pointer transition-all duration-200
        bg-gray-800 border
        ${selected ? 'border-blue-500 shadow-lg shadow-blue-500/20' : 'border-gray-700 hover:border-gray-500'}
        ${isFailed ? 'border-red-500/50' : ''}
      `}
    >
      {/* Pulse indicator for active domains */}
      {isHealthy && metrics.activeTaskCount > 0 && (
        <span className="absolute top-3 right-3">
          <span className="relative flex h-2 w-2">
            <span
              className="animate-ping absolute inline-flex h-full w-full rounded-full opacity-75"
              style={{ backgroundColor: config.color }}
            />
            <span
              className="relative inline-flex rounded-full h-2 w-2"
              style={{ backgroundColor: config.color }}
            />
          </span>
        </span>
      )}

      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div
          className="w-9 h-9 rounded-full flex items-center justify-center text-lg flex-shrink-0"
          style={{ backgroundColor: `${config.color}22`, border: `1px solid ${config.color}44` }}
        >
          {config.icon}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <h3 className="text-sm font-semibold text-white">{config.label}</h3>
            <HealthBadge health={metrics.health} />
          </div>
          <p className="text-xs text-gray-500 truncate">{config.description}</p>
        </div>
      </div>

      {/* Metrics */}
      <div className="space-y-2">
        <MetricBar
          label="CPU"
          value={metrics.cpuUsagePct}
          color={config.color}
          icon={<Cpu size={10} />}
        />
        <MetricBar
          label="Memory"
          value={metrics.memoryUsagePct}
          color={config.color}
          icon={<HardDrive size={10} />}
        />
      </div>

      {/* Footer stats */}
      <div className="flex items-center justify-between mt-3 pt-3 border-t border-gray-700">
        <div className="flex items-center gap-1 text-xs text-gray-400">
          <Activity size={10} />
          <span>{metrics.activeTaskCount} active</span>
        </div>
        <div className="flex items-center gap-3 text-xs text-gray-500">
          <span className="text-green-400">{metrics.completedTasks} done</span>
          {metrics.failedTasks > 0 && (
            <span className="text-red-400">{metrics.failedTasks} failed</span>
          )}
        </div>
      </div>
    </motion.div>
  );
};

// =============================================================================
// CPU history chart
// =============================================================================

const CpuHistoryChart: React.FC<{ domain: DomainName; color: string }> = ({ domain, color }) => {
  // Generate mock history data (in production: from store time-series)
  const data = useMemo(() => {
    return Array.from({ length: 20 }, (_, i) => ({
      time: i,
      cpu:  Math.random() * 60 + 20,
      mem:  Math.random() * 40 + 30,
    }));
  }, [domain]);

  return (
    <ResponsiveContainer width="100%" height={80}>
      <AreaChart data={data} margin={{ top: 0, right: 0, left: -30, bottom: 0 }}>
        <defs>
          <linearGradient id={`grad-${domain}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%"  stopColor={color} stopOpacity={0.3} />
            <stop offset="95%" stopColor={color} stopOpacity={0}   />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke="#333" />
        <XAxis dataKey="time" hide />
        <YAxis domain={[0, 100]} hide />
        <Tooltip
          contentStyle={{ backgroundColor: '#1F2937', border: '1px solid #374151', borderRadius: '8px' }}
          labelStyle={{ color: '#9CA3AF' }}
          itemStyle={{ color: color }}
        />
        <Area
          type="monotone"
          dataKey="cpu"
          stroke={color}
          strokeWidth={2}
          fill={`url(#grad-${domain})`}
          dot={false}
          activeDot={{ r: 4, fill: color }}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
};

// =============================================================================
// Domain detail panel
// =============================================================================

const DomainDetailPanel: React.FC<{
  config:  DomainConfig;
  metrics: DomainMetrics;
}> = ({ config, metrics }) => {
  return (
    <motion.div
      initial={{ opacity: 0, x: 20 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: 20 }}
      className="bg-gray-800 rounded-xl border border-gray-700 p-5"
    >
      <div className="flex items-center gap-3 mb-4">
        <div
          className="w-10 h-10 rounded-full flex items-center justify-center text-xl"
          style={{ backgroundColor: `${config.color}22` }}
        >
          {config.icon}
        </div>
        <div>
          <h2 className="text-lg font-bold text-white">{config.label} Domain</h2>
          <p className="text-sm text-gray-400">{config.description}</p>
        </div>
        <div className="ml-auto">
          <HealthBadge health={metrics.health} />
        </div>
      </div>

      {/* CPU history */}
      <div className="mb-4">
        <h3 className="text-xs font-medium text-gray-400 mb-2 uppercase tracking-wider">CPU History</h3>
        <CpuHistoryChart domain={config.name} color={config.color} />
      </div>

      {/* Detailed metrics grid */}
      <div className="grid grid-cols-2 gap-3">
        {[
          { label: 'CPU Usage',      value: `${metrics.cpuUsagePct.toFixed(1)}%`,    icon: <Cpu size={14} /> },
          { label: 'Memory Usage',   value: `${metrics.memoryUsagePct.toFixed(1)}%`, icon: <HardDrive size={14} /> },
          { label: 'Active Tasks',   value: metrics.activeTaskCount.toString(),       icon: <Activity size={14} /> },
          { label: 'Completed',      value: metrics.completedTasks.toString(),        icon: <CheckCircle size={14} /> },
          { label: 'Failed',         value: metrics.failedTasks.toString(),           icon: <AlertTriangle size={14} /> },
          { label: 'Uptime',         value: formatUptime(metrics.uptimeMs),           icon: <Clock size={14} /> },
        ].map(({ label, value, icon }) => (
          <div key={label} className="bg-gray-900 rounded-lg p-3">
            <div className="flex items-center gap-1.5 text-gray-400 text-xs mb-1">
              {icon}
              <span>{label}</span>
            </div>
            <div className="text-white font-semibold text-sm">{value}</div>
          </div>
        ))}
      </div>
    </motion.div>
  );
};

// =============================================================================
// Radial overview chart
// =============================================================================

const DomainRadialOverview: React.FC = () => {
  const domains = useZenithStore((s) => s.domains);

  const data = DOMAIN_CONFIGS.map((cfg) => ({
    name:  cfg.label,
    cpu:   domains[cfg.name].cpuUsagePct,
    fill:  cfg.color,
  }));

  return (
    <div className="bg-gray-800 rounded-xl border border-gray-700 p-4">
      <h3 className="text-sm font-semibold text-white mb-3">CPU Overview</h3>
      <ResponsiveContainer width="100%" height={200}>
        <RadialBarChart
          cx="50%" cy="50%"
          innerRadius="20%" outerRadius="90%"
          data={data}
          startAngle={180} endAngle={0}
        >
          <RadialBar
            dataKey="cpu"
            cornerRadius={4}
            background={{ fill: '#374151' }}
          />
          <Legend
            iconSize={8}
            layout="vertical"
            verticalAlign="middle"
            align="right"
            formatter={(value) => (
              <span className="text-xs text-gray-400">{value}</span>
            )}
          />
          <Tooltip
            contentStyle={{ backgroundColor: '#1F2937', border: '1px solid #374151', borderRadius: '8px' }}
            formatter={(value: number) => [`${value.toFixed(1)}%`, 'CPU']}
          />
        </RadialBarChart>
      </ResponsiveContainer>
    </div>
  );
};

// =============================================================================
// Main DomainMonitor component
// =============================================================================

export const DomainMonitor: React.FC = () => {
  const domains        = useZenithStore((s) => s.domains);
  const selectedDomain = useZenithStore((s) => s.selectedDomain);
  const setSelected    = useZenithStore((s) => s.setSelectedDomain);

  const selectedConfig  = DOMAIN_CONFIGS.find((c) => c.name === selectedDomain);
  const selectedMetrics = selectedDomain ? domains[selectedDomain] : null;

  const totalActiveTasks = Object.values(domains).reduce(
    (sum, d) => sum + d.activeTaskCount, 0
  );
  const healthyCount = Object.values(domains).filter(
    (d) => d.health === 'Healthy'
  ).length;

  return (
    <div className="space-y-4">
      {/* Summary bar */}
      <div className="flex items-center gap-4 p-3 bg-gray-800 rounded-xl border border-gray-700">
        <div className="flex items-center gap-2">
          <div className="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
          <span className="text-sm text-gray-300">
            <span className="font-semibold text-white">{healthyCount}</span>/{DOMAIN_CONFIGS.length} domains healthy
          </span>
        </div>
        <div className="h-4 w-px bg-gray-600" />
        <div className="flex items-center gap-2">
          <Activity size={14} className="text-blue-400" />
          <span className="text-sm text-gray-300">
            <span className="font-semibold text-white">{totalActiveTasks}</span> active tasks
          </span>
        </div>
        <div className="ml-auto">
          <Zap size={14} className="text-yellow-400" />
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        {/* Domain cards grid */}
        <div className="lg:col-span-2 grid grid-cols-1 sm:grid-cols-2 gap-3">
          <AnimatePresence>
            {DOMAIN_CONFIGS.map((config) => (
              <DomainCard
                key={config.name}
                config={config}
                metrics={domains[config.name]}
                onClick={() => setSelected(
                  selectedDomain === config.name ? null : config.name
                )}
                selected={selectedDomain === config.name}
              />
            ))}
          </AnimatePresence>
        </div>

        {/* Right panel: detail or radial overview */}
        <div className="space-y-4">
          <AnimatePresence mode="wait">
            {selectedConfig && selectedMetrics ? (
              <DomainDetailPanel
                key={selectedConfig.name}
                config={selectedConfig}
                metrics={selectedMetrics}
              />
            ) : (
              <motion.div
                key="overview"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
              >
                <DomainRadialOverview />
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
};

// =============================================================================
// Helpers
// =============================================================================

function formatUptime(ms: number): string {
  if (ms === 0) return '—';
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const h = Math.floor(m / 60);
  const d = Math.floor(h / 24);
  if (d > 0) return `${d}d ${h % 24}h`;
  if (h > 0) return `${h}h ${m % 60}m`;
  if (m > 0) return `${m}m ${s % 60}s`;
  return `${s}s`;
}

export default DomainMonitor;
