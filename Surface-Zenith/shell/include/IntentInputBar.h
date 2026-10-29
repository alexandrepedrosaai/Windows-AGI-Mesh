// =============================================================================
// Surface Zenith OS — IntentInputBar Header
// =============================================================================

#pragma once

#include <QWidget>
#include <QStringList>

class QLineEdit;
class QPushButton;
class QLabel;
class QTimer;
class QCompleter;
class QStringListModel;
class ZenithBusClient;

class IntentInputBar : public QWidget {
    Q_OBJECT

public:
    explicit IntentInputBar(QWidget* parent = nullptr);

    void setPlaceholderText(const QString& text);
    void setBusClient(ZenithBusClient* client);
    void setSessionId(const QString& sessionId);
    void addSuggestion(const QString& suggestion);

signals:
    void intentSubmitted(const QString& goal);
    void domainPredicted(const QString& domain);

protected:
    void keyPressEvent(QKeyEvent* event) override;

private slots:
    void onTextChanged(const QString& text);
    void onClassifyIntent();
    void onSubmit();
    void onVoiceInput();

private:
    void setupUI();
    void setupCompleter();
    void setupConnections();
    QString classifyLocally(const QString& text) const;
    void updateDomainLabel(const QString& domain);

    // UI components
    QLabel*           m_iconLabel      = nullptr;
    QLineEdit*        m_input          = nullptr;
    QLabel*           m_domainLabel    = nullptr;
    QPushButton*      m_voiceButton    = nullptr;
    QPushButton*      m_submitButton   = nullptr;

    // Autocomplete
    QCompleter*       m_completer      = nullptr;
    QStringListModel* m_completerModel = nullptr;
    QStringList       m_suggestions;

    // State
    ZenithBusClient*  m_busClient      = nullptr;
    QTimer*           m_classifyTimer;
    QStringList       m_history;
    int               m_historyIndex;
    bool              m_isSubmitting;
    QString           m_currentSessionId;
};