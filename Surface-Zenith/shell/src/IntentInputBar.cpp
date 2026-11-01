// =============================================================================
// Surface Zenith OS — Intent Input Bar (Qt/C++)
// File: shell/src/IntentInputBar.cpp
//
// The Intent Input Bar is the primary user interaction point.
// Users type natural-language goals; the bar submits them as Intents
// to the Zenith Intent Scheduler via the ZIB.
//
// Features:
//   - Natural language input with AI-powered autocomplete
//   - Intent history (up/down arrow navigation)
//   - Real-time classification preview (shows predicted domain)
//   - Voice input integration
//   - Keyboard shortcut: Ctrl+Space to focus
// =============================================================================

#include "IntentInputBar.h"
#include "ZenithBusClient.h"

#include <QHBoxLayout>
#include <QVBoxLayout>
#include <QLineEdit>
#include <QPushButton>
#include <QLabel>
#include <QCompleter>
#include <QStringListModel>
#include <QTimer>
#include <QKeyEvent>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPropertyAnimation>
#include <QGraphicsDropShadowEffect>
#include <QLoggingCategory>
#include <QUuid>
#include <QDateTime>

Q_LOGGING_CATEGORY(lcIntentBar, "zenith.shell.intentbar")

// =============================================================================
// IntentInputBar implementation
// =============================================================================

IntentInputBar::IntentInputBar(QWidget* parent)
    : QWidget(parent)
    , m_busClient(nullptr)
    , m_classifyTimer(new QTimer(this))
    , m_historyIndex(-1)
    , m_isSubmitting(false)
{
    setupUI();
    setupCompleter();
    setupConnections();

    // Debounce classification: wait 300ms after typing stops
    m_classifyTimer->setSingleShot(true);
    m_classifyTimer->setInterval(300);

    qCInfo(lcIntentBar) << "IntentInputBar initialized";
}

void IntentInputBar::setupUI()
{
    setObjectName("IntentInputBar");
    setFixedHeight(56);

    auto* layout = new QHBoxLayout(this);
    layout->setContentsMargins(12, 8, 12, 8);
    layout->setSpacing(8);

    // Zenith logo / intent icon
    m_iconLabel = new QLabel("⚡", this);
    m_iconLabel->setObjectName("intentIcon");
    m_iconLabel->setFixedSize(32, 32);
    m_iconLabel->setAlignment(Qt::AlignCenter);
    m_iconLabel->setStyleSheet(
        "QLabel { background: #0078D4; border-radius: 16px; "
        "color: white; font-size: 16px; font-weight: bold; }"
    );

    // Main text input
    m_input = new QLineEdit(this);
    m_input->setObjectName("intentInput");
    m_input->setPlaceholderText("What would you like to do?");
    m_input->setStyleSheet(
        "QLineEdit { "
        "  background: transparent; "
        "  border: none; "
        "  color: #FFFFFF; "
        "  font-size: 15px; "
        "  font-family: 'Segoe UI Variable', 'Segoe UI', sans-serif; "
        "}"
        "QLineEdit:focus { border-bottom: 2px solid #0078D4; }"
    );

    // Domain prediction label
    m_domainLabel = new QLabel("", this);
    m_domainLabel->setObjectName("domainPrediction");
    m_domainLabel->setFixedWidth(100);
    m_domainLabel->setAlignment(Qt::AlignCenter);
    m_domainLabel->setStyleSheet(
        "QLabel { "
        "  background: #1E1E1E; "
        "  border-radius: 4px; "
        "  color: #888888; "
        "  font-size: 11px; "
        "  padding: 2px 6px; "
        "}"
    );

    // Voice input button
    m_voiceButton = new QPushButton("🎤", this);
    m_voiceButton->setObjectName("voiceButton");
    m_voiceButton->setFixedSize(32, 32);
    m_voiceButton->setToolTip("Voice input (Ctrl+Shift+V)");
    m_voiceButton->setStyleSheet(
        "QPushButton { "
        "  background: transparent; "
        "  border: none; "
        "  font-size: 16px; "
        "  border-radius: 16px; "
        "}"
        "QPushButton:hover { background: #333333; }"
        "QPushButton:pressed { background: #0078D4; }"
    );

    // Submit button
    m_submitButton = new QPushButton("→", this);
    m_submitButton->setObjectName("submitButton");
    m_submitButton->setFixedSize(32, 32);
    m_submitButton->setToolTip("Submit intent (Enter)");
    m_submitButton->setEnabled(false);
    m_submitButton->setStyleSheet(
        "QPushButton { "
        "  background: #0078D4; "
        "  border: none; "
        "  color: white; "
        "  font-size: 18px; "
        "  font-weight: bold; "
        "  border-radius: 16px; "
        "}"
        "QPushButton:hover { background: #106EBE; }"
        "QPushButton:disabled { background: #333333; color: #666666; }"
    );

    layout->addWidget(m_iconLabel);
    layout->addWidget(m_input, 1);
    layout->addWidget(m_domainLabel);
    layout->addWidget(m_voiceButton);
    layout->addWidget(m_submitButton);

    // Drop shadow effect
    auto* shadow = new QGraphicsDropShadowEffect(this);
    shadow->setBlurRadius(20);
    shadow->setColor(QColor(0, 0, 0, 80));
    shadow->setOffset(0, 4);
    setGraphicsEffect(shadow);

    setStyleSheet(
        "IntentInputBar { "
        "  background: #2D2D2D; "
        "  border-radius: 28px; "
        "  border: 1px solid #3D3D3D; "
        "}"
    );
}

void IntentInputBar::setupCompleter()
{
    // Common intent suggestions
    m_suggestions = QStringList{
        "Open Excel and analyze Q4 data",
        "Send a message to the team on Teams",
        "Compile and run the Rust project",
        "Summarize this document with Copilot",
        "Compare these two contracts",
        "Play music on Spotify",
        "Schedule a meeting for tomorrow",
        "Run quantum circuit simulation",
        "Translate this document to Portuguese",
        "Open Visual Studio and debug the project",
        "Sync files to OneDrive",
        "Take a photo with the rear camera",
        "Start a video call",
        "Generate a report from the sales data",
        "Search for recent news about AI",
    };

    m_completerModel = new QStringListModel(m_suggestions, this);
    m_completer = new QCompleter(m_completerModel, this);
    m_completer->setCaseSensitivity(Qt::CaseInsensitive);
    m_completer->setFilterMode(Qt::MatchContains);
    m_completer->setCompletionMode(QCompleter::PopupCompletion);
    m_input->setCompleter(m_completer);
}

void IntentInputBar::setupConnections()
{
    connect(m_input, &QLineEdit::textChanged,
            this, &IntentInputBar::onTextChanged);
    connect(m_input, &QLineEdit::returnPressed,
            this, &IntentInputBar::onSubmit);
    connect(m_submitButton, &QPushButton::clicked,
            this, &IntentInputBar::onSubmit);
    connect(m_voiceButton, &QPushButton::clicked,
            this, &IntentInputBar::onVoiceInput);
    connect(m_classifyTimer, &QTimer::timeout,
            this, &IntentInputBar::onClassifyIntent);
}

// =============================================================================
// Event handlers
// =============================================================================

void IntentInputBar::onTextChanged(const QString& text)
{
    bool hasText = !text.trimmed().isEmpty();
    m_submitButton->setEnabled(hasText);

    if (hasText) {
        // Start debounce timer for classification
        m_classifyTimer->start();
        m_domainLabel->setText("...");
        m_domainLabel->setStyleSheet(
            "QLabel { background: #1E1E1E; border-radius: 4px; "
            "color: #888888; font-size: 11px; padding: 2px 6px; }"
        );
    } else {
        m_classifyTimer->stop();
        m_domainLabel->setText("");
    }
}

void IntentInputBar::onClassifyIntent()
{
    QString text = m_input->text().trimmed();
    if (text.isEmpty()) return;

    // Classify locally using keyword matching
    // In production: call ZIB inference endpoint
    QString domain = classifyLocally(text);
    updateDomainLabel(domain);
}

QString IntentInputBar::classifyLocally(const QString& text) const
{
    QString lower = text.toLower();

    // Quick keyword classification (mirrors Rust IntentClassifier)
    if (lower.contains("excel") || lower.contains("word") ||
        lower.contains("document") || lower.contains("contract") ||
        lower.contains("report") || lower.contains("pdf")) {
        return "Windows";
    }
    if (lower.contains("whatsapp") || lower.contains("message") ||
        lower.contains("sms") || lower.contains("call") ||
        lower.contains("camera") || lower.contains("photo")) {
        return "Android";
    }
    if (lower.contains("copilot") || lower.contains("ai") ||
        lower.contains("summarize") || lower.contains("generate") ||
        lower.contains("translate") || lower.contains("analyze")) {
        return "AI";
    }
    if (lower.contains("quantum") || lower.contains("qubit") ||
        lower.contains("circuit") || lower.contains("qasm")) {
        return "Quantum";
    }
    if (lower.contains("compile") || lower.contains("build") ||
        lower.contains("debug") || lower.contains("code") ||
        lower.contains("visual studio") || lower.contains("git")) {
        return "Windows";
    }
    if (lower.contains("music") || lower.contains("spotify") ||
        lower.contains("play") || lower.contains("video")) {
        return "Android";
    }
    if (lower.contains("sync") || lower.contains("onedrive") ||
        lower.contains("cloud") || lower.contains("backup")) {
        return "Cloud";
    }

    return "AI"; // Default: let AI decide
}

void IntentInputBar::updateDomainLabel(const QString& domain)
{
    QString color;
    QString icon;

    if (domain == "Windows") {
        color = "#0078D4"; icon = "🪟";
    } else if (domain == "Android") {
        color = "#3DDC84"; icon = "🤖";
    } else if (domain == "AI") {
        color = "#FF6B35"; icon = "🧠";
    } else if (domain == "Quantum") {
        color = "#9B59B6"; icon = "⚛";
    } else if (domain == "Cloud") {
        color = "#17A2B8"; icon = "☁";
    } else {
        color = "#888888"; icon = "?";
    }

    m_domainLabel->setText(QString("%1 %2").arg(icon).arg(domain));
    m_domainLabel->setStyleSheet(QString(
        "QLabel { "
        "  background: %1; "
        "  border-radius: 4px; "
        "  color: white; "
        "  font-size: 11px; "
        "  padding: 2px 6px; "
        "  font-weight: bold; "
        "}"
    ).arg(color));
}

void IntentInputBar::onSubmit()
{
    QString text = m_input->text().trimmed();
    if (text.isEmpty() || m_isSubmitting) return;

    m_isSubmitting = true;

    // Add to history
    if (m_history.isEmpty() || m_history.first() != text) {
        m_history.prepend(text);
        if (m_history.size() > 100) {
            m_history.removeLast();
        }
    }
    m_historyIndex = -1;

    // Build intent payload
    QJsonObject intentPayload;
    intentPayload["intent_id"]    = QUuid::createUuid().toString(QUuid::WithoutBraces);
    intentPayload["session_id"]   = m_currentSessionId;
    intentPayload["goal"]         = text;
    intentPayload["priority"]     = 128;
    intentPayload["timestamp"]    = QDateTime::currentMSecsSinceEpoch();
    intentPayload["source"]       = "shell_input_bar";

    // Publish to ZIB
    if (m_busClient) {
        m_busClient->publish(
            "intent.submit",
            QJsonDocument(intentPayload).toJson(QJsonDocument::Compact)
        );
    }

    // Visual feedback: flash the icon
    m_iconLabel->setStyleSheet(
        "QLabel { background: #00C851; border-radius: 16px; "
        "color: white; font-size: 16px; font-weight: bold; }"
    );
    QTimer::singleShot(300, this, [this]() {
        m_iconLabel->setStyleSheet(
            "QLabel { background: #0078D4; border-radius: 16px; "
            "color: white; font-size: 16px; font-weight: bold; }"
        );
        m_isSubmitting = false;
    });

    // Clear input
    m_input->clear();
    m_domainLabel->setText("");

    emit intentSubmitted(text);
    qCInfo(lcIntentBar) << "Intent submitted:" << text;
}

void IntentInputBar::onVoiceInput()
{
    // Toggle voice recording
    m_voiceButton->setStyleSheet(
        "QPushButton { background: #FF4444; border: none; "
        "font-size: 16px; border-radius: 16px; }"
    );
    // In production: start audio capture → STT → fill m_input
    QTimer::singleShot(3000, this, [this]() {
        m_voiceButton->setStyleSheet(
            "QPushButton { background: transparent; border: none; "
            "font-size: 16px; border-radius: 16px; }"
        );
        // Simulate STT result
        m_input->setText("Analyze the Q4 sales report with Copilot");
    });
}

void IntentInputBar::keyPressEvent(QKeyEvent* event)
{
    if (event->key() == Qt::Key_Up) {
        // Navigate history up
        if (m_historyIndex < m_history.size() - 1) {
            ++m_historyIndex;
            m_input->setText(m_history[m_historyIndex]);
        }
        event->accept();
        return;
    }
    if (event->key() == Qt::Key_Down) {
        // Navigate history down
        if (m_historyIndex > 0) {
            --m_historyIndex;
            m_input->setText(m_history[m_historyIndex]);
        } else if (m_historyIndex == 0) {
            m_historyIndex = -1;
            m_input->clear();
        }
        event->accept();
        return;
    }
    if (event->key() == Qt::Key_Escape) {
        m_input->clear();
        m_historyIndex = -1;
        event->accept();
        return;
    }
    QWidget::keyPressEvent(event);
}

void IntentInputBar::setPlaceholderText(const QString& text)
{
    m_input->setPlaceholderText(text);
}

void IntentInputBar::setBusClient(ZenithBusClient* client)
{
    m_busClient = client;
}

void IntentInputBar::setSessionId(const QString& sessionId)
{
    m_currentSessionId = sessionId;
}

void IntentInputBar::addSuggestion(const QString& suggestion)
{
    if (!m_suggestions.contains(suggestion)) {
        m_suggestions.prepend(suggestion);
        m_completerModel->setStringList(m_suggestions);
    }
}