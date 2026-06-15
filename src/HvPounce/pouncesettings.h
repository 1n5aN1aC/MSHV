/* MSHV Pounce Settings
 * Copyright 2026
 * May be used under the terms of the GNU General Public License (GPL)
 */
#ifndef POUNCESETTINGS_H
#define POUNCESETTINGS_H

#include <QDialog>

class QCheckBox;
class QLineEdit;
class QButtonGroup;
class QRadioButton;

class HvPounceSettings : public QDialog
{
    Q_OBJECT
public:
    HvPounceSettings(bool dsty, QWidget *parent = 0);
    virtual ~HvPounceSettings();

    bool RespondDirectedEnabled() const;
    void SetRespondDirectedEnabled(bool enabled);
    bool RespondCqKeywordEnabled() const;
    void SetRespondCqKeywordEnabled(bool enabled);
    QString RespondCqKeywords() const;
    void SetRespondCqKeywords(const QString &keywords);
    bool RespondCqGridEnabled() const;
    void SetRespondCqGridEnabled(bool enabled);
    QString RespondCqGrids() const;
    void SetRespondCqGrids(const QString &grids);
    int ResponseMode() const;
    void SetResponseMode(int mode);

signals:
    void EmitRespondDirectedChanged(bool);
    void EmitRespondCqKeywordChanged(bool);
    void EmitRespondCqKeywordsChanged(QString);
    void EmitRespondCqGridChanged(bool);
    void EmitRespondCqGridsChanged(QString);
    void EmitResponseModeChanged(int);

private:
    QCheckBox *cb_respond_directed;
    QCheckBox *cb_respond_cq_keyword;
    QLineEdit *le_respond_cq_keywords;
    QCheckBox *cb_respond_cq_grid;
    QLineEdit *le_respond_cq_grids;
    QButtonGroup *bg_response_mode;
    QRadioButton *rb_response_stay_freq;
    QRadioButton *rb_response_move_to_sender;
    QRadioButton *rb_response_optimal_freq;
};

#endif
