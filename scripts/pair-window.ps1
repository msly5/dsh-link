param([switch]$Check)
$ErrorActionPreference = 'Stop'
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $inputData = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $bytes = [Convert]::FromBase64String($inputData.png)
    $stream = [IO.MemoryStream]::new($bytes, 0, $bytes.Length)
    $image = [Drawing.Image]::FromStream($stream)
    if ($Check) { Write-Output 'PASS: local pairing image loaded.'; exit 0 }
    [Windows.Forms.Application]::EnableVisualStyles()
    $form = [Windows.Forms.Form]::new()
    $form.Text = 'dsh link - Connect your phone'
    $form.ClientSize = [Drawing.Size]::new(460, 610)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.BackColor = [Drawing.Color]::FromArgb(249,249,246)
    $heading = [Windows.Forms.Label]::new()
    $heading.Text = 'Scan in dsh link on iOS or Android'
    $heading.SetBounds(24,20,412,32)
    $heading.Font = [Drawing.Font]::new('Segoe UI',14)
    $form.Controls.Add($heading)
    $picture = [Windows.Forms.PictureBox]::new()
    $picture.SetBounds(30,60,400,400)
    $picture.SizeMode = 'Zoom'
    $picture.Image = $image
    $form.Controls.Add($picture)
    $status = [Windows.Forms.Label]::new()
    $status.SetBounds(24,464,412,64)
    $status.Text = $inputData.server + "`r`nExpires in 5 minutes. Keep this code private."
    $form.Controls.Add($status)
    $details = [Windows.Forms.Button]::new()
    $details.Text = 'Show manual connection details'
    $details.SetBounds(24,540,412,40)
    $details.Add_Click({
        $dialog = [Windows.Forms.Form]::new()
        $dialog.Text = 'Private connection details'
        $dialog.ClientSize = [Drawing.Size]::new(540,200)
        $dialog.StartPosition = 'CenterParent'
        $text = [Windows.Forms.TextBox]::new()
        $text.Multiline = $true; $text.ReadOnly = $true; $text.Dock = 'Fill'
        $text.Text = $inputData.server
        if ($inputData.connectionKey) { $text.Text += "`r`n`r`nConnection key:`r`n" + $inputData.connectionKey }
        else { $text.Text += "`r`n`r`nUse your Cloudflare Service Token Client ID and Secret, or scan the QR code." }
        $dialog.Controls.Add($text)
        [void]$dialog.ShowDialog($form)
        $dialog.Dispose()
    })
    $form.Controls.Add($details)
    $timer = [Windows.Forms.Timer]::new(); $timer.Interval = 1000
    $timer.Add_Tick({
        if ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -ge $inputData.expiresAt) {
            $picture.Visible = $false; $details.Enabled = $false
            $status.Text = 'Code expired. Enter p in the terminal to open a new code.'
            $timer.Stop()
        }
    })
    $timer.Start()
    [void]$form.ShowDialog()
    $timer.Dispose(); $form.Dispose(); $image.Dispose(); $stream.Dispose()
} catch { [Console]::Error.WriteLine('Cannot display the pairing window. No credentials were logged.'); exit 1 }
