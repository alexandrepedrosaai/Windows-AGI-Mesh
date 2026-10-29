// =============================================================================
// Surface Zenith OS — Zenith Shell (Qt/C++)
// File: shell/src/ZenithShell.cpp
//
// The Zenith Shell is the primary user interface layer of the Surface Zenith OS.
// It provides:
//   - Intent input (natural language command bar)
//   - Session management UI
//   - Domain status dashboard
//   - Form factor adaptation (fold/unfold detection)
//   - Universal Object Browser
//   - AI Copilot integration panel
//   - Notification center
//   - Task graph visualization
// =============================================================================

#include "ZenithShell.h"
#include "IntentInputBar.h"
#include "DomainStatusPanel.h"
#include "SessionManager.h"
#include "FormFactorAdapter.h"
#include "UniversalObjectBrowser.h"
#include "CopilotPanel.h"
#include "NotificationCenter.h"
#include "TaskGraphView.h"
#include "ZenithBusClient.h"
#include "ThemeEngine.h"

#include <QApplication>
#include <QMainWindow>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QSplitter>
#include <QStackedWidget>
#include <QStatusBar>
#include <QMenuBar>
#include <QToolBar>
#include <QDockWidget>
#include <QTimer>
#include <QScreen>
#include <QWindow>
#include <QPropertyAnimation>
#include <QGraphicsOpacityEffect>
#include <QSettings>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QWebSocket>
#include <QSslConfiguration>
#include <QLoggingCategory>
#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include <QFuture>
#include <QtConcurrent>
#include <QOpenGLWidget>
#include <QOpenGLFunctions>
#include <QSGNode>
#include <QQuickWidget>
#include <QQmlEngine>
#include <QQmlContext>

Q_LOGGING_CATEGORY(lcZenithShell, "zenith.shell")

// =============================================================================
// ZenithShell — Main Shell Window
// =============================================================================

ZenithShell::ZenithShell(QWidget* parent)
    : QMainWindow(parent)
    , m_busClient(new ZenithBusClient(this))
    , m_themeEngine(new ThemeEngine(this))
    , m_formFactorAdapter(new FormFactorAdapter(this))
    , m_sessionManager(new SessionManager(this))
    , m_networkManager(new QNetworkAccessManager(this))
    , m_heartbeatTimer(new QTimer(this))
    , m_currentFormFactor(FormFactor::PhoneFolded)
    , m_hingeAngle(0.0)
    , m_isAnimating(false)
{
    setObjectName("ZenithShell");
    setWindowTitle("Surface Zenith OS");
    setMinimumSize(360, 640);

    // Initialize subsystems
    initializeTheme();
    initializeLayout();
    initializeMenuBar();
    initializeToolBar();
    initializeStatusBar();
    initializeDockWidgets();
    initializeConnections();
    initializeBusSubscriptions();
    startHeartbeat();

    qCInfo(lcZenithShell) << "ZenithShell initialized";
}

ZenithShell::~ZenithShell()
{
    m_heartbeatTimer->stop();
    m_busClient->disconnect();
    qCInfo(lcZenithShell) << "ZenithShell destroyed";
}

// =============================================================================
// Initialization
// =============================================================================

void ZenithShell::initializeTheme()
{
    m_themeEngine->loadTheme("zenith-dark");
    m_themeEngine->setAccentColor(QColor(0x00, 0x78, 0xD4)); // Microsoft Blue
    setStyleSheet(m_themeEngine->generateStyleSheet());
}

void ZenithShell::initializeLayout()
{
    // Central widget with stacked layout for form factor adaptation
    m_centralStack = new QStackedWidget(this);
    setCentralWidget(m_centralStack);

    // ---- Phone layout (folded) -----------------------------------------------
    m_phoneLayout = new QWidget();
    auto* phoneVBox = new QVBoxLayout(m_phoneLayout);
    phoneVBox->setContentsMargins(0, 0, 0, 0);
    phoneVBox->setSpacing(0);

    m_intentBar = new IntentInputBar(this);
    m_intentBar->setPlaceholderText("What would you like to do?");
    m_intentBar->setFixedHeight(56);

    m_objectBrowser = new UniversalObjectBrowser(this);
    m_copilotPanel  = new CopilotPanel(this);

    phoneVBox->addWidget(m_intentBar);
    phoneVBox->addWidget(m_objectBrowser, 1);
    phoneVBox->addWidget(m_copilotPanel);

    // ---- Tablet layout (unfolded) --------------------------------------------
    m_tabletLayout = new QWidget();
    auto* tabletHBox = new QHBoxLayout(m_tabletLayout);
    tabletHBox->setContentsMargins(0, 0, 0, 0);
    tabletHBox->setSpacing(0);

    auto* tabletSplitter = new QSplitter(Qt::Horizontal, m_tabletLayout);

    // Left panel: object browser + copilot
    auto* leftPanel = new QWidget();
    auto* leftVBox  = new QVBoxLayout(leftPanel);
    leftVBox->setContentsMargins(0, 0, 0, 0);
    leftVBox->addWidget(new IntentInputBar(this));
    leftVBox->addWidget(new UniversalObjectBrowser(this), 1);

    // Right panel: copilot + task graph
    auto* rightPanel = new QWidget();
    auto* rightVBox  = new QVBoxLayout(rightPanel);
    rightVBox->setContentsMargins(0, 0, 0, 0);
    rightVBox->addWidget(new CopilotPanel(this), 1);
    rightVBox->addWidget(new TaskGraphView(this));

    tabletSplitter->addWidget(leftPanel);
    tabletSplitter->addWidget(rightPanel);
    tabletSplitter->setSizes({500, 500});

    tabletHBox->addWidget(tabletSplitter);

    // ---- Desktop layout ------------------------------------------------------
    m_desktopLayout = new QWidget();
    auto* desktopHBox = new QHBoxLayout(m_desktopLayout);
    desktopHBox->setContentsMargins(0, 0, 0, 0);
    desktopHBox->setSpacing(0);

    auto* desktopSplitter = new QSplitter(Qt::Horizontal, m_desktopLayout);

    // Left sidebar: domain status
    m_domainPanel = new DomainStatusPanel(this);
    m_domainPanel->setFixedWidth(280);

    // Center: main content
    auto* centerWidget = new QWidget();
    auto* centerVBox   = new QVBoxLayout(centerWidget);
    centerVBox->setContentsMargins(0, 0, 0, 0);
    centerVBox->addWidget(new IntentInputBar(this));
    centerVBox->addWidget(new UniversalObjectBrowser(this), 1);

    // Right: copilot + task graph
    auto* rightDesktop = new QWidget();
    auto* rightDesktopVBox = new QVBoxLayout(rightDesktop);
    rightDesktopVBox->setContentsMargins(0, 0, 0, 0);
    rightDesktopVBox->addWidget(new CopilotPanel(this), 2);
    rightDesktopVBox->addWidget(new TaskGraphView(this), 1);

    desktopSplitter->addWidget(m_domainPanel);
    desktopSplitter->addWidget(centerWidget);
    desktopSplitter->addWidget(rightDesktop);
    desktopSplitter->setSizes({280, 700, 400});

    desktopHBox->addWidget(desktopSplitter);

    // Add all layouts to stack
    m_centralStack->addWidget(m_phoneLayout);    // index 0
    m_centralStack->addWidget(m_tabletLayout);   // index 1
    m_centralStack->addWidget(m_desktopLayout);  // index 2

    // Start in phone layout
    m_centralStack->setCurrentIndex(0);
}

void ZenithShell::initializeMenuBar()
{
    auto* menuBar = new QMenuBar(this);

    // Zenith menu
    auto* zenithMenu = menuBar->addMenu("&Zenith");
    zenithMenu->addAction("&New Session",    this, &ZenithShell::onNewSession,    QKeySequence::New);
    zenithMenu->addAction("&Open Session",   this, &ZenithShell::onOpenSession,   QKeySequence::Open);
    zenithMenu->addSeparator();
    zenithMenu->addAction("&Settings",       this, &ZenithShell::onOpenSettings,  QKeySequence::Preferences);
    zenithMenu->addSeparator();
    zenithMenu->addAction("E&xit",           qApp, &QApplication::quit,           QKeySequence::Quit);

    // View menu
    auto* viewMenu = menuBar->addMenu("&View");
    viewMenu->addAction("Phone Mode",   this, [this]{ adaptToFormFactor(FormFactor::PhoneFolded); });
    viewMenu->addAction("Tablet Mode",  this, [this]{ adaptToFormFactor(FormFactor::TabletUnfolded); });
    viewMenu->addAction("Desktop Mode", this, [this]{ adaptToFormFactor(FormFactor::Desktop); });
    viewMenu->addSeparator();
    viewMenu->addAction("Toggle &Copilot",    this, &ZenithShell::onToggleCopilot,    QKeySequence("Ctrl+Shift+C"));
    viewMenu->addAction("Toggle &Task Graph", this, &ZenithShell::onToggleTaskGraph,  QKeySequence("Ctrl+Shift+T"));
    viewMenu->addAction("Toggle &Domain Panel", this, &ZenithShell::onToggleDomainPanel);

    // Domains menu
    auto* domainsMenu = menuBar->addMenu("&Domains");
    domainsMenu->addAction("Android Domain Status",  this, &ZenithShell::onShowAndroidStatus);
    domainsMenu->addAction("Windows Domain Status",  this, &ZenithShell::onShowWindowsStatus);
    domainsMenu->addAction("AI Domain Status",       this, &ZenithShell::onShowAIStatus);
    domainsMenu->addAction("Quantum Domain Status",  this, &ZenithShell::onShowQuantumStatus);
    domainsMenu->addSeparator();
    domainsMenu->addAction("Migrate Active Tasks",   this, &ZenithShell::onMigrateActiveTasks);

    // Help menu
    auto* helpMenu = menuBar->addMenu("&Help");
    helpMenu->addAction("&About Surface Zenith", this, &ZenithShell::onAbout);
    helpMenu->addAction("Zenith &Documentation", this, &ZenithShell::onOpenDocs);

    setMenuBar(menuBar);
}

void ZenithShell::initializeToolBar()
{
    auto* toolBar = new QToolBar("Main Toolbar", this);
    toolBar->setObjectName("MainToolBar");
    toolBar->setMovable(false);
    toolBar->setIconSize(QSize(24, 24));

    // Session indicator
    m_sessionLabel = new QLabel("No Session", toolBar);
    m_sessionLabel->setObjectName("sessionLabel");
    toolBar->addWidget(m_sessionLabel);
    toolBar->addSeparator();

    // Domain health indicators
    m_androidIndicator = createDomainIndicator("Android", toolBar);
    m_windowsIndicator = createDomainIndicator("Windows", toolBar);
    m_aiIndicator      = createDomainIndicator("AI",      toolBar);
    m_quantumIndicator = createDomainIndicator("Quantum", toolBar);

    toolBar->addSeparator();

    // Hinge angle display
    m_hingeLabel = new QLabel("Hinge: 0°", toolBar);
    m_hingeLabel->setObjectName("hingeLabel");
    toolBar->addWidget(m_hingeLabel);

    addToolBar(Qt::TopToolBarArea, toolBar);
}

void ZenithShell::initializeStatusBar()
{
    auto* sb = statusBar();

    m_statusLabel = new QLabel("Ready", sb);
    m_queueDepthLabel = new QLabel("Queue: 0", sb);
    m_activeTasksLabel = new QLabel("Tasks: 0", sb);
    m_memoryLabel = new QLabel("Memory: 0%", sb);

    sb->addWidget(m_statusLabel, 1);
    sb->addPermanentWidget(m_queueDepthLabel);
    sb->addPermanentWidget(m_activeTasksLabel);
    sb->addPermanentWidget(m_memoryLabel);
}

void ZenithShell::initializeDockWidgets()
{
    // Notification center dock
    m_notificationDock = new QDockWidget("Notifications", this);
    m_notificationDock->setObjectName("NotificationDock");
    m_notificationDock->setWidget(new NotificationCenter(this));
    m_notificationDock->setAllowedAreas(Qt::RightDockWidgetArea | Qt::BottomDockWidgetArea);
    addDockWidget(Qt::RightDockWidgetArea, m_notificationDock);
    m_notificationDock->hide();
}

void ZenithShell::initializeConnections()
{
    // Form factor adapter
    connect(m_formFactorAdapter, &FormFactorAdapter::formFactorChanged,
            this, &ZenithShell::onFormFactorChanged);
    connect(m_formFactorAdapter, &FormFactorAdapter::hingeAngleChanged,
            this, &ZenithShell::onHingeAngleChanged);

    // Session manager
    connect(m_sessionManager, &SessionManager::sessionOpened,
            this, &ZenithShell::onSessionOpened);
    connect(m_sessionManager, &SessionManager::sessionClosed,
            this, &ZenithShell::onSessionClosed);

    // Bus client
    connect(m_busClient, &ZenithBusClient::connected,
            this, &ZenithShell::onBusConnected);
    connect(m_busClient, &ZenithBusClient::disconnected,
            this, &ZenithShell::onBusDisconnected);
    connect(m_busClient, &ZenithBusClient::messageReceived,
            this, &ZenithShell::onBusMessageReceived);

    // Heartbeat timer
    connect(m_heartbeatTimer, &QTimer::timeout,
            this, &ZenithShell::onHeartbeat);
}

void ZenithShell::initializeBusSubscriptions()
{
    // Subscribe to domain health updates
    m_busClient->subscribe("domain.health");
    m_busClient->subscribe("intent.complete");
    m_busClient->subscribe("intent.failed");
    m_busClient->subscribe("task.migrated");
    m_busClient->subscribe("system.heartbeat");
    m_busClient->subscribe("device.hinge.changed");
    m_busClient->subscribe("security.violation");
    m_busClient->subscribe("system.metrics.snapshot");
}

void ZenithShell::startHeartbeat()
{
    m_heartbeatTimer->setInterval(1000); // 1 Hz
    m_heartbeatTimer->start();
}

// =============================================================================
// Form Factor Adaptation
// =============================================================================

void ZenithShell::adaptToFormFactor(FormFactor newFormFactor)
{
    if (m_currentFormFactor == newFormFactor || m_isAnimating) {
        return;
    }

    qCInfo(lcZenithShell) << "Adapting to form factor:" << static_cast<int>(newFormFactor);

    m_isAnimating = true;

    // Fade out current layout
    auto* fadeOut = new QPropertyAnimation(
        new QGraphicsOpacityEffect(m_centralStack), "opacity", this
    );
    fadeOut->setDuration(150);
    fadeOut->setStartValue(1.0);
    fadeOut->setEndValue(0.0);

    connect(fadeOut, &QPropertyAnimation::finished, this, [this, newFormFactor]() {
        // Switch layout
        switch (newFormFactor) {
            case FormFactor::PhoneFolded:
                m_centralStack->setCurrentIndex(0);
                setMinimumSize(360, 640);
                setMaximumSize(480, 960);
                break;
            case FormFactor::TabletUnfolded:
                m_centralStack->setCurrentIndex(1);
                setMinimumSize(768, 600);
                setMaximumSize(1200, 900);
                break;
            case FormFactor::Desktop:
            case FormFactor::Laptop:
                m_centralStack->setCurrentIndex(2);
                setMinimumSize(1024, 768);
                setMaximumSize(QWIDGETSIZE_MAX, QWIDGETSIZE_MAX);
                break;
            default:
                m_centralStack->setCurrentIndex(1);
                break;
        }

        m_currentFormFactor = newFormFactor;

        // Fade in new layout
        auto* fadeIn = new QPropertyAnimation(
            new QGraphicsOpacityEffect(m_centralStack), "opacity", this
        );
        fadeIn->setDuration(150);
        fadeIn->setStartValue(0.0);
        fadeIn->setEndValue(1.0);
        connect(fadeIn, &QPropertyAnimation::finished, this, [this]() {
            m_isAnimating = false;
        });
        fadeIn->start(QAbstractAnimation::DeleteWhenStopped);

        // Notify session manager
        m_sessionManager->notifyFormFactorChange(newFormFactor);

        // Publish form factor change to ZIB
        publishFormFactorChange(newFormFactor);
    });

    fadeOut->start(QAbstractAnimation::DeleteWhenStopped);
}

void ZenithShell::publishFormFactorChange(FormFactor formFactor)
{
    QJsonObject payload;
    payload["form_factor"] = static_cast<int>(formFactor);
    payload["hinge_angle"] = m_hingeAngle;
    payload["timestamp"]   = QDateTime::currentMSecsSinceEpoch();

    m_busClient->publish("domain.formfactor.changed",
                         QJsonDocument(payload).toJson(QJsonDocument::Compact));
}

// =============================================================================
// Slot implementations
// =============================================================================

void ZenithShell::onFormFactorChanged(FormFactor newFormFactor)
{
    adaptToFormFactor(newFormFactor);
}

void ZenithShell::onHingeAngleChanged(double angle)
{
    m_hingeAngle = angle;
    m_hingeLabel->setText(QString("Hinge: %1°").arg(static_cast<int>(angle)));

    // Auto-adapt based on hinge angle
    if (angle < 10.0) {
        adaptToFormFactor(FormFactor::PhoneFolded);
    } else if (angle < 160.0) {
        adaptToFormFactor(FormFactor::TabletUnfolded);
    } else {
        adaptToFormFactor(FormFactor::Desktop);
    }
}

void ZenithShell::onSessionOpened(const QString& sessionId, const QString& identityName)
{
    m_currentSessionId = sessionId;
    m_sessionLabel->setText(QString("Session: %1 (%2)")
                            .arg(sessionId.left(8))
                            .arg(identityName));
    m_statusLabel->setText("Session active");
    qCInfo(lcZenithShell) << "Session opened:" << sessionId;
}

void ZenithShell::onSessionClosed(const QString& sessionId)
{
    m_currentSessionId.clear();
    m_sessionLabel->setText("No Session");
    m_statusLabel->setText("Session closed");
}

void ZenithShell::onBusConnected()
{
    m_statusLabel->setText("Connected to ZIB");
    qCInfo(lcZenithShell) << "Connected to Zenith Interdomain Bus";
}

void ZenithShell::onBusDisconnected()
{
    m_statusLabel->setText("Disconnected from ZIB");
    qCWarning(lcZenithShell) << "Disconnected from Zenith Interdomain Bus";
    // Attempt reconnection after 5 seconds
    QTimer::singleShot(5000, m_busClient, &ZenithBusClient::reconnect);
}

void ZenithShell::onBusMessageReceived(const QString& topic, const QByteArray& payload)
{
    QJsonDocument doc = QJsonDocument::fromJson(payload);
    if (doc.isNull()) return;

    QJsonObject obj = doc.object();

    if (topic == "domain.health") {
        updateDomainHealth(obj);
    } else if (topic == "intent.complete") {
        onIntentCompleted(obj);
    } else if (topic == "intent.failed") {
        onIntentFailed(obj);
    } else if (topic == "task.migrated") {
        onTaskMigrated(obj);
    } else if (topic == "device.hinge.changed") {
        double angle = obj["hinge_angle_degrees"].toDouble();
        onHingeAngleChanged(angle);
    } else if (topic == "security.violation") {
        onSecurityViolation(obj);
    } else if (topic == "system.metrics.snapshot") {
        updateMetrics(obj);
    }
}

void ZenithShell::onHeartbeat()
{
    // Update status bar metrics
    // In production: query ZIB for real metrics
    m_queueDepthLabel->setText(QString("Queue: %1").arg(m_schedulerQueueDepth));
    m_activeTasksLabel->setText(QString("Tasks: %1").arg(m_activeTaskCount));
}

void ZenithShell::updateDomainHealth(const QJsonObject& health)
{
    QString domain = health["domain"].toString();
    QString status = health["health"].toString();
    double  cpu    = health["cpu_usage_pct"].toDouble();

    QLabel* indicator = nullptr;
    if (domain == "android")  indicator = m_androidIndicator;
    else if (domain == "windows") indicator = m_windowsIndicator;
    else if (domain == "ai")      indicator = m_aiIndicator;
    else if (domain == "quantum") indicator = m_quantumIndicator;

    if (indicator) {
        QString color = (status == "Healthy") ? "#00C851" :
                        (status == "Degraded") ? "#FF8800" : "#FF4444";
        indicator->setStyleSheet(QString("color: %1;").arg(color));
        indicator->setToolTip(QString("%1: %2 (CPU: %3%)")
                              .arg(domain).arg(status).arg(cpu, 0, 'f', 1));
    }
}

void ZenithShell::onIntentCompleted(const QJsonObject& result)
{
    QString intentId = result["intent_id"].toString();
    qint64  durationMs = result["duration_ms"].toInteger();
    m_statusLabel->setText(QString("Intent completed in %1ms").arg(durationMs));
}

void ZenithShell::onIntentFailed(const QJsonObject& result)
{
    QString intentId = result["intent_id"].toString();
    QString error    = result["error_message"].toString();
    m_statusLabel->setText(QString("Intent failed: %1").arg(error));
    qCWarning(lcZenithShell) << "Intent failed:" << intentId << error;
}

void ZenithShell::onTaskMigrated(const QJsonObject& migration)
{
    QString from = migration["from_domain"].toString();
    QString to   = migration["to_domain"].toString();
    m_statusLabel->setText(QString("Task migrated: %1 → %2").arg(from).arg(to));
}

void ZenithShell::onSecurityViolation(const QJsonObject& violation)
{
    QString detail   = violation["detail"].toString();
    QString severity = violation["severity"].toString();

    // Show security alert
    auto* notification = new QLabel(
        QString("⚠ Security: %1 [%2]").arg(detail).arg(severity), this
    );
    notification->setStyleSheet("color: #FF4444; font-weight: bold;");
    statusBar()->addWidget(notification);
    QTimer::singleShot(10000, notification, &QLabel::deleteLater);

    qCCritical(lcZenithShell) << "Security violation:" << detail;
}

void ZenithShell::updateMetrics(const QJsonObject& metrics)
{
    QJsonObject metricsObj = metrics["metrics"].toObject();
    double memUsage = metricsObj["memory_usage_pct"].toDouble();
    m_memoryLabel->setText(QString("Memory: %1%").arg(memUsage, 0, 'f', 1));
    m_schedulerQueueDepth = static_cast<int>(metricsObj["queue_depth"].toDouble());
    m_activeTaskCount     = static_cast<int>(metricsObj["active_tasks"].toDouble());
}

// =============================================================================
// Menu action slots
// =============================================================================

void ZenithShell::onNewSession()
{
    m_sessionManager->createNewSession();
}

void ZenithShell::onOpenSession()
{
    m_sessionManager->openExistingSession();
}

void ZenithShell::onOpenSettings()
{
    // Open settings dialog
    qCInfo(lcZenithShell) << "Opening settings";
}

void ZenithShell::onToggleCopilot()
{
    if (m_copilotPanel) {
        m_copilotPanel->setVisible(!m_copilotPanel->isVisible());
    }
}

void ZenithShell::onToggleTaskGraph()
{
    // Toggle task graph dock
}

void ZenithShell::onToggleDomainPanel()
{
    if (m_domainPanel) {
        m_domainPanel->setVisible(!m_domainPanel->isVisible());
    }
}

void ZenithShell::onShowAndroidStatus()  { showDomainStatus("android"); }
void ZenithShell::onShowWindowsStatus()  { showDomainStatus("windows"); }
void ZenithShell::onShowAIStatus()       { showDomainStatus("ai"); }
void ZenithShell::onShowQuantumStatus()  { showDomainStatus("quantum"); }

void ZenithShell::showDomainStatus(const QString& domain)
{
    qCInfo(lcZenithShell) << "Showing status for domain:" << domain;
    // Query ZIB for domain status and show dialog
    QJsonObject query;
    query["domain"] = domain;
    m_busClient->publish("domain.query",
                         QJsonDocument(query).toJson(QJsonDocument::Compact));
}

void ZenithShell::onMigrateActiveTasks()
{
    qCInfo(lcZenithShell) << "Requesting active task migration";
    QJsonObject request;
    request["trigger"] = "user_requested";
    m_busClient->publish("domain.migrate",
                         QJsonDocument(request).toJson(QJsonDocument::Compact));
}

void ZenithShell::onAbout()
{
    // Show about dialog
    qCInfo(lcZenithShell) << "Surface Zenith OS v0.1.0-alpha";
}

void ZenithShell::onOpenDocs()
{
    qCInfo(lcZenithShell) << "Opening documentation";
}

// =============================================================================
// Helper: Create domain health indicator label
// =============================================================================

QLabel* ZenithShell::createDomainIndicator(const QString& name, QWidget* parent)
{
    auto* label = new QLabel(QString("● %1").arg(name), parent);
    label->setObjectName(QString("%1Indicator").arg(name.toLower()));
    label->setStyleSheet("color: #888888;"); // Gray = unknown
    label->setToolTip(QString("%1 domain: unknown").arg(name));
    return label;
}

// =============================================================================
// main() — Application entry point
// =============================================================================

int main(int argc, char* argv[])
{
    // Enable high-DPI scaling
    QApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    QApplication::setAttribute(Qt::AA_UseHighDpiPixmaps);

    QApplication app(argc, argv);
    app.setApplicationName("Surface Zenith OS");
    app.setApplicationVersion("0.1.0-alpha");
    app.setOrganizationName("Microsoft Surface Zenith Team");
    app.setOrganizationDomain("zenith.surface.microsoft.com");

    // Set up logging
    QLoggingCategory::setFilterRules("zenith.*.debug=true");

    // Create and show main shell window
    ZenithShell shell;
    shell.show();

    // Connect to ZIB
    shell.connectToBus("ws://localhost:7890/zib");

    qCInfo(lcZenithShell) << "Surface Zenith Shell started";

    return app.exec();
}