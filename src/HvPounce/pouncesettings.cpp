/* MSHV Pounce Settings
 * Copyright 2026
 * May be used under the terms of the GNU General Public License (GPL)
 */
#include "pouncesettings.h"

#include <QCheckBox>
#include <QButtonGroup>
#include <QDialogButtonBox>
#include <QFrame>
#include <QGroupBox>
#include <QLabel>
#include <QLineEdit>
#include <QRadioButton>
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

    cb_respond_cq_keyword = new QCheckBox(tr("Respond to CQs containing specific keywords"));
    cb_respond_cq_keyword->setToolTip(tr("When enabled, Pounce reacts to CQ lines containing any keyword from the list."));
    cb_respond_cq_keyword->setChecked(false);

    le_respond_cq_keywords = new QLineEdit();
    le_respond_cq_keywords->setPlaceholderText(tr("Example: POTA,SOTA,WWFF"));
    le_respond_cq_keywords->setToolTip(tr("Comma-separated CQ keywords to match."));
    le_respond_cq_keywords->setEnabled(false);

    cb_respond_cq_grid = new QCheckBox(tr("Respond to CQs containing specific grid squares"));
    cb_respond_cq_grid->setToolTip(tr("When enabled, Pounce reacts to CQ lines with matching grid squares."));
    cb_respond_cq_grid->setChecked(false);

    le_respond_cq_grids = new QLineEdit();
    le_respond_cq_grids->setPlaceholderText(tr("Example: CN84,EM12,JO22"));
    le_respond_cq_grids->setToolTip(tr("Comma-separated grid squares to match."));
    le_respond_cq_grids->setEnabled(false);

    QGroupBox *gb_response_mode = new QGroupBox(tr("Response mode"));
    rb_response_stay_freq = new QRadioButton(tr("stay on Freq"));
    rb_response_move_to_sender = new QRadioButton(tr("move to sender"));
    rb_response_optimal_freq = new QRadioButton(tr("use optimal freq"));
    rb_response_stay_freq->setChecked(true);
    rb_response_optimal_freq->setEnabled(false);

    bg_response_mode = new QButtonGroup(this);
    bg_response_mode->addButton(rb_response_stay_freq, 0);
    bg_response_mode->addButton(rb_response_move_to_sender, 1);
    bg_response_mode->addButton(rb_response_optimal_freq, 2);

    QVBoxLayout *v_response = new QVBoxLayout(gb_response_mode);
    v_response->setContentsMargins(8, 4, 8, 6);
    v_response->setSpacing(2);
    v_response->addWidget(rb_response_stay_freq);
    v_response->addWidget(rb_response_move_to_sender);
    v_response->addWidget(rb_response_optimal_freq);

    QVBoxLayout *v_box = new QVBoxLayout(box);
    v_box->setContentsMargins(8, 8, 8, 8);
    v_box->setSpacing(4);
    v_box->addWidget(cb_respond_directed);
    v_box->addWidget(cb_respond_cq_keyword);
    v_box->addWidget(le_respond_cq_keywords);
    v_box->addWidget(cb_respond_cq_grid);
    v_box->addWidget(le_respond_cq_grids);
    v_box->addWidget(gb_response_mode);

    QDialogButtonBox *bb = new QDialogButtonBox(QDialogButtonBox::Close);
    connect(bb, SIGNAL(rejected()), this, SLOT(reject()));
    connect(cb_respond_directed, SIGNAL(toggled(bool)), this, SIGNAL(EmitRespondDirectedChanged(bool)));
    connect(cb_respond_cq_keyword, SIGNAL(toggled(bool)), le_respond_cq_keywords, SLOT(setEnabled(bool)));
    connect(cb_respond_cq_keyword, SIGNAL(toggled(bool)), this, SIGNAL(EmitRespondCqKeywordChanged(bool)));
    connect(le_respond_cq_keywords, SIGNAL(textChanged(QString)), this, SIGNAL(EmitRespondCqKeywordsChanged(QString)));
    connect(cb_respond_cq_grid, SIGNAL(toggled(bool)), le_respond_cq_grids, SLOT(setEnabled(bool)));
    connect(cb_respond_cq_grid, SIGNAL(toggled(bool)), this, SIGNAL(EmitRespondCqGridChanged(bool)));
    connect(le_respond_cq_grids, SIGNAL(textChanged(QString)), this, SIGNAL(EmitRespondCqGridsChanged(QString)));
    connect(bg_response_mode, SIGNAL(buttonClicked(int)), this, SIGNAL(EmitResponseModeChanged(int)));

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

bool HvPounceSettings::RespondCqKeywordEnabled() const
{
    return cb_respond_cq_keyword->isChecked();
}

void HvPounceSettings::SetRespondCqKeywordEnabled(bool enabled)
{
    cb_respond_cq_keyword->setChecked(enabled);
}

QString HvPounceSettings::RespondCqKeywords() const
{
    return le_respond_cq_keywords->text().trimmed();
}

void HvPounceSettings::SetRespondCqKeywords(const QString &keywords)
{
    le_respond_cq_keywords->setText(keywords.trimmed());
}

bool HvPounceSettings::RespondCqGridEnabled() const
{
    return cb_respond_cq_grid->isChecked();
}

void HvPounceSettings::SetRespondCqGridEnabled(bool enabled)
{
    cb_respond_cq_grid->setChecked(enabled);
}

QString HvPounceSettings::RespondCqGrids() const
{
    return le_respond_cq_grids->text().trimmed();
}

void HvPounceSettings::SetRespondCqGrids(const QString &grids)
{
    le_respond_cq_grids->setText(grids.trimmed());
}

int HvPounceSettings::ResponseMode() const
{
    int mode = bg_response_mode->checkedId();
    if (mode < 0) return 0;
    return mode;
}

void HvPounceSettings::SetResponseMode(int mode)
{
    if (mode != 1) mode = 0;
    QAbstractButton *button = bg_response_mode->button(mode);
    if (button) button->setChecked(true);
}
