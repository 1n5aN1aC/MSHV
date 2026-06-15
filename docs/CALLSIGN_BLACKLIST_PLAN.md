# Callsign Blacklist Implementation Plan

## Overview

Add a "Hide Messages From DX Call" feature to the existing Decode List Filter Dialog. This allows users to specify callsigns whose decoded messages will be hidden from the decode list (and optionally from auto-sequencing responses).

Additionally, add a right-click context menu item "BLACKLIST this callsign" on decoded messages that automatically adds the selected message's callsign to the blacklist and enables the filter.

## Architecture

The implementation follows the exact same pattern as the existing "Show Only Messages With DX Call" whitelist (`list_cufspec` / `show_cufspec_list`), but with inverted logic — matching calls are **hidden** instead of shown.

The right-click blacklist action extracts the DX callsign from the selected row using the existing `FindHisCall()` parser, then signals the filter dialog to append it to the blacklist text field and enable the checkbox.

## Files to Modify

### 1. `src/HvDecodeList/hvfilterdialog.h`

Add new member variables:

```cpp
QCheckBox *cb_hidecalls;
HvLeWithSpace *le_hidecalls;
```

Add new public methods for settings persistence:

```cpp
void SetSettings7(QString);
QString GetSettings7();
```

### 2. `src/HvDecodeList/hvfilterdialog.cpp`

**Constructor — Create UI controls (~20 lines):**

Add after the existing `GB_CTXT1` (Show Only Messages With DX Call) section in the constructor. In the layout, insert after `GB_HIDCCNT` (Hide Messages From Country) so hide-type filters are grouped together:

```cpp
int limit_bl = 3000;
QGroupBox *GB_HIDCALL = new QGroupBox(
    tr("Hide Messages From DX Call:    (Maximum 3000 Characters)"));
cb_hidecalls = new QCheckBox(tr("Enable"));
le_hidecalls = new HvLeWithSpace();
le_hidecalls->setMaxLength(limit_bl);
QHBoxLayout *hb_hidecalls = new QHBoxLayout();
hb_hidecalls->setContentsMargins(5, 5, 5, 5);
hb_hidecalls->setSpacing(5);
hb_hidecalls->addWidget(cb_hidecalls);
hb_hidecalls->addWidget(le_hidecalls);
GB_HIDCALL->setLayout(hb_hidecalls);
```

Insert `GB_HIDCALL` into layout `LV` after `GB_HIDCCNT` (line ~252):
```cpp
LV->addWidget(GB_HIDCCNT);
LV->addWidget(GB_HIDCALL);  // new — Hide Messages From DX Call
LV->addLayout(hbcq);
```

**`ApplyChFilter()` — Add syntax correction:**

```cpp
le_hidecalls->setText(CorrectSyntax(le_hidecalls->text(), true));
```

**`SetDefaultFilter()` — Add default state:**

```cpp
cb_hidecalls->setChecked(false);
le_hidecalls->setText("");
```

**`SetFilter()` — Emit new list parameter:**

Add a new `QStringList lc6` declaration alongside lc0–lc5:

```cpp
QStringList lc6;
```

Add inside the `if (cb_gonoff->isChecked())` block after the existing `GetLineParms` calls:

```cpp
if (cb_hidecalls->isChecked()) lc6 = GetLineParms(le_hidecalls);
```

Update the `EmitSetFilter` signal emission to include `lc6`:

```cpp
emit EmitSetFilter(lc,fh,lc0,lc1,lc2,lc3,lc4,lc5,lc6);
```

Update the `RefreshPbSetOnOff` check to include `!lc6.isEmpty()`:

```cpp
if (fh[8] || !lc.isEmpty() || !lc0.isEmpty() || !lc1.isEmpty()|| !lc2.isEmpty()|| !lc3.isEmpty() ||
    !lc4.isEmpty() || !lc5.isEmpty() || !lc6.isEmpty()) f = true;
```

**Settings persistence — Add `SetSettings7`/`GetSettings7`:**

```cpp
void HvFilterDialog::SetSettings7(QString s)
{
    SetSettings_p(s, cb_hidecalls, le_hidecalls, true);
}
QString HvFilterDialog::GetSettings7()
{
    return GetSettings_p(cb_hidecalls, le_hidecalls, true);
}
```

### 3. `src/HvDecodeList/hvfilterdialog.h` — Signal & Slot Updates

Update the `EmitSetFilter` signal signature to add one more `QStringList` parameter:

```cpp
// Before:
void EmitSetFilter(QStringList, bool*, QStringList, QStringList,
                   QStringList, QStringList, QStringList, QStringList);

// After:
void EmitSetFilter(QStringList, bool*, QStringList, QStringList,
                   QStringList, QStringList, QStringList, QStringList,
                   QStringList);
```

Add new public slot to receive callsigns from the decode list right-click menu:

```cpp
public slots:
    void SetTextMark(bool*,QString);
    void AddBlacklistCall(QString);
```

### 4. `src/HvDecodeList/decodelist.h`

Add new member variables:

```cpp
bool hide_call_list;
QStringList list_hidecalls;
```

Add new private methods:

```cpp
bool HideByCall(QString);
```

Add new private slot for right-click menu:

```cpp
void ac_blacklist_call();
```

Add new QAction pointer for right-click menu:

```cpp
QAction *m_blacklist_call;
```

Add new signal to send callsign to filter dialog:

```cpp
void EmitBlacklistCall(QString);
```

Update `SetFilter` slot signature to accept one more `QStringList`:

```cpp
void SetFilter(QStringList,bool*,QStringList,QStringList,QStringList,QStringList,QStringList,QStringList,QStringList);
```

### 5. `src/HvDecodeList/decodelist.cpp`

**Constructor — Initialize new members:**

```cpp
hide_call_list = false;
list_hidecalls.clear();
```

**Constructor — Add right-click menu action (~line 175, after `m_respond_now`):**

```cpp
m_blacklist_call = new QAction(tr("BLACKLIST this callsign"), this);
m_spot->addAction(m_blacklist_call);
connect(m_blacklist_call, SIGNAL(triggered()), this, SLOT(ac_blacklist_call()));
```

**New `ac_blacklist_call()` slot (~15 lines):**

Extracts callsign from selected row using `FindHisCall()` on the message column, then emits `EmitBlacklistCall`:

```cpp
void DecodeList::ac_blacklist_call()
{
    QModelIndex index = selectionModel()->currentIndex();
    int row = index.row();
    if (row < 0) return;
    QString msg = model.item(row, msg_column)->text();
    QString call = FindHisCall(msg);
    if (!call.isEmpty())
        emit EmitBlacklistCall(call);
}
```

**`SetFilter()` — Parse new parameter:**

Update signature to accept the new `QStringList lc6` parameter:

```cpp
void DecodeList::SetFilter(QStringList lc,bool *fh,QStringList lc0,QStringList lc1,QStringList lc2,
                           QStringList lc3,QStringList lc4,QStringList lc5,QStringList lc6)
```

Add after the existing `SetFilterParms` calls:

```cpp
SetFilterParms(lc6, list_hidecalls, hide_call_list);
```

Add `hide_call_list` to the `RefreshFiltHeadColor` call. This requires updating the function signature to accept one more bool (10 total):

```cpp
RefreshFiltHeadColor(show_filter_list,hide_filter_list,show_customf_list,show_cufspec_list,
                     show_cufend_list,show_cnyf_list,show_pfxf_list,hide_cnyf_list,f_hide_c[8],hide_call_list);
```

**Update `RefreshFiltHeadColor()` signature:**

```cpp
// Before (9 bools):
void DecodeList::RefreshFiltHeadColor(bool f1,bool f2,bool f3,bool f4,bool f5,bool f6,bool f7,bool f8,bool f9)

// After (10 bools):
void DecodeList::RefreshFiltHeadColor(bool f1,bool f2,bool f3,bool f4,bool f5,bool f6,bool f7,bool f8,bool f9,bool f10)
```

Update the condition checks in RefreshFiltHeadColor to include `f10`:
```cpp
if ((s_mode==11 || s_mode==13 || s_mode==18) && (f1 || f2 || f3 || f4 || f5 || f6 || f7 || f8 || f9 || f10))
```
And:
```cpp
if (f1 && !f2 && !f3 && !f4 && !f5 && !f6 && !f7 && !f8 && !f9 && !f10) is_only_cqrr73_active = true;
```

Also update the declaration in `decodelist.h`:
```cpp
void RefreshFiltHeadColor(bool,bool,bool,bool,bool,bool,bool,bool,bool,bool);
```

**New `HideByCall()` function (~10 lines):**

```cpp
bool DecodeList::HideByCall(QString call)
{
    if (call.isEmpty()) return true;  // show if no call parsed
    for (int i = 0; i < list_hidecalls.count(); ++i)
    {
        if (call == list_hidecalls.at(i))
            return false;  // hide this call
    }
    return true;  // show — not in blacklist
}
```

**`InsertItem_hv()` — Add hide check:**

In the filtering chain inside `InsertItem_hv()`, add `hide_call_list` to the condition that extracts the call, and add the hide check:

```cpp
// Add hide_call_list to the call-extraction condition (around line 1523):
if (hide_filter_list || show_customf_list || show_cufspec_list || show_cnyf_list ||
    show_pfxf_list || hide_cnyf_list || f_b4qso || hide_call_list)
    call = FindHisCall(list.at(4));

// Add in the hide-check chain (after the existing HideB4Qso check, around line 1563):
if (hide_call_list && f_sho0) f_sho0 = HideByCall(call);
```

### 6. `src/HvDecodeList/hvfilterdialog.cpp` — New `AddBlacklistCall` Slot

Receives a callsign from the decode list right-click menu and appends it to the blacklist:

```cpp
void HvFilterDialog::AddBlacklistCall(QString call)
{
    if (call.isEmpty()) return;
    QString txt = le_hidecalls->text().trimmed();
    // Check if callsign already exists in the list
    QStringList existing = txt.split(",", QString::SkipEmptyParts);
    for (int i = 0; i < existing.count(); ++i)
    {
        if (existing.at(i).trimmed() == call) return;  // already blacklisted
    }
    if (!txt.isEmpty()) txt += ",";
    txt += call;
    le_hidecalls->setText(txt);
    cb_hidecalls->setChecked(true);
    // If global filter is on, apply immediately
    if (cb_gonoff->isChecked()) SetFilter();
}
```

### 7. `src/main_ms.h` — No changes needed

`FilterDialog` is already a member.

### 8. `src/main_ms.cpp`

**Signal/slot connection — Update `EmitSetFilter` signature (~line 315-316):**

Update the `connect()` call to match the new signal signature with one more `QStringList`:

```cpp
connect(FilterDialog, SIGNAL(EmitSetFilter(QStringList,bool*,QStringList,QStringList,QStringList,QStringList,QStringList,QStringList,QStringList)),
        TDecodeList1, SLOT(SetFilter(QStringList,bool*,QStringList,QStringList,QStringList,QStringList,QStringList,QStringList,QStringList)));
```

**New signal connections — Blacklist right-click from both decode lists to FilterDialog:**

Add after the existing `EmitRespondNow` connections:

```cpp
connect(TDecodeList1, SIGNAL(EmitBlacklistCall(QString)), FilterDialog, SLOT(AddBlacklistCall(QString)));
connect(TDecodeList2, SIGNAL(EmitBlacklistCall(QString)), FilterDialog, SLOT(AddBlacklistCall(QString)));
```

**Settings array — Increment `c_st_id` from 111 to 112, add `"def_filter_list7"` at index 111:**

```cpp
const int c_st_id = 112;
// ... add to end of st_id array:
"def_dftol_all_mode","def_filter_list7"
```

**Settings load (~line 4420):**

```cpp
if (!st_res[111].isEmpty()) FilterDialog->SetSettings7(st_res[111]);
```

**Settings save (~line 4679):**

```cpp
out << "def_filter_list7=" << FilterDialog->GetSettings7() << "\n";
```

### 9. `bin/settings/ms_settings`

Add default line:

```
def_filter_list7=0
```

## Behavior Summary

- When **"Hide Messages From DX Call"** is enabled and the global "USE FILTERS" is on:
  - Decoded messages where the DX call matches any entry in the comma-separated list are hidden from the decode list
  - Messages addressed **to** the user (their callsign) within ±10 kHz are still shown (existing filter bypass logic)
  - The `cb_filtered_answer` checkbox controls whether auto-sequencing also respects this blacklist
- **Right-click "BLACKLIST this callsign"** on any decoded message:
  - Extracts the DX callsign from the message using `FindHisCall()` (same parser used by all existing filters)
  - Appends callsign to the "Hide Messages From DX Call" text field (comma-separated)
  - Automatically enables the "Enable" checkbox for the blacklist
  - If global "USE FILTERS" is already on, the filter is applied immediately
  - If global "USE FILTERS" is off, the callsign is added but filtering won't take effect until the user enables it
  - Duplicate callsigns are not added (checked before appending)
  - Works from both decode lists (TDecodeList1 and TDecodeList2), but filtering only applies to TDecodeList1 (same as all existing filters)
- Callsign matching is **exact** (same as existing `ShowCSDecode`)
- Users enter callsigns as comma-separated values: `K1ABC,W2XYZ,JA1ZZZ`
- Maximum 3000 characters (same as existing DX Call whitelist)
- Settings are persisted to `ms_settings` and restored on startup

## Estimated Scope

| File | Lines Added | Lines Modified |
|------|------------|----------------|
| `hvfilterdialog.h` | ~7 | ~2 (signal signature) |
| `hvfilterdialog.cpp` | ~55 | ~10 (layout, SetFilter, defaults) |
| `decodelist.h` | ~6 | ~3 (SetFilter sig, RefreshFiltHeadColor sig) |
| `decodelist.cpp` | ~30 | ~12 (SetFilter, InsertItem_hv, init, menu, RefreshFiltHeadColor) |
| `main_ms.cpp` | ~5 | ~3 (connect sigs, settings, c_st_id) |
| `ms_settings` | ~1 | 0 |
| **Total** | **~104** | **~30** |

## Risk Assessment

- **Low risk**: Follows the exact same pattern used by 6+ existing filter types
- **No breaking changes**: The new parameter is additive; old settings files without `def_filter_list7` simply result in an empty/disabled blacklist
- **Filter bypass preserved**: The existing `forme` and `freply` logic in `InsertItem_hv()` ensures messages directed at the user are never hidden
- **Right-click menu**: Follows the same pattern as the existing "Respond to this message NOW" action — same menu, same row-extraction logic, emit signal to parent
