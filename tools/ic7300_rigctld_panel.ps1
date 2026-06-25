#Requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# -- Script-scope state -------------------------------------------------------
$script:tcpClient   = $null
$script:tcpStream   = $null
$script:fontMeter   = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$script:regPath     = "HKCU:\Software\IC7300RigctldPanel"
$script:brushGreen  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::LimeGreen)
$script:brushYellow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Yellow)
$script:brushOrange = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::OrangeRed)

# Shared between UI thread and background poll runspace.
# [hashtable]::Synchronized() makes individual key reads/writes atomic.
$script:shared = [hashtable]::Synchronized(@{
    pwrFrac          = -1.0   # 0.0-1.0, or -1.0 = no reading
    swrVal           = -1.0   # actual SWR ratio (>= 1.0), or -1.0 = no reading
    alcFrac          = -1.0   # 0.0-1.0, or -1.0 = no reading
    pttState         = -1     # -1=unknown, 0=RX, 1=TX
    stop             = $false
    swrProtect       = $false
    consecutiveFails = 0
    tcpLock          = [System.Threading.SemaphoreSlim]::new(1, 1)
})
$script:bgPs     = $null
$script:bgHandle = $null

# -- rigctld helpers (UI thread) ----------------------------------------------
# tcpLock must be held by the caller before invoking these helpers.

function Send-RigctlSetCmd {
    param([string]$CmdLine)
    if (-not $script:tcpClient -or -not $script:tcpClient.Connected) { return $false }
    try {
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($CmdLine + "`n")
        $script:tcpStream.Write($bytes, 0, $bytes.Length)
        $response = ''
        $origTimeout = $script:tcpStream.ReadTimeout
        $script:tcpStream.ReadTimeout = 200
        try {
            while ($true) {
                $c = $script:tcpStream.ReadByte()
                if ($c -eq -1 -or $c -eq 10) { break }
                if ($c -ne 13) { $response += [char]$c }
            }
        } catch [System.Net.Sockets.SocketException] { }
        catch [System.IO.IOException] { }
        $script:tcpStream.ReadTimeout = $origTimeout
        $response = $response.Trim()
        if ($response -match '^RPRT\s+(-?\d+)') {
            return ([int]$Matches[1] -eq 0)
        }
        return $true
    } catch { return $false }
}

# Set RF power. $Watts is 0-100 (assumes 100 W max).
function Set-PowerLevel {
    param([int]$Watts)
    if (-not $script:tcpClient -or -not $script:tcpClient.Connected) { return }
    if (-not $script:shared.tcpLock.Wait(400)) { return }
    try {
        $frac    = [Math]::Max(0.0, [Math]::Min(1.0, $Watts / 100.0))
        $fracStr = $frac.ToString('F6', [System.Globalization.CultureInfo]::InvariantCulture)
        Send-RigctlSetCmd "L RFPOWER $fracStr" | Out-Null
    } catch { } finally { [void]$script:shared.tcpLock.Release() }
}

# Toggle PTT. $State: 0=RX, 1=TX.
function Set-Ptt {
    param([int]$State)
    if (-not $script:tcpClient -or -not $script:tcpClient.Connected) { return }
    if (-not $script:shared.tcpLock.Wait(400)) { return }
    try { Send-RigctlSetCmd "T $State" | Out-Null }
    catch { } finally { [void]$script:shared.tcpLock.Release() }
}

# Trigger the ATU tune cycle.
function Start-Tune {
    if (-not $script:tcpClient -or -not $script:tcpClient.Connected) { return }
    if (-not $script:shared.tcpLock.Wait(400)) { return }
    try { Send-RigctlSetCmd 'G TUNE' | Out-Null }
    catch { } finally { [void]$script:shared.tcpLock.Release() }
}

# -- Background poll scriptblock ----------------------------------------------
# Runs in a separate PowerShell runspace.
# Variables injected via SessionStateProxy: $tcpStream, $shared.
# Only updates $shared -- never touches WinForms controls directly.
$bgScript = {
    # Read response until a short timeout, collecting all lines.
    # Returns the first non-RPRT data line for get commands, or the full
    # response for set commands. The short timeout (100ms) avoids blocking.
    function Read-Response {
        $allLines = [System.Collections.Generic.List[string]]::new()
        $line = ''
        try {
            while ($true) {
                $c = $tcpStream.ReadByte()
                if ($c -eq -1) { break }
                if ($c -eq 10) {                         # \n = end of line
                    if ($line.Trim().Length -gt 0) {
                        $allLines.Add($line.Trim())
                        if ($line -match '^RPRT\b') { break }  # complete response; don't drain to timeout
                    }
                    $line = ''
                } elseif ($c -ne 13) { $line += [char]$c }    # skip \r
            }
        } catch [System.ObjectDisposedException] { }
        catch [System.Net.Sockets.SocketException] { }
        catch [System.IO.IOException] { }
        if ($line.Trim().Length -gt 0) { $allLines.Add($line.Trim()) }
        $dataLines = $allLines | Where-Object { $_ -notmatch '^RPRT\s+' }
        if ($dataLines.Count -gt 0) { return $dataLines -join ' ' }
        if ($allLines.Count -gt 0) { return $allLines[0] }
        return ''
    }

    # Send a get_level query (command 'l') and return the float value line.
    # Caller must hold $shared.tcpLock.
    function RigSendGet {
        param([string]$CmdLine)
        try {
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($CmdLine + "`n")
            $tcpStream.Write($bytes, 0, $bytes.Length)
            return Read-Response
        } catch { return $null }
    }

    # Send a set/action command and check for RPRT 0.
    # Caller must hold $shared.tcpLock.
    function RigSendSet {
        param([string]$CmdLine)
        try {
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($CmdLine + "`n")
            $tcpStream.Write($bytes, 0, $bytes.Length)
            $response = Read-Response
            if ($response -match '^RPRT\s+(-?\d+)') {
                $code = [int]$Matches[1]
                return ($code -eq 0)
            }
            return $true
        } catch { return $false }
    }

    # Query a float level from rigctld using 'l' (get_level).
    # Returns the value, or -1.0 on error.
    function Get-RigLevel {
        param([string]$Level)
        $line = RigSendGet "l $Level"
        if ($null -eq $line -or $line -eq '') { return -1.0 }
        $val = 0.0
        if ([double]::TryParse($line,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$val)) { return $val }
        return -1.0
    }

    # Query PTT state via 't' (get_ptt). Returns 0=RX, 1=TX, or -1 on error.
    function Get-RigPtt {
        $line = RigSendGet "t"
        if ($null -eq $line -or $line -eq '') { return -1 }
        $val = 0
        if ([int]::TryParse($line.Trim(), [ref]$val)) { return $val }
        return -1
    }

    $pttPollMs = 50
    while (-not $shared.stop) {
        $t = -1
        if (-not $shared.tcpLock.Wait(1000)) { continue }
        try {
            $t = Get-RigPtt
            if ($t -ge 0) { $shared.pttState = $t }   # update immediately, before meter queries
            if ($t -eq 1) {
                [System.Threading.Thread]::Sleep(10)
                $p = Get-RigLevel 'RFPOWER_METER'
                [System.Threading.Thread]::Sleep(10)
                $raw = Get-RigLevel 'SWR'
                [System.Threading.Thread]::Sleep(10)
                $a = Get-RigLevel 'ALC'
                $s = if ($raw -ge 0.0) { if ($raw -lt 1.0) { 1.0 } else { $raw } } else { -1.0 }
                if ($s -ge 1.0 -and $shared.swrProtect -and $s -gt 2.0) {
                    RigSendSet "T 0" | Out-Null
                }
                if ($p -ge 0.0) { $shared.pwrFrac = $p }
                if ($s -ge 1.0) { $shared.swrVal  = $s }
                if ($a -ge 0.0) { $shared.alcFrac = $a }
            } elseif ($t -eq 0) {
                # RX: clear meters; future receive-only queries go here
                $shared.pwrFrac = -1.0
                $shared.swrVal  = -1.0
                $shared.alcFrac = -1.0
            }
        } catch { } finally { [void]$shared.tcpLock.Release() }

        if ($t -ge 0) {
            $shared.consecutiveFails = 0
        } else {
            $shared.consecutiveFails++
        }

        if (-not $shared.stop) { [System.Threading.Thread]::Sleep($pttPollMs) }
    }
}

# -- Registry helpers ---------------------------------------------------------

function Save-Settings {
    try {
        if (-not (Test-Path $script:regPath)) { New-Item -Path $script:regPath -Force | Out-Null }
        Set-ItemProperty -Path $script:regPath -Name "Host"       -Value $txtHost.Text.Trim()
        Set-ItemProperty -Path $script:regPath -Name "Port"       -Value $txtPort.Text.Trim()
        Set-ItemProperty -Path $script:regPath -Name "SwrProtect" -Value ([int]$chkSwrProtect.Checked) -Type DWord
    } catch { }
}

function Load-Settings {
    if (-not (Test-Path $script:regPath)) { return }
    try {
        $props = Get-ItemProperty -Path $script:regPath -ErrorAction Stop
        if ($props.PSObject.Properties["Host"] -and $props.Host) { $txtHost.Text = $props.Host }
        if ($props.PSObject.Properties["Port"] -and $props.Port) { $txtPort.Text = $props.Port }
        if ($props.PSObject.Properties["SwrProtect"]) { $chkSwrProtect.Checked = [bool]$props.SwrProtect }
    } catch { }
}

# -- GUI construction ---------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text            = "IC-7300 Panel (rigctld)"
$form.ClientSize      = New-Object System.Drawing.Size(280, 462)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox     = $false
$form.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor       = [System.Drawing.Color]::FromArgb(30, 30, 30)
$form.ForeColor       = [System.Drawing.Color]::White

$fontSmall  = New-Object System.Drawing.Font("Segoe UI", 9)
$fontBold   = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$fontPtt    = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$silver    = [System.Drawing.Color]::Silver
$darkBg    = [System.Drawing.Color]::FromArgb(30, 30, 30)
$panelBg   = [System.Drawing.Color]::FromArgb(18, 18, 18)

function New-Label {
    param($Text, $X, $Y, $W)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Location = [System.Drawing.Point]::new($X, $Y)
    $l.Size = [System.Drawing.Size]::new($W, 20); $l.Font = $fontSmall
    $l.ForeColor = $silver; $l.BackColor = $darkBg
    return $l
}

# -- Row 1: Host and Port -----------------------------------------------------
$form.Controls.Add((New-Label "Host:" 5 9 32))

$txtHost = New-Object System.Windows.Forms.TextBox
$txtHost.Location  = [System.Drawing.Point]::new(39, 5)
$txtHost.Size      = [System.Drawing.Size]::new(145, 24)
$txtHost.Text      = "localhost"
$txtHost.Font      = $fontSmall
$form.Controls.Add($txtHost)

$form.Controls.Add((New-Label "Port:" 188 9 30))

$txtPort = New-Object System.Windows.Forms.TextBox
$txtPort.Location  = [System.Drawing.Point]::new(220, 5)
$txtPort.Size      = [System.Drawing.Size]::new(54, 24)
$txtPort.Text      = "4532"
$txtPort.Font      = $fontSmall
$txtPort.MaxLength = 5
$form.Controls.Add($txtPort)

# -- Row 2: Connect / Disconnect ----------------------------------------------
$btnConnect = New-Object System.Windows.Forms.Button
$btnConnect.Text      = "Connect"
$btnConnect.Location  = [System.Drawing.Point]::new(5, 33)
$btnConnect.Size      = [System.Drawing.Size]::new(132, 26)
$btnConnect.Font      = $fontBold
$btnConnect.BackColor = [System.Drawing.Color]::FromArgb(34, 100, 34)
$btnConnect.ForeColor = [System.Drawing.Color]::White
$btnConnect.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$form.Controls.Add($btnConnect)

$btnDisconnect = New-Object System.Windows.Forms.Button
$btnDisconnect.Text      = "Disconnect"
$btnDisconnect.Location  = [System.Drawing.Point]::new(141, 33)
$btnDisconnect.Size      = [System.Drawing.Size]::new(134, 26)
$btnDisconnect.Font      = $fontBold
$btnDisconnect.BackColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$btnDisconnect.ForeColor = [System.Drawing.Color]::White
$btnDisconnect.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDisconnect.Enabled   = $false
$form.Controls.Add($btnDisconnect)

# -- Status label -------------------------------------------------------------
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text      = "Not connected"
$lblStatus.Location  = [System.Drawing.Point]::new(5, 62)
$lblStatus.Size      = [System.Drawing.Size]::new(270, 16)
$lblStatus.Font      = $fontSmall
$lblStatus.ForeColor = $silver
$lblStatus.BackColor = $darkBg
$lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$form.Controls.Add($lblStatus)

# -- SWR protect checkbox -----------------------------------------------------
$chkSwrProtect = New-Object System.Windows.Forms.CheckBox
$chkSwrProtect.Text      = "SWR protect - stop TX above 2.0"
$chkSwrProtect.Location  = [System.Drawing.Point]::new(7, 83)
$chkSwrProtect.Size      = [System.Drawing.Size]::new(266, 18)
$chkSwrProtect.Font      = $fontSmall
$chkSwrProtect.ForeColor = $silver
$chkSwrProtect.BackColor = $darkBg
$form.Controls.Add($chkSwrProtect)

$chkSwrProtect.Add_CheckedChanged({ $script:shared.swrProtect = $chkSwrProtect.Checked; Save-Settings })

# -- PTT status label ---------------------------------------------------------
$lblPtt = New-Object System.Windows.Forms.Label
$lblPtt.Location  = [System.Drawing.Point]::new(5, 106)
$lblPtt.Size      = [System.Drawing.Size]::new(270, 34)
$lblPtt.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
$lblPtt.ForeColor = [System.Drawing.Color]::White
$lblPtt.Text      = "---"
$lblPtt.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblPtt.Font      = $fontPtt
$lblPtt.Cursor    = [System.Windows.Forms.Cursors]::Hand
$lblPtt.Add_Click({
    $next = if ($script:shared.pttState -eq 1) { 0 } else { 1 }
    Set-Ptt -State $next
})
$form.Controls.Add($lblPtt)

# -- Meter panels (stacked) ---------------------------------------------------
$pnlSwr = New-Object System.Windows.Forms.Panel
$pnlSwr.Location  = [System.Drawing.Point]::new(5, 146)
$pnlSwr.Size      = [System.Drawing.Size]::new(270, 64)
$pnlSwr.BackColor = $panelBg
$form.Controls.Add($pnlSwr)

$pnlPwr = New-Object System.Windows.Forms.Panel
$pnlPwr.Location  = [System.Drawing.Point]::new(5, 216)
$pnlPwr.Size      = [System.Drawing.Size]::new(270, 64)
$pnlPwr.BackColor = $panelBg
$form.Controls.Add($pnlPwr)

$pnlAlc = New-Object System.Windows.Forms.Panel
$pnlAlc.Location  = [System.Drawing.Point]::new(5, 286)
$pnlAlc.Size      = [System.Drawing.Size]::new(270, 64)
$pnlAlc.BackColor = $panelBg
$form.Controls.Add($pnlAlc)

# Enable double-buffering to eliminate repaint flicker.
$dbl = [System.Windows.Forms.Control].GetProperty('DoubleBuffered',
    [System.Reflection.BindingFlags]'NonPublic,Instance')
$dbl.SetValue($pnlSwr, $true, $null)
$dbl.SetValue($pnlPwr, $true, $null)
$dbl.SetValue($pnlAlc, $true, $null)

$pnlSwr.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics; $pw = $sender.Width; $ph = $sender.Height
    $swr = $script:shared.swrVal
    $g.FillRectangle([System.Drawing.Brushes]::Black, 0, 0, $pw, $ph)
    # pct: 0 = SWR 1.0, 0.5 = SWR 2.0, 1.0 = SWR 3.0+
    $pct = if ($swr -ge 1.0) { [Math]::Min(1.0, ($swr - 1.0) / 2.0) } else { 0.0 }
    if ($swr -ge 1.0) {
        $barW = [int]($pct * ($pw - 4))
        if ($barW -gt 0) {
            $br = if ($pct -lt 0.25)    { $script:brushGreen }
                  elseif ($pct -lt 0.5) { $script:brushYellow }
                  else                  { $script:brushOrange }
            $g.FillRectangle($br, 2, $ph - 24, $barW, 20)
        }
    }
    $swrText = if ($swr -lt 0)       { "SWR  ---" }
               elseif ($swr -le 1.0) { "SWR  1.0" }
               else                  { "SWR  {0:F1}" -f $swr }
    $g.DrawString($swrText, $script:fontMeter, [System.Drawing.Brushes]::White, 4, 6)
})

$pnlPwr.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics; $pw = $sender.Width; $ph = $sender.Height
    $frac = $script:shared.pwrFrac
    $g.FillRectangle([System.Drawing.Brushes]::Black, 0, 0, $pw, $ph)
    $pct = if ($frac -ge 0.0) { [Math]::Min(1.0, $frac) } else { 0.0 }
    if ($frac -ge 0.0) {
        $barW = [int]($pct * ($pw - 4))
        if ($barW -gt 0) { $g.FillRectangle($script:brushGreen, 2, $ph - 24, $barW, 20) }
    }
    $watts = [int]($pct * 100)
    $pwrText = if ($frac -lt 0.0)   { "PWR  --- W" }
               elseif ($pct -eq 0)  { "PWR    0 W" }
               else                 { "PWR  {0,3} W" -f $watts }
    $g.DrawString($pwrText, $script:fontMeter, [System.Drawing.Brushes]::White, 4, 6)
})

$pnlAlc.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics; $pw = $sender.Width; $ph = $sender.Height
    $frac = $script:shared.alcFrac
    $g.FillRectangle([System.Drawing.Brushes]::Black, 0, 0, $pw, $ph)
    $pct = if ($frac -ge 0.0) { [Math]::Min(1.0, $frac) } else { 0.0 }
    if ($frac -ge 0.0) {
        $barW = [int]($pct * ($pw - 4))
        if ($barW -gt 0) {
            $br = if ($pct -lt 0.5)      { $script:brushGreen }
                  elseif ($pct -lt 0.8)  { $script:brushYellow }
                  else                   { $script:brushOrange }
            $g.FillRectangle($br, 2, $ph - 24, $barW, 20)
        }
    }
    $alcText = if ($frac -lt 0.0)   { "ALC  ---" }
               elseif ($pct -eq 0)  { "ALC    0%" }
               else                 { "ALC  {0,3}%" -f ([int]($pct * 100)) }
    $g.DrawString($alcText, $script:fontMeter, [System.Drawing.Brushes]::White, 4, 6)
})

# -- Button grid (2 rows x 4) -------------------------------------------------
$flow = New-Object System.Windows.Forms.FlowLayoutPanel
$flow.Location      = [System.Drawing.Point]::new(5, 356)
$flow.Size          = [System.Drawing.Size]::new(270, 68)
$flow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$flow.WrapContents  = $true
$flow.BackColor     = $darkBg
$form.Controls.Add($flow)

foreach ($entry in @(
    @{W=1;   Label="1W";   Tune=$false},
    @{W=5;   Label="5W";   Tune=$false},
    @{W=25;  Label="25W";  Tune=$false},
    @{W=50;  Label="50W";  Tune=$false},
    @{W=75;  Label="75W";  Tune=$false},
    @{W=90;  Label="90W";  Tune=$false},
    @{W=100; Label="100W"; Tune=$false},
    @{W=0;   Label="TUNE"; Tune=$true}
)) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text      = $entry.Label
    $btn.Size      = New-Object System.Drawing.Size(62, 30)
    $btn.Margin    = New-Object System.Windows.Forms.Padding(2)
    $btn.Font      = $fontBold
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    if ($entry.Tune) {
        $btn.BackColor = [System.Drawing.Color]::FromArgb(140, 20, 20)
        $btn.Add_Click({ Start-Tune })
    } else {
        $btn.BackColor = [System.Drawing.Color]::FromArgb(40, 70, 110)
        $btn.Tag = $entry.W
        $btn.Add_Click({ Set-PowerLevel -Watts ([int]$this.Tag) })
    }
    $flow.Controls.Add($btn)
}

# -- UI refresh timer (display only -- no network I/O on the UI thread) -------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 50

$timer.Add_Tick({
    $pnlPwr.Invalidate()
    $pnlSwr.Invalidate()
    $pnlAlc.Invalidate()

    $ptt = $script:shared.pttState
    if ($ptt -eq 1) {
        $lblPtt.BackColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
        $lblPtt.Text      = "Transmitting..."
    } elseif ($ptt -eq 0) {
        $lblPtt.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 0)
        $lblPtt.Text      = "Receiving"
    } else {
        $lblPtt.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
        $lblPtt.Text      = "---"
    }

    if (-not $script:bgPs) { return }

    $fails = $script:shared.consecutiveFails
    if ($fails -eq 0) {
        $lblStatus.Text      = 'Polling OK'
        $lblStatus.ForeColor = [System.Drawing.Color]::LimeGreen
    } elseif ($fails -lt 20) {
        $lblStatus.Text      = "Polling warn ($fails)"
        $lblStatus.ForeColor = [System.Drawing.Color]::Yellow
    } elseif ($fails -lt 50) {
        $lblStatus.Text      = "Polling FAIL ($fails)"
        $lblStatus.ForeColor = [System.Drawing.Color]::OrangeRed
    } else {
        $lblStatus.Text      = 'Polling FAIL - disconnecting'
        $lblStatus.ForeColor = [System.Drawing.Color]::OrangeRed
        Invoke-Disconnect
    }
})

# -- Disconnect (shared by button, auto-disconnect, and FormClosing) ----------
function Invoke-Disconnect {
    if (-not $script:bgPs) { return }

    $timer.Stop()
    $script:shared.stop = $true

    # Closing the socket interrupts any blocking ReadLine() in the background thread.
    if ($script:tcpClient) {
        try { $script:tcpClient.Close()   } catch { }
        try { $script:tcpClient.Dispose() } catch { }
        $script:tcpClient = $null
        $script:tcpStream = $null
    }

    $script:bgHandle.AsyncWaitHandle.WaitOne(2000) | Out-Null
    try   { $script:bgPs.EndInvoke($script:bgHandle) } catch { }
    try   { $script:bgPs.Dispose()                   } catch { }
    $script:bgPs     = $null
    $script:bgHandle = $null

    $script:shared.pwrFrac = -1.0; $script:shared.swrVal = -1.0; $script:shared.alcFrac = -1.0; $script:shared.pttState = -1
    $pnlPwr.Invalidate(); $pnlSwr.Invalidate(); $pnlAlc.Invalidate()
    $lblPtt.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50); $lblPtt.Text = "---"

    $lblStatus.Text      = 'Not connected'
    $lblStatus.ForeColor = $silver
    $btnConnect.Enabled    = $true
    $btnDisconnect.Enabled = $false
    $txtHost.Enabled = $true; $txtPort.Enabled = $true
    $form.Text = 'IC-7300 Panel (rigctld)'
}

# -- Connect ------------------------------------------------------------------
$btnConnect.Add_Click({
    $hostStr = $txtHost.Text.Trim()
    $portNum = 0
    if (-not $hostStr) {
        [System.Windows.Forms.MessageBox]::Show("Enter a host or IP address.", "Connect",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    if (-not [int]::TryParse($txtPort.Text.Trim(), [ref]$portNum) -or
            $portNum -lt 1 -or $portNum -gt 65535) {
        [System.Windows.Forms.MessageBox]::Show("Port must be 1-65535.", "Connect",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.ReceiveTimeout = 100    # bg poller uses 100ms; Send-RigctlSetCmd overrides to 200ms when needed
        $tcp.SendTimeout    = 500
        $tcp.Connect($hostStr, $portNum)

        $stream               = $tcp.GetStream()
        $script:tcpStream     = $stream
        $script:tcpClient     = $tcp

        Save-Settings

        $script:shared.stop             = $false
        $script:shared.consecutiveFails = 0
        $script:shared.pwrFrac          = -1.0
        $script:shared.swrVal           = -1.0
        $script:shared.pttState         = -1
        $script:shared.swrProtect       = $chkSwrProtect.Checked

        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.Open()

        $rs.SessionStateProxy.SetVariable('tcpStream', $script:tcpStream)
        $rs.SessionStateProxy.SetVariable('shared',    $script:shared)

        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($bgScript)
        $script:bgHandle = $ps.BeginInvoke()
        $script:bgPs     = $ps

        $timer.Start()

        $btnConnect.Enabled    = $false
        $btnDisconnect.Enabled = $true
        $txtHost.Enabled = $false; $txtPort.Enabled = $false
        $lblStatus.Text      = 'Connected'
        $lblStatus.ForeColor = [System.Drawing.Color]::LimeGreen
        $form.Text = "IC-7300  [${hostStr}:${portNum}]"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not connect: $_", "Connect",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        if ($script:tcpClient) { try { $script:tcpClient.Dispose() } catch { } }
        $script:tcpClient = $null; $script:tcpStream = $null
    }
})

$btnDisconnect.Add_Click({ Invoke-Disconnect })

# -- Cleanup ------------------------------------------------------------------
$form.Add_FormClosing({
    Invoke-Disconnect
    $script:fontMeter.Dispose(); $fontSmall.Dispose(); $fontBold.Dispose(); $fontPtt.Dispose()
    $script:brushGreen.Dispose(); $script:brushYellow.Dispose(); $script:brushOrange.Dispose()
    $script:shared.tcpLock.Dispose()
    $timer.Dispose()
})

# -- Load saved settings then show --------------------------------------------
Load-Settings
[void]$form.ShowDialog()
