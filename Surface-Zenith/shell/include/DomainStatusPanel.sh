// =============================================================================
// Surface Zenith OS — DomainStatusPanel Header
// =============================================================================

#pragma once

#include <QWidget>
#include <QFrame>
#include <QColor>
#include <QJsonObject>

class QLabel;
class QProgressBar;
class QTimer;

// =============================================================================
// DomainCard — Individual domain health card
// =============================================================================

class DomainCard : public QFrame {
    Q_OBJECT

public:
    explicit DomainCard(const QString& domainName, const QString& icon,
                        const QColor& accentColor, QWidget* parent = nullptr);

    void updateHealth(const QString& health, double cpu, double memory, int tasks);

    QString health()          const { return m_health; }
    double  cpuUsage()        const { return m_cpuUsage; }
    double  memoryUsage()     const { return m_memoryUsage; }
    int     activeTaskCount() const { return m_activeTaskCount; }

private:
    void setupUI();

    QString      m_domainName;
    QString      m_icon;
    QColor       m_accentColor;
    QString      m_health;
    double       m_cpuUsage;
    double       m_memoryUsage;
    int          m_activeTaskCount;

    QLabel*      m_iconLabel      = nullptr;
    QLabel*      m_nameLabel      = nullptr;
    QLabel*      m_healthDot      = nullptr;
    QLabel*      m_taskCountLabel = nullptr;
    QProgressBar* m_cpuBar        = nullptr;
    QProgressBar* m_memBar        = nullptr;
    QLabel*      m_cpuValueLabel  = nullptr;
    QLabel*      m_memValueLabel  = nullptr;
};

// =============================================================================
// DomainStatusPanel — Full domain status sidebar
// =============================================================================

class DomainStatusPanel : public QWidget {
    Q_OBJECT

public:
    explicit DomainStatusPanel(QWidget* parent = nullptr);

    void updateDomain(const QJsonObject& healthData);
    void setSchedulerQueueDepth(int depth);

public slots:
    void onUpdateTimer();

private:
    void setupUI();
    void setupConnections();
    void updateSummary();

    DomainCard* m_androidCard  = nullptr;
    DomainCard* m_windowsCard  = nullptr;
    DomainCard* m_aiCard       = nullptr;
    DomainCard* m_quantumCard  = nullptr;
    DomainCard* m_realtimeCard = nullptr;
    DomainCard* m_cloudCard    = nullptr;

    QLabel*     m_totalTasksLabel = nullptr;
    QLabel*     m_schedulerLabel  = nullptr;
    QTimer*     m_updateTimer;
};
