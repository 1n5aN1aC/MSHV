/* MSHV Idle AR Status Dialog
 * Temporary status window for the idle autoresponse scoring system.
 * Copyright 2024
 * May be used under the terms of the GNU General Public License (GPL)
 */
#include "idlearstatusdialog.h"
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QDateTime>

static const char * const CAT_NAMES[IDLE_CAT_COUNT] = {
    "CQ Tag", "CQ", "RR73", "73", "Other"
};

IdleArStatusDialog::IdleArStatusDialog(QWidget *parent)
    : QDialog(parent, Qt::Window | Qt::WindowStaysOnTopHint)
{
    setWindowTitle("Idle AR Status");
    setMinimumWidth(640);
    setMinimumHeight(200);

    table = new QTableWidget(this);
    table->setColumnCount(7);
    QStringList headers;
    headers << "Call" << "Cat" << "Freq" << "SNR" << "Score" << "Last Heard" << "Last Tried";
    table->setHorizontalHeaderLabels(headers);
    table->horizontalHeader()->setSectionResizeMode(QHeaderView::Interactive);
    table->horizontalHeader()->setStretchLastSection(true);
    table->horizontalHeader()->setMinimumSectionSize(50);
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->setSelectionBehavior(QAbstractItemView::SelectRows);
    table->setSelectionMode(QAbstractItemView::SingleSelection);
    table->setSortingEnabled(false);
    table->verticalHeader()->setVisible(false);

    lbl_status = new QLabel(tr("No candidates"), this);
    btn_close   = new QPushButton(tr("Close"), this);
    connect(btn_close, SIGNAL(clicked()), this, SLOT(hide()));

    QHBoxLayout *hlay = new QHBoxLayout;
    hlay->addWidget(lbl_status);
    hlay->addStretch();
    hlay->addWidget(btn_close);

    QVBoxLayout *vlay = new QVBoxLayout(this);
    vlay->addWidget(table);
    vlay->addLayout(hlay);
    setLayout(vlay);
}

IdleArStatusDialog::~IdleArStatusDialog() {}

void IdleArStatusDialog::UpdateCandidates(const QList<IdleCandidate> &candidates,
                                           unsigned int nowSec,
                                           unsigned int windowSec)
{
    if (windowSec == 0) windowSec = 1;

    // Build scored list so we can sort descending by score
    struct ScoredEntry {
        const IdleCandidate *cand;
        int score;
    };
    QList<ScoredEntry> entries;
    for (int i = 0; i < candidates.count(); ++i)
    {
        ScoredEntry e;
        e.cand  = &candidates.at(i);
        e.score = MultiAnswerModW::ScoreIdleCandidate(candidates.at(i), nowSec, windowSec);
        entries.append(e);
    }
    // Sort descending by score
    for (int i = 0; i < entries.count() - 1; ++i)
        for (int j = i + 1; j < entries.count(); ++j)
            if (entries[j].score > entries[i].score)
                entries.swapItemsAt(i, j);

    table->setRowCount(entries.count());

    for (int i = 0; i < entries.count(); ++i)
    {
        const IdleCandidate &c = *entries.at(i).cand;
        int score = entries.at(i).score;

        // Last Heard: show age in seconds if recent, else UTC time
        QString lastHeard;
        if (nowSec >= c.rx_time)
        {
            unsigned int age = nowSec - c.rx_time;
            if (age < 60)
                lastHeard = QString("%1s ago").arg(age);
            else
                lastHeard = QDateTime::fromTime_t(c.rx_time).toUTC().toString("HH:mm:ss") + " UTC";
        }

        // Last Tried: "Never" or time ago / UTC
        QString lastTried;
        if (c.last_tried == 0)
        {
            lastTried = tr("Never");
        }
        else if (nowSec >= c.last_tried)
        {
            unsigned int triedAge = nowSec - c.last_tried;
            if (triedAge < 60)
                lastTried = QString("%1s ago").arg(triedAge);
            else
                lastTried = QDateTime::fromTime_t(c.last_tried).toUTC().toString("HH:mm:ss") + " UTC";
        }

        auto setCell = [&](int col, const QString &txt, int align) {
            QTableWidgetItem *item = new QTableWidgetItem(txt);
            item->setTextAlignment(align);
            table->setItem(i, col, item);
        };
        int alignL = Qt::AlignLeft  | Qt::AlignVCenter;
        int alignR = Qt::AlignRight | Qt::AlignVCenter;

        setCell(0, c.call, alignL);
        setCell(1, c.cat < IDLE_CAT_COUNT ? QString(CAT_NAMES[c.cat]) : QString("?"), alignL);
        setCell(2, c.freq, alignL);
        setCell(3, c.snr, alignR);
        setCell(4, QString::number(score), alignR);
        setCell(5, lastHeard, alignL);
        setCell(6, lastTried, alignL);
    }

    table->resizeColumnsToContents();
    lbl_status->setText(tr("%1 candidate(s)").arg(candidates.count()));
}

void IdleArStatusDialog::NotifyFired(const QString &call)
{
    lbl_status->setText(tr("Fired: %1").arg(call));
}
