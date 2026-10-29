// =============================================================================
// Surface Zenith OS — Domain Status Panel (Qt/C++)
// File: shell/src/DomainStatusPanel.cpp
//
// Displays real-time health and metrics for all Zenith domains:
//   - Android Domain
//   - Windows Domain
//   - AI Domain
//   - Quantum Domain
//   - RealTime Domain
//   - Cloud Domain
// =============================================================================

#include "DomainStatusPanel.sh"
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QProgressBar>
#include <QGroupBox>
#include <QScrollArea>
#include <QTimer>
#include <QJsonObject>
#include <QPainter>
#include <QPropertyAnimation>
#include <QLoggingCategory>

Q_LOGGING_CATEGORY(lcDomainPanel, "zenith.shell.domainpanel")

// =============================================================================
// DomainCard — Individual domain status card
// =============================================================================

DomainCard::DomainCard(const QString& domainName, const QString& icon,
                       const QColor& accentColor, QWidget* parent)
    : QFrame(parent)
    , m_domainName(domainName)
    , m_icon(icon)
    , m_accentColor(accentColor)
    , m_health("Unknown")
    , m_cpuUsage(0.0)
    , m_memoryUsage(0.0)
    , m_activeTaskCount(0)
{
    setObjectName(QString("%1Card").arg(domainName.toLower()));
    setFrameShape(QFrame::StyledPanel);
    setFixedHeight(120);

    setupUI();
}

void DomainCard::setupUI()
{
    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(12, 10, 12, 10);
    layout->setSpacing(6);

    // Header row: icon + name + health indicator
    auto* headerLayout = new QHBoxLayout();
    headerLayout->setSpacing(8);

    m_iconLabel = new QLabel(m_icon, this);
    m_iconLabel->setFixedSize(28, 28);
    m_iconLabel->setAlignment(Qt::AlignCenter);
    m_iconLabel->setStyleSheet(QString(
        "QLabel { background: %1; border-radius: 14px; font-size: 14px; }"
    ).arg(m_accentColor.name()));

    m_nameLabel = new QLabel(m_domainName, this);
    m_nameLabel->setStyleSheet("QLabel { color: #FFFFFF; font-size: 13px; font-weight: bold; }");

    m_healthDot = new QLabel("●", this);
    m_healthDot->setStyleSheet("QLabel { color: #888888; font-size: 10px; }");
    m_healthDot->setAlignment(Qt::AlignRight | Qt::AlignVCenter);

    m_taskCountLabel = new QLabel("0 tasks", this);
    m_taskCountLabel->setStyleSheet("QLabel { color: #888888; font-size: 11px; }");
    m_taskCountLabel->setAlignment(Qt::AlignRight);

    headerLayout->addWidget(m_iconLabel);
    headerLayout->addWidget(m_nameLabel, 1);
    headerLayout->addWidget(m_taskCountLabel);
    headerLayout->addWidget(m_healthDot);

    // CPU progress bar
    auto* cpuLayout = new QHBoxLayout();
    auto* cpuLabel = new QLabel("CPU", this);
    cpuLabel->setFixedWidth(32);
    cpuLabel->setStyleSheet("QLabel { color: #888888; font-size: 10px; }");

    m_cpuBar = new QProgressBar(this);
    m_cpuBar->setRange(0, 100);
    m_cpuBar->setValue(0);
    m_cpuBar->setFixedHeight(6);
    m_cpuBar->setTextVisible(false);
    m_cpuBar->setStyleSheet(QString(
        "QProgressBar { background: #333333; border-radius: 3px; border: none; }"
        "QProgressBar::chunk { background: %1; border-radius: 3px; }"
    ).arg(m_accentColor.name()));

    m_cpuValueLabel = new QLabel("0%", this);
    m_cpuValueLabel->setFixedWidth(32);
    m_cpuValueLabel->setAlignment(Qt::AlignRight);
    m_cpuValueLabel->setStyleSheet("QLabel { color: #888888; font-size: 10px; }");

    cpuLayout->addWidget(cpuLabel);
    cpuLayout->addWidget(m_cpuBar, 1);
    cpuLayout->addWidget(m_cpuValueLabel);

    // Memory progress bar
    auto* memLayout = new QHBoxLayout();
    auto* memLabel = new QLabel("MEM", this);
    memLabel->setFixedWidth(32);
    memLabel->setStyleSheet("QLabel { color: #888888; font-size: 10px; }");

    m_memBar = new QProgressBar(this);
    m_memBar->setRange(0, 100);
    m_memBar->setValue(0);
    m_memBar->setFixedHeight(6);
    m_memBar->setTextVisible(false);
    m_memBar->setStyleSheet(QString(
        "QProgressBar { background: #333333; border-radius: 3px; border: none; }"
        "QProgressBar::chunk { background: %1; border-radius: 3px; }"
    ).arg(m_accentColor.lighter(120).name()));

    m_memValueLabel = new QLabel("0%", this);
    m_memValueLabel->setFixedWidth(32);
    m_memValueLabel->setAlignment(Qt::AlignRight);
    m_memValueLabel->setStyleSheet("QLabel { color: #888888; font-size: 10px; }");

    memLayout->addWidget(memLabel);
    memLayout->addWidget(m_memBar, 1);
    memLayout->addWidget(m_memValueLabel);

    layout->addLayout(headerLayout);
    layout->addLayout(cpuLayout);
    layout->addLayout(memLayout);

    setStyleSheet(
        "DomainCard { background: #2D2D2D; border-radius: 8px; border: 1px solid #3D3D3D; }"
        "DomainCard:hover { border: 1px solid #0078D4; }"
    );
}

void DomainCard::updateHealth(const QString& health, double cpu, double memory, int tasks)
{
    m_health       = health;
    m_cpuUsage     = cpu;
    m_memoryUsage  = memory;
    m_activeTaskCount = tasks;

    // Update health dot color
    QString dotColor;
    if (health == "Healthy") {
        dotColor = "#00C851";
    } else if (health.startsWith("Degraded")) {
        dotColor = "#FF8800";
    } else if (health.startsWith("Failed")) {
        dotColor = "#FF4444";
    } else if (health == "Initializing") {
        dotColor = "#0078D4";
    } else {
        dotColor = "#888888";
    }
    m_healthDot->setStyleSheet(QString("QLabel { color: %1; font-size: 10px; }").arg(dotColor));
    m_healthDot->setToolTip(health);

    // Animate CPU bar
    auto* cpuAnim = new QPropertyAnimation(m_cpuBar, "value", this);
    cpuAnim->setDuration(500);
    cpuAnim->setEndValue(static_cast<int>(cpu));
    cpuAnim->start(QAbstractAnimation::DeleteWhenStopped);
    m_cpuValueLabel->setText(QString("%1%").arg(static_cast<int>(cpu)));

    // Animate memory bar
    auto* memAnim = new QPropertyAnimation(m_memBar, "value", this);
    memAnim->setDuration(500);
    memAnim->setEndValue(static_cast<int>(memory));
    memAnim->start(QAbstractAnimation::DeleteWhenStopped);
    m_memValueLabel->setText(QString("%1%").arg(static_cast<int>(memory)));

    // Update task count
    m_taskCountLabel->setText(QString("%1 task%2").arg(tasks).arg(tasks == 1 ? "" : "s"));

    // Color CPU bar red if high usage
    if (cpu > 90.0) {
        m_cpuBar->setStyleSheet(
            "QProgressBar { background: #333333; border-radius: 3px; border: none; }"
            "QProgressBar::chunk { background: #FF4444; border-radius: 3px; }"
        );
    } else {
        m_cpuBar->setStyleSheet(QString(
            "QProgressBar { background: #333333; border-radius: 3px; border: none; }"
            "QProgressBar::chunk { background: %1; border-radius: 3px; }"
        ).arg(m_accentColor.name()));
    }
}

// =============================================================================
// DomainStatusPanel
// =============================================================================

DomainStatusPanel::DomainStatusPanel(QWidget* parent)
    : QWidget(parent)
    , m_updateTimer(new QTimer(this))
{
    setObjectName("DomainStatusPanel");
    setMinimumWidth(240);
    setMaximumWidth(320);

    setupUI();
    setupConnections();

    // Update every 2 seconds
    m_updateTimer->setInterval(2000);
    m_updateTimer->start();

    qCInfo(lcDomainPanel) << "DomainStatusPanel initialized";
}

void DomainStatusPanel::setupUI()
{
    auto* mainLayout = new QVBoxLayout(this);
    mainLayout->setContentsMargins(8, 8, 8, 8);
    mainLayout->setSpacing(8);

    // Header
    auto* headerLabel = new QLabel("Domain Status", this);
    headerLabel->setStyleSheet(
        "QLabel { color: #FFFFFF; font-size: 14px; font-weight: bold; "
        "padding: 4px 0; }"
    );
    mainLayout->addWidget(headerLabel);

    // Scroll area for domain cards
    auto* scrollArea = new QScrollArea(this);
    scrollArea->setWidgetResizable(true);
    scrollArea->setFrameShape(QFrame::NoFrame);
    scrollArea->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    scrollArea->setStyleSheet("QScrollArea { background: transparent; }");

    auto* scrollContent = new QWidget(scrollArea);
    auto* cardsLayout   = new QVBoxLayout(scrollContent);
    cardsLayout->setContentsMargins(0, 0, 0, 0);
    cardsLayout->setSpacing(8);

    // Create domain cards
    m_androidCard = new DomainCard("Android", "🤖", QColor(0x3D, 0xDC, 0x84), scrollContent);
    m_windowsCard = new DomainCard("Windows", "🪟", QColor(0x00, 0x78, 0xD4), scrollContent);
    m_aiCard      = new DomainCard("AI",      "🧠", QColor(0xFF, 0x6B, 0x35), scrollContent);
    m_quantumCard = new DomainCard("Quantum", "⚛",  QColor(0x9B, 0x59, 0xB6), scrollContent);
    m_realtimeCard= new DomainCard("RealTime","⚡",  QColor(0xFF, 0xC1, 0x07), scrollContent);
    m_cloudCard   = new DomainCard("Cloud",   "☁",  QColor(0x17, 0xA2, 0xB8), scrollContent);

    cardsLayout->addWidget(m_androidCard);
    cardsLayout->addWidget(m_windowsCard);
    cardsLayout->addWidget(m_aiCard);
    cardsLayout->addWidget(m_quantumCard);
    cardsLayout->addWidget(m_realtimeCard);
    cardsLayout->addWidget(m_cloudCard);
    cardsLayout->addStretch();

    scrollArea->setWidget(scrollContent);
    mainLayout->addWidget(scrollArea, 1);

    // Summary footer
    auto* footerLayout = new QHBoxLayout();
    m_totalTasksLabel = new QLabel("Total: 0 tasks", this);
    m_totalTasksLabel->setStyleSheet("QLabel { color: #888888; font-size: 11px; }");
    m_schedulerLabel  = new QLabel("Queue: 0", this);
    m_schedulerLabel->setStyleSheet("QLabel { color: #888888; font-size: 11px; }");
    m_schedulerLabel->setAlignment(Qt::AlignRight);

    footerLayout->addWidget(m_totalTasksLabel);
    footerLayout->addWidget(m_schedulerLabel);
    mainLayout->addLayout(footerLayout);

    setStyleSheet("DomainStatusPanel { background: #1E1E1E; }");
}

void DomainStatusPanel::setupConnections()
{
    connect(m_updateTimer, &QTimer::timeout,
            this, &DomainStatusPanel::onUpdateTimer);
}

void DomainStatusPanel::updateDomain(const QJsonObject& healthData)
{
    QString domain  = healthData["domain"].toString().toLower();
    QString health  = healthData["health"].toString();
    double  cpu     = healthData["cpu_usage_pct"].toDouble();
    double  memory  = healthData["memory_usage_pct"].toDouble();
    int     tasks   = healthData["active_task_count"].toInt();

    DomainCard* card = nullptr;
    if (domain == "android")  card = m_androidCard;
    else if (domain == "windows") card = m_windowsCard;
    else if (domain == "ai")      card = m_aiCard;
    else if (domain == "quantum") card = m_quantumCard;
    else if (domain == "realtime")card = m_realtimeCard;
    else if (domain == "cloud")   card = m_cloudCard;

    if (card) {
        card->updateHealth(health, cpu, memory, tasks);
        updateSummary();
    }
}

void DomainStatusPanel::updateSummary()
{
    int totalTasks = m_androidCard->activeTaskCount()
                   + m_windowsCard->activeTaskCount()
                   + m_aiCard->activeTaskCount()
                   + m_quantumCard->activeTaskCount()
                   + m_realtimeCard->activeTaskCount()
                   + m_cloudCard->activeTaskCount();

    m_totalTasksLabel->setText(QString("Total: %1 task%2")
                               .arg(totalTasks)
                               .arg(totalTasks == 1 ? "" : "s"));
}

void DomainStatusPanel::setSchedulerQueueDepth(int depth)
{
    m_schedulerLabel->setText(QString("Queue: %1").arg(depth));
}

void DomainStatusPanel::onUpdateTimer()
{
    // In production: query ZIB for real metrics
    // For now: simulate slight variations
    static double phase = 0.0;
    phase += 0.1;

    // Simulate realistic-looking metrics
    m_androidCard->updateHealth("Healthy",
        30.0 + 10.0 * qSin(phase),
        45.0 + 5.0  * qCos(phase), 3);
    m_windowsCard->updateHealth("Healthy",
        55.0 + 15.0 * qSin(phase + 1.0),
        60.0 + 8.0  * qCos(phase + 1.0), 7);
    m_aiCard->updateHealth("Healthy",
        70.0 + 20.0 * qSin(phase + 2.0),
        75.0 + 5.0  * qCos(phase + 2.0), 2);
    m_quantumCard->updateHealth("Initializing", 5.0, 10.0, 0);
    m_realtimeCard->updateHealth("Healthy", 15.0, 20.0, 1);
    m_cloudCard->updateHealth("Healthy", 25.0, 30.0, 4);

    updateSummary();
}
