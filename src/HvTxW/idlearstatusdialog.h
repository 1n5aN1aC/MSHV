/* MSHV Idle AR Status Dialog
 * Temporary status window for the idle autoresponse scoring system.
 * Copyright 2024
 * May be used under the terms of the GNU General Public License (GPL)
 */
#ifndef IDLEARSTATUSDIALOG_H
#define IDLEARSTATUSDIALOG_H

#include <QDialog>
#include <QTableWidget>
#include <QLabel>
#include <QPushButton>
#include "hvmultianswermodw.h"

class IdleArStatusDialog : public QDialog
{
    Q_OBJECT
public:
    explicit IdleArStatusDialog(QWidget *parent = 0);
    virtual ~IdleArStatusDialog();

    void UpdateCandidates(const QList<IdleCandidate> &candidates,
                          unsigned int nowSec,
                          unsigned int windowSec);
    void NotifyFired(const QString &call);

private:
    QTableWidget *table;
    QLabel       *lbl_status;
    QPushButton  *btn_close;
};

#endif
