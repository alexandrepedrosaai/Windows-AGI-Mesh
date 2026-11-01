// =============================================================================
// Surface Zenith OS — ZenithShell Header
// File: shell/include/ZenithShell.h
// =============================================================================

#pragma once

#include <QMainWindow>
#include <QLabel>
#include <QTimer>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QStackedWidget>

// Forward declarations
class IntentInputBar;
class DomainStatusPanel;
class SessionManager;
class FormFactorAdapter;
class UniversalObjectBrowser;
class CopilotPanel;
class NotificationCenter;
class TaskGraphView;
class ZenithBusClient;
class ThemeEngine;
class QDockWidget;
class QSplitter;

// =============================================================================
// Form factor enum
// =============================================================================

enum class FormFactor : int {
    PhoneFolded    = 0,
    TabletUnfolded = 1,
    Desktop        = 2,
    Laptop         = 3,
    Headless       = 4,
    MixedReality   = 5,
};

// =============================================================================
// ZenithShell — Main Shell Window
// =============================================================================

class ZenithShell : public QMainWindow {
    Q_OBJECT

public:
    explicit ZenithShell(QWidget* parent = nullptr);
    ~ZenithShell() override;

    // Public API
    void connectToBus(const QString& url) {
        m_busClient->connectToHost(url);
    }
    void adaptToFormFactor(FormFactor newFormFactor);
    FormFactor currentFormFactor() const { return m_currentFormFactor; }
    double hingeAngle() const { return m_hingeAngle; }

signals:
    void formFactorChanged(FormFactor newFormFactor);
    void sessionChanged(const QString& sessionId);
    void intentSubmitted(const QString& goal);
    void domainHealthChanged(const QString& domain, const QString& status);

public slots:
    void onFormFactorChanged(FormFactor newFormFactor);
    void onHingeAngleChanged(double angle);
    void onSessionOpened(const QString& sessionId, const QString& identityName);
    void onSessionClosed(const QString& sessionId);
    void onBusConnected();
    void onBusDisconnected();
    void onBusMessageReceived(const QString& topic, const QByteArray& payload);
    void onHeartbeat();

private slots:
    // Menu actions
    void onNewSession();
    void onOpenSession();
    void onOpenSettings();
    void onToggleCopilot();
    void onToggleTaskGraph();
    void onToggleDomainPanel();
    void onShowAndroidStatus();
    void onShowWindowsStatus();
    void onShowAIStatus();
    void onShowQuantumStatus();
    void onMigrateActiveTasks();
    void onAbout();
    void onOpenDocs();

    // Bus message handlers
    void updateDomainHealth(const QJsonObject& health);
    void onIntentCompleted(const QJsonObject& result);
    void onIntentFailed(const QJsonObject& result);
    void onTaskMigrated(const QJsonObject& migration);
    void onSecurityViolation(const QJsonObject& violation);
    void updateMetrics(const QJsonObject& metrics);

private:
    // Initialization
    void initializeTheme();
    void initializeLayout();
    void initializeMenuBar();
    void initializeToolBar();
    void initializeStatusBar();
    void initializeDockWidgets();
    void initializeConnections();
    void initializeBusSubscriptions();
    void startHeartbeat();

    // Helpers
    QLabel* createDomainIndicator(const QString& name, QWidget* parent);
    void publishFormFactorChange(FormFactor formFactor);
    void showDomainStatus(const QString& domain);

    // Core subsystems
    ZenithBusClient*       m_busClient;
    ThemeEngine*           m_themeEngine;
    FormFactorAdapter*     m_formFactorAdapter;
    SessionManager*        m_sessionManager;
    QNetworkAccessManager* m_networkManager;
    QTimer*                m_heartbeatTimer;

    // Layout widgets
    QStackedWidget*        m_centralStack;
    QWidget*               m_phoneLayout;
    QWidget*               m_tabletLayout;
    QWidget*               m_desktopLayout;

    // UI components
    IntentInputBar*        m_intentBar      = nullptr;
    DomainStatusPanel*     m_domainPanel    = nullptr;
    UniversalObjectBrowser* m_objectBrowser = nullptr;
    CopilotPanel*          m_copilotPanel   = nullptr;
    QDockWidget*           m_notificationDock = nullptr;

    // Toolbar widgets
    QLabel* m_sessionLabel     = nullptr;
    QLabel* m_androidIndicator = nullptr;
    QLabel* m_windowsIndicator = nullptr;
    QLabel* m_aiIndicator      = nullptr;
    QLabel* m_quantumIndicator = nullptr;
    QLabel* m_hingeLabel       = nullptr;

    // Status bar widgets
    QLabel* m_statusLabel      = nullptr;
    QLabel* m_queueDepthLabel  = nullptr;
    QLabel* m_activeTasksLabel = nullptr;
    QLabel* m_memoryLabel      = nullptr;

    // State
    FormFactor  m_currentFormFactor;
    double      m_hingeAngle;
    bool        m_isAnimating;
    QString     m_currentSessionId;
    int         m_schedulerQueueDepth = 0;
    int         m_activeTaskCount     = 0;
};