/* MSHV Pounce Settings
 * Copyright 2026
 * May be used under the terms of the GNU General Public License (GPL)
 */
#ifndef POUNCESETTINGS_H
#define POUNCESETTINGS_H

#include <QDialog>

class QCheckBox;

class HvPounceSettings : public QDialog
{
    Q_OBJECT
public:
    HvPounceSettings(bool dsty, QWidget *parent = 0);
    virtual ~HvPounceSettings();

    bool RespondDirectedEnabled() const;
    void SetRespondDirectedEnabled(bool enabled);

signals:
    void EmitRespondDirectedChanged(bool);

private:
    QCheckBox *cb_respond_directed;
};

#endif
