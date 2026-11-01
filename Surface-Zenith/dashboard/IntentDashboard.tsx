// =============================================================================
// Surface Zenith OS — Intent Dashboard Component (React/TypeScript)
// File: dashboard/src/components/IntentDashboard.tsx
//
// Visualizes the intent queue, active intents, and scheduling history.
// Shows the Zenith Intent Scheduler (ZIS) in real time.
// =============================================================================

import React, { useState, useMemo } from 'react';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, PieChart, Pie, Cell, LineChart, Line,
} from 'recharts';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Target, Clock, CheckCircle, XCircle, Zap,
  Filter, Search, ArrowRight, TrendingUp,
} from 'lucide-react';
import { useZenithStore, Intent, IntentClass, IntentState } from '../store/zenithStore';
import { formatDistanceToNow } from 'date-fns';

// =============================================================================
// Constants
// =============================================================================

const CLASS_COLORS: Record<IntentClass, string> = {
  Messaging:    '#3DDC84',
  Telephony:    '#00BCD4',
  Productivity: '#0078D4',
  Development:  '#FF9800',
  Graphics:     '#E91E63',
  Inference:    '#FF6B35',
  Media:        '#9C27B0',
  SensorFusion: '#FFC107',
  Quantum:      '#9B59B6',
  CloudSync:    '#17A2B8',
  System:       '#607D8B',
  Unknown:      '#888888',
};

const STATE_COLORS: Record<IntentState, string> = {
  Pending:     '#888888',
  Classifying: '#FFC107',
  Planning:    '#FF9800',
  Queued:      '#0078D4',
  Running:     '#3DDC84',
  Suspended:   '#607D8B',
  Migrating:   '#9B59B6',
  Completed:   '#00C851',
  Failed:      '#FF4444',
  Cancelled:   '#888888',
};

const DOMAIN_COLORS: Record<string, string> = {
  android:  '#3DDC84',
  windows:  '#0078D4',
  ai:       '#FF6B35',
  quantum:  '#9B59B6',
  realtime: '#FFC107',
  cloud:    '#17A2B8',
};

// =============================================================================
// Intent state badge
// =============================================================================

const StateBadge: React.FC<{ state: IntentState }> = ({ state }) => {
  const color = STATE_COLORS[state] || '#888888';
  const isAnimated = state === 'Running' || state === 'Migrating';

  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium text-white ${isAnimated ? 'animate-pulse' : ''}`}
      style={{ backgroundColor: `${color}33`, border: `1px solid ${color}66`, color }}
    >
      {state}
    </span>
  );
};

// =============================================================================
// Intent row
// =============================================================================

const IntentRow: React.FC<{
  intent:   Intent;
  onClick:  () => void;
  selected: boolean;
}> = ({ intent, onClick, selected }) => {
  const classColor  = CLASS_COLORS[intent.class] || '#888888';
  const domainColor = intent.preferredDomain ? DOMAIN_COLORS[intent.preferredDomain] || '#888888' : '#888888';

  return (
    <motion.div
      layout
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: 10 }}
      onClick={onClick}
      className={`
        flex items-center gap-3 p-3 rounded-lg cursor-pointer transition-colors
        ${selected ? 'bg-blue-900/30 border border-blue-500/50' : 'hover:bg-gray-700/50 border border-transparent'}
      `}
    >
      {/* Priority indicator */}
      <div
        className="w-1 h-10 rounded-full flex-shrink-0"
        style={{ backgroundColor: intent.priority > 150 ? '#FF4444' : intent.priority > 100 ? '#FF9800' : '#888888' }}
      />

      {/* Class badge */}
      <div
        className="w-8 h-8 rounded-lg flex items-center justify-center text-xs font-bold flex-shrink-0"
        style={{ backgroundColor: `${classColor}22`, color: classColor }}
      >
        {intent.class.slice(0, 2).toUpperCase()}
      </div>

      {/* Goal text */}
      <div className="flex-1 min-w-0">
        <p className="text-sm text-white truncate font-medium">{intent.goal}</p>
        <div className="flex items-center gap-2 mt-0.5">
          <span className="text-xs text-gray-500">
            {formatDistanceToNow(intent.submittedAt, { addSuffix: true })}
          </span>
          {intent.preferredDomain && (
            <>
              <span className="text-gray-600">·</span>
              <span className="text-xs" style={{ color: domainColor }}>
                {intent.preferredDomain}
              </span>
            </>
          )}
          {intent.score !== 0 && (
            <>
              <span className="text-gray-600">·</span>
              <span className="text-xs text-gray-500">score: {intent.score}</span>
            </>
          )}
        </div>
      </div>

      {/* State badge */}
      <StateBadge state={intent.state} />

      {/* Duration */}
      {intent.durationMs !== null && (
        <span className="text-xs text-gray-500 flex-shrink-0">
          {intent.durationMs}ms
        </span>
      )}
    </motion.div>
  );
};

// =============================================================================
// Intent detail panel
// =============================================================================

const IntentDetailPanel: React.FC<{ intent: Intent }> = ({ intent }) => {
  const classColor = CLASS_COLORS[intent.class] || '#888888';

  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      className="bg-gray-800 rounded-xl border border-gray-700 p-4 space-y-4"
    >
      <div className="flex items-start justify-between">
        <div>
          <h3 className="text-sm font-bold text-white">{intent.goal}</h3>
          <p className="text-xs text-gray-400 mt-1">ID: {intent.id.slice(0, 16)}...</p>
        </div>
        <StateBadge state={intent.state} />
      </div>

      <div className="grid grid-cols-2 gap-2">
        {[
          { label: 'Class',    value: intent.class,                          color: classColor },
          { label: 'Priority', value: intent.priority.toString(),            color: intent.priority > 150 ? '#FF4444' : '#888888' },
          { label: 'Domain',   value: intent.preferredDomain || 'Auto',      color: intent.preferredDomain ? DOMAIN_COLORS[intent.preferredDomain] : '#888888' },
          { label: 'Score',    value: intent.score.toString(),               color: '#888888' },
          { label: 'Energy',   value: `${intent.energyCost} units`,          color: '#888888' },
          { label: 'Latency',  value: `${intent.latencyBudgetMs}ms budget`,  color: '#888888' },
        ].map(({ label, value, color }) => (
          <div key={label} className="bg-gray-900 rounded-lg p-2">
            <div className="text-xs text-gray-500">{label}</div>
            <div className="text-sm font-medium mt-0.5" style={{ color }}>{value}</div>
          </div>
        ))}
      </div>

      {intent.durationMs !== null && (
        <div className="flex items-center gap-2 p-2 bg-green-900/20 rounded-lg border border-green-500/20">
          <CheckCircle size={14} className="text-green-400" />
          <span className="text-xs text-green-400">
            Completed in {intent.durationMs}ms
          </span>
        </div>
      )}

      {intent.errorMessage && (
        <div className="flex items-center gap-2 p-2 bg-red-900/20 rounded-lg border border-red-500/20">
          <XCircle size={14} className="text-red-400" />
          <span className="text-xs text-red-400">{intent.errorMessage}</span>
        </div>
      )}

      {intent.tags.length > 0 && (
        <div className="flex flex-wrap gap-1">
          {intent.tags.map((tag) => (
            <span key={tag} className="px-2 py-0.5 bg-gray-700 rounded text-xs text-gray-400">
              {tag}
            </span>
          ))}
        </div>
      )}
    </motion.div>
  );
};

// =============================================================================
// Stats cards
// =============================================================================

const StatsCard: React.FC<{
  label:   string;
  value:   number | string;
  icon:    React.ReactNode;
  color:   string;
  trend?:  number;
}> = ({ label, value, icon, color, trend }) => (
  <div className="bg-gray-800 rounded-xl border border-gray-700 p-4">
    <div className="flex items-center justify-between mb-2">
      <span className="text-xs text-gray-400 uppercase tracking-wider">{label}</span>
      <div className="p-1.5 rounded-lg" style={{ backgroundColor: `${color}22` }}>
        <div style={{ color }}>{icon}</div>
      </div>
    </div>
    <div className="text-2xl font-bold text-white">{value}</div>
    {trend !== undefined && (
      <div className={`flex items-center gap-1 mt-1 text-xs ${trend >= 0 ? 'text-green-400' : 'text-red-400'}`}>
        <TrendingUp size={10} />
        <span>{trend >= 0 ? '+' : ''}{trend.toFixed(1)}%</span>
      </div>
    )}
  </div>
);

// =============================================================================
// Class distribution chart
// =============================================================================

const ClassDistributionChart: React.FC<{ intents: Intent[] }> = ({ intents }) => {
  const data = useMemo(() => {
    const counts: Partial<Record<IntentClass, number>> = {};
    intents.forEach((i) => {
      counts[i.class] = (counts[i.class] || 0) + 1;
    });
    return Object.entries(counts)
      .map(([cls, count]) => ({ name: cls, value: count }))
      .sort((a, b) => b.value - a.value)
      .slice(0, 6);
  }, [intents]);

  if (data.length === 0) {
    return (
      <div className="flex items-center justify-center h-32 text-gray-500 text-sm">
        No intent data yet
      </div>
    );
  }

  return (
    <ResponsiveContainer width="100%" height={160}>
      <PieChart>
        <Pie
          data={data}
          cx="50%" cy="50%"
          innerRadius={40} outerRadius={70}
          paddingAngle={3}
          dataKey="value"
        >
          {data.map((entry) => (
            <Cell
              key={entry.name}
              fill={CLASS_COLORS[entry.name as IntentClass] || '#888888'}
            />
          ))}
        </Pie>
        <Tooltip
          contentStyle={{ backgroundColor: '#1F2937', border: '1px solid #374151', borderRadius: '8px' }}
          formatter={(value: number, name: string) => [value, name]}
        />
      </PieChart>
    </ResponsiveContainer>
  );
};

// =============================================================================
// Throughput chart
// =============================================================================

const ThroughputChart: React.FC<{ intents: Intent[] }> = ({ intents }) => {
  const data = useMemo(() => {
    // Group by minute (last 10 minutes)
    const now = Date.now();
    return Array.from({ length: 10 }, (_, i) => {
      const minuteStart = now - (9 - i) * 60_000;
      const minuteEnd   = minuteStart + 60_000;
      const count = intents.filter(
        (intent) => intent.submittedAt >= minuteStart && intent.submittedAt < minuteEnd
      ).length;
      return { minute: `-${9 - i}m`, count };
    });
  }, [intents]);

  return (
    <ResponsiveContainer width="100%" height={100}>
      <BarChart data={data} margin={{ top: 0, right: 0, left: -30, bottom: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#333" />
        <XAxis dataKey="minute" tick={{ fontSize: 10, fill: '#6B7280' }} />
        <YAxis tick={{ fontSize: 10, fill: '#6B7280' }} />
        <Tooltip
          contentStyle={{ backgroundColor: '#1F2937', border: '1px solid #374151', borderRadius: '8px' }}
          labelStyle={{ color: '#9CA3AF' }}
        />
        <Bar dataKey="count" fill="#0078D4" radius={[2, 2, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
};

// =============================================================================
// Main IntentDashboard
// =============================================================================

export const IntentDashboard: React.FC = () => {
  const intents        = useZenithStore((s) => s.intents);
  const schedulerStats = useZenithStore((s) => s.schedulerStats);
  const selectedIntent = useZenithStore((s) => s.selectedIntent);
  const setSelected    = useZenithStore((s) => s.setSelectedIntent);

  const [filter, setFilter]   = useState<IntentState | 'All'>('All');
  const [search, setSearch]   = useState('');
  const [classFilter, setClassFilter] = useState<IntentClass | 'All'>('All');

  const filteredIntents = useMemo(() => {
    return intents.filter((i) => {
      const matchesState = filter === 'All' || i.state === filter;
      const matchesClass = classFilter === 'All' || i.class === classFilter;
      const matchesSearch = search === '' ||
        i.goal.toLowerCase().includes(search.toLowerCase()) ||
        i.id.includes(search);
      return matchesState && matchesClass && matchesSearch;
    });
  }, [intents, filter, classFilter, search]);

  const selectedIntentData = useMemo(
    () => intents.find((i) => i.id === selectedIntent),
    [intents, selectedIntent]
  );

  const activeCount    = intents.filter((i) => i.state === 'Running').length;
  const completedCount = intents.filter((i) => i.state === 'Completed').length;
  const failedCount    = intents.filter((i) => i.state === 'Failed').length;

  return (
    <div className="space-y-4">
      {/* Stats row */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <StatsCard
          label="Queue Depth"
          value={schedulerStats.queueDepth}
          icon={<Target size={14} />}
          color="#0078D4"
        />
        <StatsCard
          label="Active"
          value={activeCount}
          icon={<Zap size={14} />}
          color="#3DDC84"
        />
        <StatsCard
          label="Completed"
          value={completedCount}
          icon={<CheckCircle size={14} />}
          color="#00C851"
          trend={schedulerStats.completionRate * 100}
        />
        <StatsCard
          label="Failed"
          value={failedCount}
          icon={<XCircle size={14} />}
          color="#FF4444"
          trend={-schedulerStats.failureRate * 100}
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        {/* Intent list */}
        <div className="lg:col-span-2 space-y-3">
          {/* Filters */}
          <div className="flex items-center gap-2 flex-wrap">
            <div className="relative flex-1 min-w-48">
              <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
              <input
                type="text"
                placeholder="Search intents..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="w-full pl-8 pr-3 py-1.5 bg-gray-800 border border-gray-700 rounded-lg text-sm text-white placeholder-gray-500 focus:outline-none focus:border-blue-500"
              />
            </div>

            <select
              value={filter}
              onChange={(e) => setFilter(e.target.value as IntentState | 'All')}
              className="px-3 py-1.5 bg-gray-800 border border-gray-700 rounded-lg text-sm text-white focus:outline-none focus:border-blue-500"
            >
              <option value="All">All States</option>
              {(['Pending','Running','Completed','Failed','Migrating','Queued'] as IntentState[]).map((s) => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>

            <select
              value={classFilter}
              onChange={(e) => setClassFilter(e.target.value as IntentClass | 'All')}
              className="px-3 py-1.5 bg-gray-800 border border-gray-700 rounded-lg text-sm text-white focus:outline-none focus:border-blue-500"
            >
              <option value="All">All Classes</option>
              {Object.keys(CLASS_COLORS).map((cls) => (
                <option key={cls} value={cls}>{cls}</option>
              ))}
            </select>
          </div>

          {/* Intent list */}
          <div className="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-700 flex items-center justify-between">
              <h3 className="text-sm font-semibold text-white">
                Intents
                <span className="ml-2 text-xs text-gray-400">({filteredIntents.length})</span>
              </h3>
              <Filter size={14} className="text-gray-400" />
            </div>

            <div className="divide-y divide-gray-700/50 max-h-96 overflow-y-auto">
              <AnimatePresence>
                {filteredIntents.length === 0 ? (
                  <div className="flex items-center justify-center py-12 text-gray-500 text-sm">
                    No intents match the current filters
                  </div>
                ) : (
                  filteredIntents.slice(0, 50).map((intent) => (
                    <IntentRow
                      key={intent.id}
                      intent={intent}
                      onClick={() => setSelected(
                        selectedIntent === intent.id ? null : intent.id
                      )}
                      selected={selectedIntent === intent.id}
                    />
                  ))
                )}
              </AnimatePresence>
            </div>
          </div>
        </div>

        {/* Right panel */}
        <div className="space-y-4">
          {/* Selected intent detail */}
          <AnimatePresence mode="wait">
            {selectedIntentData && (
              <IntentDetailPanel key={selectedIntentData.id} intent={selectedIntentData} />
            )}
          </AnimatePresence>

          {/* Class distribution */}
          <div className="bg-gray-800 rounded-xl border border-gray-700 p-4">
            <h3 className="text-sm font-semibold text-white mb-3">Intent Classes</h3>
            <ClassDistributionChart intents={intents} />
            <div className="grid grid-cols-2 gap-1 mt-2">
              {Object.entries(CLASS_COLORS).slice(0, 6).map(([cls, color]) => (
                <div key={cls} className="flex items-center gap-1.5">
                  <div className="w-2 h-2 rounded-full" style={{ backgroundColor: color }} />
                  <span className="text-xs text-gray-400">{cls}</span>
                </div>
              ))}
            </div>
          </div>

          {/* Throughput */}
          <div className="bg-gray-800 rounded-xl border border-gray-700 p-4">
            <h3 className="text-sm font-semibold text-white mb-3">Throughput (10min)</h3>
            <ThroughputChart intents={intents} />
          </div>
        </div>
      </div>
    </div>
  );
};

export default IntentDashboard;