/* MSHV Pounce Settings
 * Copyright 2026
 * May be used under the terms of the GNU General Public License (GPL)
 */
#include "pouncesettings.h"

#include <QCheckBox>
#include <QDialogButtonBox>
#include <QFrame>
#include <QLabel>
#include <QVBoxLayout>

HvPounceSettings::HvPounceSettings(bool dsty, QWidget *parent)
    : QDialog(parent)
{
    setWindowTitle(tr("Pounce Settings"));
    setModal(true);
    setMinimumWidth(430);

    QLabel *l_intro = new QLabel(tr("Pounce listens for new decodes and can react immediately when matching rules are found."));
    l_intro->setWordWrap(true);

    QFrame *box = new QFrame();
    box->setFrameShape(QFrame::StyledPanel);
    box->setFrameShadow(QFrame::Raised);

    cb_respond_directed = new QCheckBox(tr("Respond to calls directed to my callsign"));
    cb_respond_directed->setToolTip(tr("When enabled, Pounce adds directed calls to the MASTD queue and starts AUTO."));
    cb_respond_directed->setChecked(true);

    QVBoxLayout *v_box = new QVBoxLayout(box);
    v_box->setContentsMargins(8, 8, 8, 8);
    v_box->setSpacing(4);
    v_box->addWidget(cb_respond_directed);

    QDialogButtonBox *bb = new QDialogButtonBox(QDialogButtonBox::Close);
    connect(bb, SIGNAL(rejected()), this, SLOT(reject()));
    connect(cb_respond_directed, SIGNAL(toggled(bool)), this, SIGNAL(EmitRespondDirectedChanged(bool)));

    QVBoxLayout *v_main = new QVBoxLayout(this);
    v_main->setContentsMargins(8, 8, 8, 8);
    v_main->setSpacing(6);
    v_main->addWidget(l_intro);
    v_main->addWidget(box);
    v_main->addWidget(bb);

    if (dsty)
    {
        l_intro->setStyleSheet("QLabel{color:rgb(210,210,210);}");
    }
}

HvPounceSettings::~HvPounceSettings()
{
}

bool HvPounceSettings::RespondDirectedEnabled() const
{
    return cb_respond_directed->isChecked();
}

void HvPounceSettings::SetRespondDirectedEnabled(bool enabled)
{
    cb_respond_directed->setChecked(enabled);
}
