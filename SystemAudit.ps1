# ==========================================
# CONG CU KIEM TRA HE THONG - SystemAudit.ps1
# Windows 10/11 | PowerShell 5.1+ | Tieng Viet khong dau
# ==========================================
#Requires -RunAsAdministrator
param([switch]$ChiTiet)

# --- BIEN TOAN CUC ---
$script:BaoCao = @()
$script:Debug = $ChiTiet.IsPresent

function Ghi-BaoCao {
    param([string]$NoiDung, [switch]$ChiTiet)
    if ($ChiTiet -and -not $script:Debug) { return }
    $script:BaoCao += $NoiDung
    if (-not $ChiTiet) { Write-Host $NoiDung }
}

function Thu-PhuongPhap {
    param([Parameter(Mandatory)][array]$DS)
    foreach ($p in $DS) {
        Ghi-BaoCao -ChiTiet "  [DEBUG] Thu: $($p.Ten)..."
        try {
            $kq = & $p.Script
            if ($kq) { Ghi-BaoCao -ChiTiet "  [DEBUG] -> OK: $($p.Ten)"; return $kq }
        } catch { Ghi-BaoCao -ChiTiet "  [DEBUG] -> Loi: $_" }
    }
    Ghi-BaoCao -ChiTiet "  [DEBUG] -> Tat ca deu that bai!"
    return $null
}

# ==========================================
# HAM 1: KIEM TRA BAN QUYEN WINDOWS
# ==========================================
function KiemTra-BanQuyenWindows {
    Ghi-BaoCao "========================================"
    Ghi-BaoCao "1. KIEM TRA BAN QUYEN WINDOWS"
    Ghi-BaoCao "========================================"
    Ghi-BaoCao ""

    $os = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
    if (-not $os) { Ghi-BaoCao "[!] Khong doc duoc thong tin OS"; Ghi-BaoCao ""; return }

    Ghi-BaoCao "Ten he dieu hanh : $($os.ProductName)"
    Ghi-BaoCao "Phien ban        : $(if ($os.DisplayVersion) { $os.DisplayVersion } else { $os.ReleaseId })"
    Ghi-BaoCao "So hieu build    : $($os.CurrentBuild).$($os.UBR)"
    Ghi-BaoCao "Kien truc        : $(if ([Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit' })"
    Ghi-BaoCao ""

    $lic = Thu-PhuongPhap -DS @(
        @{ Ten = "CIM SoftwareLicensing"; Script = {
            Get-CimInstance SoftwareLicensingProduct -Filter "Name like 'Windows%'" -ErrorAction Stop |
            Where-Object { $_.PartialProductKey -and ($_.Name -notmatch "TIMESTAMP") } | Select-Object -First 1 }},
        @{ Ten = "WMI SoftwareLicensing"; Script = {
            Get-WmiObject SoftwareLicensingProduct -Filter "Name like 'Windows%'" -ErrorAction SilentlyContinue |
            Where-Object { $_.PartialProductKey -and ($_.Name -notmatch "TIMESTAMP") } | Select-Object -First 1 }}
    )

    if (-not $lic) { Ghi-BaoCao "[!] Khong tim thay ban quyen Windows"; Ghi-BaoCao ""; return }

    $loai = switch -Regex ($lic.Description) {
        "OEM" { "OEM (Nha san xuat)" }
        "RETAIL" { "Retail (Ban le)" }
        "VOLUME_MAK" { "MAK (Volume)" }
        "VOLUME_KMS" { "KMS (Volume)" }
        default { if ($lic.Description) { $lic.Description } else { "Khong xac dinh" } }
    }
    $trangThai = switch ($lic.LicenseStatus) {
        0 { "Chua duoc cap quyen" }
        1 { "Da cap quyen - HOP LE" }
        2 { "Het han" }
        3 { "Can kich hoat" }
        4 { "Non-Genuine" }
        default { "Ma: $($lic.LicenseStatus)" }
    }

    Ghi-BaoCao "Loai ban quyen   : $loai"
    Ghi-BaoCao "Kenh kich hoat   : $(if ($lic.LicenseFamily) { $lic.LicenseFamily } else { 'Khong xac dinh' })"
    Ghi-BaoCao "5 ky tu cuoi key : $($lic.PartialProductKey)"
    Ghi-BaoCao "Trang thai       : $trangThai"
    Ghi-BaoCao ""
    Ghi-BaoCao "--- HUONG DAN BAO QUAN KEY ---"
    if ($loai -match "OEM") {
        Ghi-BaoCao "+ Key OEM nhung vao BIOS/UEFI, tu dong kich hoat khi cai lai dung phien ban"
        Ghi-BaoCao "+ KHONG MAT KEY khi cai lai neu dung phien ban dung"
    } elseif ($loai -match "Retail") {
        Ghi-BaoCao "+ Key Retail can LUU TRU RIENG, CO THE MAT KEY neu khong luu"
        Ghi-BaoCao "+ Khuyen nghi: Lien ket tai khoan Microsoft de bao ve ban quyen"
    } elseif ($loai -match "MAK|KMS") {
        Ghi-BaoCao "+ Key Volume can quan ly boi IT/Admin"
        Ghi-BaoCao "+ MAK: luu lai key | KMS: ket noi server de tu dong kich hoat"
    }
    Ghi-BaoCao ""
}

# ==========================================
# HAM 2: KIEM TRA BAN QUYEN OFFICE
# ==========================================
function KiemTra-BanQuyenOffice {
    Ghi-BaoCao "========================================"
    Ghi-BaoCao "2. KIEM TRA BAN QUYEN OFFICE"
    Ghi-BaoCao "========================================"
    Ghi-BaoCao ""

    # --- BUOC 1: Thu thap du lieu tu nhieu nguon ---
    $dsPhatHien = @{}  # Hash: TenChuan -> thong tin

    # PP1: Registry Uninstall (tin cay nhat)
    foreach ($path in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
        if (-not (Test-Path $path)) { continue }
        Get-ChildItem $path -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if (-not $p.DisplayName) { return }
                $name = $p.DisplayName
                if ($name -notmatch "Microsoft Office|Microsoft 365") { return }
                if ($name -match "Proofing|Visual|Web Components|Shared|Shell|Runtime|Language|Update|Add-in") { return }
                $tenChuan = $name -replace "\s+-\s+en-us$", "" -replace "\s+\(\d{2}\d{2}\)$", "" -replace "\s+\d{4}$", ""
                if (-not $dsPhatHien.ContainsKey($tenChuan)) {
                    $bit = if ($name -match "64-bit|x64") { "64-bit" } elseif ($name -match "32-bit|x86") { "32-bit" } else { "Khong ro" }
                    $dsPhatHien[$tenChuan] = [PSCustomObject]@{ Ten = $tenChuan; Ver = $p.DisplayVersion; Bit = $bit; Nguon = @("Registry Uninstall"); DuongDan = $p.InstallLocation }
                } else {
                    $dsPhatHien[$tenChuan].Nguon += "Registry Uninstall"
                    if ($dsPhatHien[$tenChuan].Bit -eq "Khong ro" -and ($name -match "64-bit|x64")) { $dsPhatHien[$tenChuan].Bit = "64-bit" }
                }
            } catch {}
        }
    }

    # PP2: Registry Office\XX.0 (kiem tra duong dan truoc khi dung)
    foreach ($root in @("HKLM:\SOFTWARE\Microsoft\Office", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office")) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d+\.0$' } | ForEach-Object {
            try {
                if (-not $_.FullName) { return }
                $v = [int]($_.PSChildName -replace '\.0$','')
                $ten = switch ($v) { 11 { "Office 2003" }; 12 { "Office 2007" }; 14 { "Office 2010" }; 15 { "Office 2013" }; 16 { "Office 2016/2019/2021/365/2024" }; default { "Office ($($_.PSChildName))" } }
                $c2rPath = Join-Path $_.FullName "ClickToRun\Configuration"
                $insPath = Join-Path $_.FullName "Common\InstallRoot"
                $daCai = $false
                if (Test-Path $c2rPath) { $daCai = $true }
                if (-not $daCai -and (Test-Path $insPath)) {
                    $insVal = Get-ItemProperty $insPath -ErrorAction SilentlyContinue
                    if ($insVal -and $insVal.Path) { $daCai = $true }
                }
                if (-not $daCai) { return }
                $tenDayDu = "Microsoft $ten"
                if (-not $dsPhatHien.ContainsKey($tenDayDu)) {
                    $bit = "Khong ro"
                    $outPath = Join-Path $_.FullName "Outlook"
                    if (Test-Path $outPath) { $b = (Get-ItemProperty $outPath -ErrorAction SilentlyContinue).Bitness; if ($b) { $bit = $b } }
                    $dsPhatHien[$tenDayDu] = [PSCustomObject]@{ Ten = $tenDayDu; Ver = $_.PSChildName; Bit = $bit; Nguon = @("Registry Office"); DuongDan = "" }
                } else {
                    $dsPhatHien[$tenDayDu].Nguon += "Registry Office"
                }
            } catch {}
        }
    }

    # PP3: App Paths (kiem tra file EXE thuc te)
    foreach ($apRoot in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths")) {
        if (-not (Test-Path $apRoot)) { continue }
        foreach ($exe in @("Winword.exe", "Excel.exe", "Powerpnt.exe")) {
            $ap = Join-Path $apRoot $exe
            if (-not (Test-Path $ap)) { continue }
            try {
                $pr = Get-ItemProperty $ap -ErrorAction SilentlyContinue
                $fp = $pr.'(Default)'; if (-not $fp -and $pr.Path) { $fp = Join-Path $pr.Path $exe }
                if (-not $fp -or -not (Test-Path $fp)) { continue }
                $fv = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($fp)
                $ver = if ($fp -match "Office(\\|/)16") { "2016/2019/2021/365/2024" } elseif ($fp -match "Office(\\|/)15") { "2013" } elseif ($fp -match "Office(\\|/)14") { "2010" } else { "Khong ro" }
                $ten = "Microsoft Office $ver"
                if (-not $dsPhatHien.ContainsKey($ten)) {
                    $bit = if ($fp -match "x86|WOW6432Node|Program Files \(x86\)") { "32-bit" } else { "64-bit" }
                    $dsPhatHien[$ten] = [PSCustomObject]@{ Ten = $ten; Ver = $fv.ProductVersion; Bit = $bit; Nguon = @("App Paths ($exe)"); DuongDan = $fp }
                } else {
                    $dsPhatHien[$ten].Nguon += "App Paths ($exe)"
                    if ($dsPhatHien[$ten].Ver -eq "Khong ro") { $dsPhatHien[$ten].Ver = $fv.ProductVersion }
                }
            } catch {}
        }
    }

    # PP4: C2R Configuration tong hop
    try {
        $c2rMain = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
        if (Test-Path $c2rMain) {
            $c2r = Get-ItemProperty $c2rMain -ErrorAction SilentlyContinue
            if ($c2r.ProductReleaseIds) {
                $plat = if ($c2r.Platform) { $c2r.Platform } else { "x86" }
                $ten = "Microsoft 365 / Office C2R ($($c2r.ProductReleaseIds))"
                if (-not $dsPhatHien.ContainsKey($ten)) {
                    $bit = if ($plat -eq "x64") { "64-bit" } else { "32-bit" }
                    $dsPhatHien[$ten] = [PSCustomObject]@{ Ten = $ten; Ver = $c2r.VersionToReport; Bit = $bit; Nguon = @("C2R Config"); DuongDan = $c2r.InstallPath }
                }
            }
        }
    } catch {}

    # --- BUOC 2: TONG HOP VA LOC TRUNG LAP ---
    # Gop cac phien ban giong nhau (chi khac nguon)
    $dsTongHop = @{}
    foreach ($key in $dsPhatHien.Keys) {
        $item = $dsPhatHien[$key]
        # Tim xem da co phien ban tuong tu chua
        $daCo = $false
        foreach ($tk in $dsTongHop.Keys) {
            if ($item.Ten -eq $dsTongHop[$tk].Ten -or ($item.Ten -match "Office" -and $dsTongHop[$tk].Ten -match "Office" -and $item.Ver -eq $dsTongHop[$tk].Ver)) {
                $dsTongHop[$tk].Nguon += $item.Nguon
                if ($dsTongHop[$tk].Bit -eq "Khong ro" -and $item.Bit -ne "Khong ro") { $dsTongHop[$tk].Bit = $item.Bit }
                $daCo = $true; break
            }
        }
        if (-not $daCo) { $dsTongHop[$key] = $item }
    }

    if ($dsTongHop.Count -eq 0) { Ghi-BaoCao "[!] Khong phat hien Microsoft Office"; Ghi-BaoCao ""; return }

    Ghi-BaoCao "Da tim thay $($dsTongHop.Count) bo Office:"
    Ghi-BaoCao ""

    # --- BUOC 3: Tim license tu nhieu nguon ---
    $licenses = @()

    # PP1: WMI/CIM SoftwareLicensingProduct
    try {
        $l = Get-CimInstance SoftwareLicensingProduct -Filter "Name like 'Office%'" -ErrorAction Stop | Where-Object { $_.PartialProductKey }
        if ($l) { foreach ($i in $l) { $licenses += [PSCustomObject]@{ Name = $i.Name; Key = $i.PartialProductKey; Desc = $i.Description; Status = $i.LicenseStatus } } }
    } catch {
        try {
            $l = Get-WmiObject SoftwareLicensingProduct -Filter "Name like 'Office%'" -ErrorAction SilentlyContinue | Where-Object { $_.PartialProductKey }
            if ($l) { foreach ($i in $l) { $licenses += [PSCustomObject]@{ Name = $i.Name; Key = $i.PartialProductKey; Desc = $i.Description; Status = $i.LicenseStatus } } }
        } catch {}
    }

    # PP2: OSPP Registry
    foreach ($ospp in @("HKLM:\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform\Products", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\OfficeSoftwareProtectionPlatform\Products")) {
        if (-not (Test-Path $ospp)) { continue }
        try {
            Get-ChildItem $ospp -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $prod = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                    if ($prod.ProductName -and $prod.PartialProductKey) {
                        $licenses += [PSCustomObject]@{ Name = $prod.ProductName; Key = $prod.PartialProductKey; Desc = $prod.ProductDescription; Status = $prod.LicenseStatus }
                    }
                } catch {}
            }
        } catch {}
    }

    # PP3: ospp.vbs
    foreach ($vbs in @("${env:ProgramFiles}\Microsoft Office\Office16\ospp.vbs", "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs", "${env:ProgramFiles}\Microsoft Office\Office15\ospp.vbs", "${env:ProgramFiles(x86)}\Microsoft Office\Office15\ospp.vbs")) {
        if (-not (Test-Path $vbs)) { continue }
        try {
            $out = cscript //nologo "$vbs" /dstatus 2>$null
            if ($out) {
                $lines = $out -split "`r`n"; $cur = @{}
                foreach ($line in $lines) {
                    if ($line -match "LICENSE NAME:\s*(.+)$") {
                        if ($cur.Count -gt 0) { $licenses += [PSCustomObject]@{ Name = $cur["N"]; Key = $cur["K"]; Desc = $cur["S"]; Status = $cur["S"] }; $cur = @{} }
                        $cur["N"] = $matches[1].Trim()
                    } elseif ($line -match "LAST 5 CHARACTERS OF INSTALLED PRODUCT KEY:\s*(\w+)") { $cur["K"] = $matches[1].Trim() }
                    elseif ($line -match "LICENSE STATUS:\s*(.+)") { $cur["S"] = $matches[1].Trim() }
                }
                if ($cur.Count -gt 0) { $licenses += [PSCustomObject]@{ Name = $cur["N"]; Key = $cur["K"]; Desc = $cur["S"]; Status = $cur["S"] } }
            }
        } catch {}
    }

    # PP4: Office Registration Registry
    foreach ($ver in @("11.0", "12.0", "14.0", "15.0", "16.0")) {
        foreach ($rp in @("HKLM:\SOFTWARE\Microsoft\Office\$ver\Registration", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\$ver\Registration")) {
            if (-not (Test-Path $rp)) { continue }
            try {
                Get-ChildItem $rp -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $rprops = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                        if ($rprops.ProductName) {
                            $pk = "Khong ro"
                            if ($rprops.ProductID -and $rprops.ProductID.Length -ge 5) { $pk = $rprops.ProductID.Substring($rprops.ProductID.Length - 5) }
                            $licenses += [PSCustomObject]@{ Name = $rprops.ProductName; Key = $pk; Desc = "Office Registration"; Status = "Khong ro" }
                        }
                    } catch {}
                }
            } catch {}
        }
    }

    # --- BUOC 4: HIEN THI KET QUA TONG HOP ---
    foreach ($key in $dsTongHop.Keys) {
        $off = $dsTongHop[$key]
        Ghi-BaoCao "----------------------------------------"
        Ghi-BaoCao "Phan mem : $($off.Ten)"
        Ghi-BaoCao "Phien ban: $($off.Ver)"
        Ghi-BaoCao "Kien truc: $($off.Bit)"
        if ($script:Debug) { Ghi-BaoCao "Nguon    : $($off.Nguon -join ', ')" }
        Ghi-BaoCao ""

        if ($off.Ten -match "2003") {
            Ghi-BaoCao "  -> Office 2003 khong ho tro kiem tra ban quyen tu dong"
            Ghi-BaoCao "  -> Kiem tra thu cong: Help > About trong Word/Excel"
            Ghi-BaoCao ""; continue
        }

        # Tim license tuong ung
        $tenLower = $off.Ten.ToLower()
        $licTuongUng = @()
        foreach ($lc in $licenses) {
            $ln = $lc.Name.ToLower()
            # So sanh long leo
            if ($ln -match "office" -and $tenLower -match "office") {
                # Kiem tra phien ban
                if ($tenLower -match "2024" -and $ln -match "2024") { $licTuongUng += $lc }
                elseif ($tenLower -match "2021" -and $ln -match "2021") { $licTuongUng += $lc }
                elseif ($tenLower -match "2019" -and $ln -match "2019") { $licTuongUng += $lc }
                elseif ($tenLower -match "2016" -and ($ln -match "2016" -or $ln -match "365")) { $licTuongUng += $lc }
                elseif ($tenLower -match "365" -and ($ln -match "365" -or $ln -match "2016")) { $licTuongUng += $lc }
                elseif ($tenLower -match "2013" -and $ln -match "2013") { $licTuongUng += $lc }
                elseif ($tenLower -match "2010" -and $ln -match "2010") { $licTuongUng += $lc }
                elseif ($tenLower -match "ltsc" -and $ln -match "ltsc") { $licTuongUng += $lc }
                elseif ($tenLower -match "professional" -and $ln -match "pro") { $licTuongUng += $lc }
                elseif ($ln -match [regex]::Escape($off.Ten -replace "Microsoft ", "")) { $licTuongUng += $lc }
            }
        }
        $licTuongUng = $licTuongUng | Sort-Object Key -Unique

        if ($licTuongUng.Count -gt 0) {
            Ghi-BaoCao "  -> Da tim thay ban quyen:"
            foreach ($lc in $licTuongUng) {
                $st = if ($lc.Status -is [int]) {
                    switch ($lc.Status) { 0 { "Chua cap quyen" }; 1 { "Da cap quyen - HOP LE" }; 2 { "Het han" }; 3 { "Can kich hoat" }; 4 { "Non-Genuine" }; default { "Ma: $($lc.Status)" } }
                } else { $lc.Status }
                Ghi-BaoCao "     + Key (5 ky tu): $($lc.Key)"
                Ghi-BaoCao "     + Loai         : $($lc.Desc)"
                Ghi-BaoCao "     + Trang thai   : $st"
            }
        } else {
            Ghi-BaoCao "  -> Khong tim thay ban quyen"
            Ghi-BaoCao "     Nguyen nhan co the la:"
            Ghi-BaoCao "     - Office chua duoc kich hoat"
            Ghi-BaoCao "     - Dung tai khoan Microsoft / Office 365 (khong luu key cuc bo)"
            Ghi-BaoCao "     - Da bi xoa key kich hoat"
            Ghi-BaoCao "     - Key duoc quan ly boi to chuc (KMS/MAK)"
        }
        Ghi-BaoCao ""
    }
}




# ==========================================
# HAM 3: KIEM TRA PHAN MEM BAO MAT
# ==========================================
function KiemTra-BaoMat {
    Ghi-BaoCao "========================================"
    Ghi-BaoCao "3. KIEM TRA PHAN MEM BAO MAT"
    Ghi-BaoCao "========================================"
    Ghi-BaoCao ""

    $defOn = $false; $defVer = "Khong xac dinh"
    try { $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue; if ($mp) { $defOn = $mp.AntivirusEnabled; $defVer = $mp.AMProductVersion } } catch {}
    Ghi-BaoCao "Windows Defender:"
    Ghi-BaoCao "  - Trang thai : $(if ($defOn) { 'DANG BAT' } else { 'DANG TAT' })"
    Ghi-BaoCao "  - Phien ban  : $defVer"
    Ghi-BaoCao ""

    # === CAC TU KHOA VA HAM TRO GIUP ===
    $avKeys = @("Kaspersky", "Bitdefender", "Norton", "Symantec", "McAfee", "Avast", "AVG", "ESET", "Trend", "F-Secure", "Malwarebytes", "Avira", "Sophos", "CMC", "Bkav", "360")
    
    # Cac tu uu tien lam san pham chinh (cang cao cang uu tien)
    $tuUuTienChinh = @("Endpoint Security", "Internet Security", "Total Security", "Antivirus", "Security", "Pro", "Free", "Premium")
    # Cac tu thuong la thanh phan phu
    $tuPhu = @("Agent", "proxy", "server", "Service", "Network", "Update", "Center", "Cloud", "Console", "Manager", "Administration", "Distribution")

    # Ham tinh diem ten san pham (cao = uu tien hon)
    function Tinh-DiemTen {
        param([string]$Ten)
        $diem = 0
        foreach ($tu in $tuUuTienChinh) { if ($Ten -match $tu) { $diem += 10 } }
        foreach ($tu in $tuPhu) { if ($Ten -match $tu) { $diem -= 5 } }
        return $diem
    }

    # Ham xac dinh kien truc tu duong dan cai dat
    function XacDinh-KienTrucTuDuongDan {
        param([string]$DuongDan)
        if (-not $DuongDan) { return "Khong ro" }
        if ($DuongDan -match "Program Files \(x86\)|WOW6432Node|x86") { return "32-bit" }
        if ($DuongDan -match "Program Files[^\(]|x64") { return "64-bit" }
        return "Khong ro"
    }

    # === THU THAP DU LIEU TU NHIEU NGUON ===
    # Moi phan tu: [PSCustomObject]@{ TenDayDu, Ver, Bit, Nguon, DuongDan, TrangThai, Diem }
    $dsTatCaPhienBan = @()

    # PP1: Registry Uninstall
    foreach ($path in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
        if (-not (Test-Path $path)) { continue }
        Get-ChildItem $path -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if (-not $p.DisplayName) { return }
                $name = $p.DisplayName
                $isAV = $false
                foreach ($k in $avKeys) { if ($name -match $k) { $isAV = $true; break } }
                if (-not $isAV) { return }
                
                $bit = XacDinh-KienTrucTuDuongDan -DuongDan $p.InstallLocation
                $dsTatCaPhienBan += [PSCustomObject]@{ 
                    TenDayDu = $name; 
                    Ver = $p.DisplayVersion; 
                    Bit = $bit; 
                    Nguon = "Registry"; 
                    DuongDan = $p.InstallLocation;
                    TrangThai = "Da cai dat";
                    Diem = (Tinh-DiemTen -Ten $name)
                }
            } catch {}
        }
    }

    # PP2: Services
    $svcPattern = "avp|kaspersky|bdagent|bitdefender|norton|symantec|ccsvchst|mcafee|mcshield|avast|avg|eset|egui|ekrn|trend|sophos|f-secure|cmc|bkav"
    $svcs = @()
    try { $svcs = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue) } catch {}
    if ($svcs.Count -eq 0) { try { $svcs = @(Get-WmiObject Win32_Service -ErrorAction SilentlyContinue) } catch {} }
    foreach ($svc in $svcs) {
        if ($svc.Name -match $svcPattern -or $svc.DisplayName -match $svcPattern) {
            $dsTatCaPhienBan += [PSCustomObject]@{ 
                TenDayDu = $svc.DisplayName; 
                Ver = "Khong ro"; 
                Bit = "Khong ro"; 
                Nguon = "Service"; 
                DuongDan = "";
                TrangThai = $svc.State;
                Diem = (Tinh-DiemTen -Ten $svc.DisplayName)
            }
        }
    }

    # PP3: Process
    $procPattern = "avp|avpui|bdagent|bdservicehost|ccsvchst|mcshield|mcapexe|avastsvc|avastui|avg|egui|ekrn|MsMpEng|SecurityHealthService|Sense|MsSense"
    try {
        $procs = Get-Process -ErrorAction SilentlyContinue
        foreach ($proc in $procs) {
            if ($proc.ProcessName -match $procPattern) {
                # Lay duong dan file de xac dinh kien truc
                $duongDanProc = ""
                try { $duongDanProc = $proc.Path } catch {}
                $bitProc = XacDinh-KienTrucTuDuongDan -DuongDan $duongDanProc
                
                # Lay phien ban tu file
                $verProc = "Khong ro"
                try {
                    if ($duongDanProc -and (Test-Path $duongDanProc)) {
                        $fi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($duongDanProc)
                        if ($fi.ProductVersion) { $verProc = $fi.ProductVersion }
                    }
                } catch {}
                
                $dsTatCaPhienBan += [PSCustomObject]@{ 
                    TenDayDu = $proc.ProcessName; 
                    Ver = $verProc; 
                    Bit = $bitProc; 
                    Nguon = "Process"; 
                    DuongDan = $duongDanProc;
                    TrangThai = "Dang chay";
                    Diem = (Tinh-DiemTen -Ten $proc.ProcessName)
                }
            }
        }
    } catch {}

    # === NHOM THEO HANG SAN XUAT ===
    # $dsNhom: Hash - Key = TenHang, Value = Array cac phien ban
    $dsNhom = @{}
    foreach ($pb in $dsTatCaPhienBan) {
        $tenHang = ""
        foreach ($k in $avKeys) {
            if ($pb.TenDayDu -match $k) { $tenHang = $k; break }
        }
        if (-not $tenHang) { continue }
        
        if (-not $dsNhom.ContainsKey($tenHang)) {
            $dsNhom[$tenHang] = @()
        }
        $dsNhom[$tenHang] += $pb
    }

    # Bo qua Windows Defender
    $dsNhom.Remove("Windows Defender")

    # === CHON SAN PHAM CHINH CHO MOI HANG ===
    # $dsKetQua: Hash - Key = TenHang, Value = [PSCustomObject]@{ TenHang, SanPhamChinh, Ver, Bit, TrangThai, TatCaPhienBan }
    $dsKetQua = @{}
    
    foreach ($hang in $dsNhom.Keys) {
        $cacPhienBan = $dsNhom[$hang]
        
        # Sap xep: Diem cao -> truoc, Ver moi -> truoc, Dang chay -> truoc
        $cacPhienBanSorted = $cacPhienBan | Sort-Object -Property {
            $_.Diem
        }, {
            # So sanh phien ban (uu tien cao hon)
            try {
                $v = $_.Ver -replace "[^0-9.]", ""
                if ($v) { return [version]$v } else { return [version]"0.0" }
            } catch { return [version]"0.0" }
        }, {
            # Uu tien dang chay
            if ($_.TrangThai -eq "Running" -or $_.TrangThai -eq "Dang chay") { return 1 } else { return 0 }
        } -Descending
        
        $spChinh = $cacPhienBanSorted | Select-Object -First 1
        
        # Loai bo trung lap phien ban (cung TenDayDu + Ver + Bit)
        $pbUnique = @()
        $daCo = @{}
        foreach ($pb in $cacPhienBanSorted) {
            $key = "$($pb.TenDayDu)|$($pb.Ver)|$($pb.Bit)"
            if (-not $daCo.ContainsKey($key)) {
                $daCo[$key] = $true
                $pbUnique += $pb
            }
        }
        
        $dsKetQua[$hang] = [PSCustomObject]@{
            TenHang = $hang
            SanPhamChinh = $spChinh.TenDayDu
            Ver = $spChinh.Ver
            Bit = $spChinh.Bit
            TrangThai = $spChinh.TrangThai
            TatCaPhienBan = $pbUnique
        }
    }

    # === HIEN THI KET QUA CUOI CUNG ===
    if ($dsKetQua.Count -gt 0) {
        Ghi-BaoCao "Phan mem bao mat thu 3 da phat hien:"
        Ghi-BaoCao ""
        
        foreach ($hang in ($dsKetQua.Keys | Sort-Object)) {
            $kq = $dsKetQua[$hang]
            
			# --- HIEN THI SAN PHAM CHINH DA CHON ---
            Ghi-BaoCao "    -> San pham chinh: $($kq.SanPhamChinh)"
            Ghi-BaoCao "       Phien ban     : $($kq.Ver)"
            Ghi-BaoCao "       Kien truc     : $($kq.Bit)"
            Ghi-BaoCao "       Trang thai    : $($kq.TrangThai)"
            
            if ($script:Debug) {
                $nguonList = ($kq.TatCaPhienBan | ForEach-Object { $_.Nguon } | Sort-Object -Unique) -join ", "
                Ghi-BaoCao "       Nguon phat hien: $nguonList"
            }
			
            # --- HIEN THI TAT CA PHIEN BAN CUA HANG NAY ---
			Ghi-BaoCao ""
            Ghi-BaoCao "    -> Gom :  [$($kq.TenHang)]"
            
            $stt = 1
            foreach ($pb in $kq.TatCaPhienBan) {
                $dauChon = if ($pb.TenDayDu -eq $kq.SanPhamChinh -and $pb.Ver -eq $kq.Ver -and $pb.Bit -eq $kq.Bit) { ">>>" } else { "   " }
                $verHienThi = if ($pb.Ver -and $pb.Ver -ne "Khong ro") { $pb.Ver } else { "Khong ro" }
                $bitHienThi = if ($pb.Bit -and $pb.Bit -ne "Khong ro") { $pb.Bit } else { "Khong ro" }
                Ghi-BaoCao "    $dauChon ($stt) $($pb.TenDayDu) ($verHienThi) ($bitHienThi)"
                $stt++
            }
            
            Ghi-BaoCao ""
        }
    } else {
        Ghi-BaoCao "Khong phat hien phan mem bao mat thu 3"
        Ghi-BaoCao ""
    }

    # --- DANH GIA ---
    Ghi-BaoCao "--- DANH GIA HE THONG BAO MAT ---"
    $coThu3 = $dsKetQua.Count -gt 0
    if ($defOn -and $coThu3) {
        Ghi-BaoCao "[!] CANH BAO: Windows Defender DANG BAT dong thoi voi AV thu 3!"
        Ghi-BaoCao "    -> Co the gay CHAM MAY va XUNG DOT"
        Ghi-BaoCao "    -> Khuyen nghi: Tat Windows Defender, chi giu AV thu 3"
    } elseif (-not $defOn -and -not $coThu3) {
        Ghi-BaoCao "[!] NGUY HIEM: May KHONG CO bao mat nao dang hoat dong!"
        Ghi-BaoCao "    -> Bat Windows Defender NGAY hoac cai AV ngay"
    } else {
        Ghi-BaoCao "[OK] He thong bao mat on dinh"
        if ($defOn) { Ghi-BaoCao "    -> Windows Defender dang bao ve" }
        else { Ghi-BaoCao "    -> Phan mem bao mat thu 3 dang hoat dong" }
    }
    Ghi-BaoCao ""
}

# ==========================================
# HAM 4: THONG TIN MAY TINH
# ==========================================
function HienThi-ThongTinMay {
    Ghi-BaoCao "========================================"
    Ghi-BaoCao "4. THONG TIN MAY TINH"
    Ghi-BaoCao "========================================"
    Ghi-BaoCao ""

    $may = Thu-PhuongPhap -DS @(
        @{ Ten = "CIM ComputerSystem"; Script = { Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue } },
        @{ Ten = "WMI ComputerSystem"; Script = { Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue } }
    )
    $bios = Thu-PhuongPhap -DS @(
        @{ Ten = "CIM BIOS"; Script = { Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue } },
        @{ Ten = "WMI BIOS"; Script = { Get-WmiObject Win32_BIOS -ErrorAction SilentlyContinue } }
    )
    $main = Thu-PhuongPhap -DS @(
        @{ Ten = "CIM BaseBoard"; Script = { Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue } },
        @{ Ten = "WMI BaseBoard"; Script = { Get-WmiObject Win32_BaseBoard -ErrorAction SilentlyContinue } }
    )

    $tenMay = if ($may) { $may.Name } else { $env:COMPUTERNAME }
    $hang = if ($may) { $may.Manufacturer } else { "Khong ro" }
    $model = if ($may) { $may.Model } else { "Khong ro" }

    # Nam san xuat
    $namSX = "Khong xac dinh"; $ngaySX = $null
    if ($bios -and $bios.ReleaseDate) {
        try { $d = [Management.ManagementDateTimeConverter]::ToDateTime($bios.ReleaseDate); if ($d.Year -ge 1980) { $ngaySX = $d; $namSX = $d.Year } } catch {}
    }
    if ($namSX -eq "Khong xac dinh") {
        try {
            $r = Get-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" -ErrorAction SilentlyContinue
            if ($r.BIOSReleaseDate) {
                $d = $null; foreach ($f in @("MM/dd/yyyy", "yyyy-MM-dd", "dd/MM/yyyy")) { try { $d = [DateTime]::ParseExact($r.BIOSReleaseDate.Trim(), $f, $null); break } catch {} }
                if (-not $d) { try { $d = [DateTime]::Parse($r.BIOSReleaseDate.Trim()) } catch {} }
                if ($d -and $d.Year -ge 1980) { $ngaySX = $d; $namSX = $d.Year }
            }
        } catch {}
    }
    $ngaySXStr = if ($ngaySX) { "(ngay: " + $ngaySX.ToString("dd/MM/yyyy") + ")" } else { "" }

    # --- THONG TIN CHUNG ---
    Ghi-BaoCao "--- THONG TIN CHUNG ---"
    Ghi-BaoCao "Ten may         : $tenMay"
    Ghi-BaoCao "Hang san xuat   : $hang"
    Ghi-BaoCao "So hieu/Model   : $model"
    Ghi-BaoCao "Nam san xuat    : $namSX $ngaySXStr"
    $serialStr = if ($bios) { $bios.SerialNumber } else { "Khong co" }
    Ghi-BaoCao "Serial/Service  : $serialStr"
    $biosVerStr = if ($bios) { $bios.SMBIOSBIOSVersion } else { "Khong co" }
    Ghi-BaoCao "BIOS Version    : $biosVerStr"
    $mainStr = if ($main) { "$($main.Manufacturer) $($main.Product)" } else { "Khong ro" }
    Ghi-BaoCao "Mainboard       : $mainStr"
    Ghi-BaoCao ""

    # --- PHAN CUNG ---
    Ghi-BaoCao "--- THONG TIN PHAN CUNG ---"

    # CPU
    $cpu = Thu-PhuongPhap -DS @(
        @{ Ten = "CIM Processor"; Script = { Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1 } },
        @{ Ten = "WMI Processor"; Script = { Get-WmiObject Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1 } }
    )
    if ($cpu) {
        Ghi-BaoCao "CPU: $($cpu.Name)"
        Ghi-BaoCao "    So nhan: $($cpu.NumberOfCores) | Logic: $($cpu.NumberOfLogicalProcessors) | Toc do: $($cpu.MaxClockSpeed) MHz"
    } else { Ghi-BaoCao "CPU: Khong lay duoc thong tin" }
    Ghi-BaoCao ""

    # GPU
    $gpu = @(); $daGPU = @{}
    try {
        $g = @(); try { $g = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue) } catch {}
        if ($g.Count -eq 0) { try { $g = @(Get-WmiObject Win32_VideoController -ErrorAction SilentlyContinue) } catch {} }
        foreach ($i in $g) {
            if (-not $i.Name) { continue }
            $n = $i.Name.Trim(); if ($daGPU.ContainsKey($n.ToLower())) { continue }
            $daGPU[$n.ToLower()] = $true
            $vram = $i.AdapterRAM; if ($vram -lt 0) { $vram = [uint32]$vram }
            $vramGB = if ($vram -gt 0) { [math]::Round($vram / 1GB, 2) } else { 0 }
            $gc = if ($n -match "Basic|Standard VGA|Microsoft Basic") { " (Driver chua day du)" } else { "" }
            $gpu += [PSCustomObject]@{ Ten = $n; VRAM = $vramGB; Driver = $i.DriverVersion; GhiChu = $gc }
        }
    } catch {}
    if ($gpu.Count -eq 0) {
        try {
            $rp = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E968-E325-11CE-BFC1-08002BE10318}"
            if (Test-Path $rp) {
                Get-ChildItem $rp -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
                    try {
                        $pr = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                        if ($pr.DriverDesc) {
                            $n = $pr.DriverDesc.Trim(); if ($daGPU.ContainsKey($n.ToLower())) { return }
                            $daGPU[$n.ToLower()] = $true
                            $v = if ($pr.QTVideoRam) { [math]::Round($pr.QTVideoRam / 1MB, 2) } else { 0 }
                            $gpu += [PSCustomObject]@{ Ten = $n; VRAM = $v; Driver = $pr.DriverVersion; GhiChu = "" }
                        }
                    } catch {}
                }
            }
        } catch {}
    }
    if ($gpu.Count -gt 0) {
        Ghi-BaoCao "Card do hoa:"
        foreach ($g in $gpu) { Ghi-BaoCao "  + $($g.Ten) | VRAM: $($g.VRAM) GB | Driver: $($g.Driver)$($g.GhiChu)" }
    } else { Ghi-BaoCao "Card do hoa: Khong phat hien" }
    Ghi-BaoCao ""

    # RAM
    $ram = @(); try { $ram = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue) } catch {}
    if ($ram.Count -eq 0) { try { $ram = @(Get-WmiObject Win32_PhysicalMemory -ErrorAction SilentlyContinue) } catch {} }
    $ramArr = Thu-PhuongPhap -DS @(
        @{ Ten = "CIM RAM Array"; Script = { Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue | Select-Object -First 1 } },
        @{ Ten = "WMI RAM Array"; Script = { Get-WmiObject Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue | Select-Object -First 1 } }
    )
    $tongRAM = 0
    Ghi-BaoCao "RAM:"
    if ($ram.Count -gt 0) {
        foreach ($m in $ram) {
            $sz = [math]::Round($m.Capacity / 1GB, 2)
            $tongRAM += $sz
            $mf = if ($m.Manufacturer) { $m.Manufacturer } else { "Khong ro" }
            $pt = if ($m.PartNumber) { $m.PartNumber.Trim() } else { "Khong ro" }
            $lc = if ($m.DeviceLocator) { $m.DeviceLocator } else { "Khong ro" }
            Ghi-BaoCao "  [$lc] $mf $pt | $($sz) GB | Bus: $($m.Speed) MHz"
        }
        $ts = if ($ramArr) { $ramArr.MemoryDevices } else { 0 }
        if ($ts -gt 0) { Ghi-BaoCao "Tong slot: $ts | Da dung: $($ram.Count) | Con trong: $($ts - $ram.Count)" }
    } else { Ghi-BaoCao "  Khong lay duoc thong tin RAM" }
    Ghi-BaoCao "TONG CONG RAM   : $tongRAM GB"
    Ghi-BaoCao ""

    # O cung
    Ghi-BaoCao "O dia:"
    $disks = @(); try { $disks = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue) } catch {}
    if ($disks.Count -eq 0) { try { $disks = @(Get-WmiObject Win32_DiskDrive -ErrorAction SilentlyContinue) } catch {} }
    $pd = $null; try { $pd = Get-CimInstance -Namespace "root\Microsoft\Windows\Storage" -ClassName MSFT_PhysicalDisk -ErrorAction SilentlyContinue } catch {}
    $tongODia = 0
    $soODia = 0
    foreach ($d in $disks) {
        $sz = [math]::Round($d.Size / 1GB, 2)
        $tongODia += $sz
        $soODia++
        $md = $d.Model.Trim()
        $loai = "Khong xac dinh"
        if ($pd) {
            $p = $pd | Where-Object { $_.DeviceId -eq $d.Index }
            if ($p) { switch ($p.MediaType) { 3 { $loai = "HDD" }; 4 { $loai = "SSD" }; 5 { $loai = "SCM" } } }
        }
        if ($loai -eq "Khong xac dinh") {
            if ($md -match "SSD|Solid State|NVMe") { $loai = "SSD (du doan)" }
            elseif ($md -match "WDC|WD|Seagate|Toshiba|Hitachi") { $loai = "HDD (du doan)" }
        }
        Ghi-BaoCao "  + $md | $sz GB | $loai | $($d.InterfaceType)"
    }
    Ghi-BaoCao "SO LUONG O DIA  : $soODia"
    Ghi-BaoCao "TONG DUNG LUONG : $tongODia GB"
    Ghi-BaoCao ""

    # Pin
    Ghi-BaoCao "Pin:"
    $pin = Thu-PhuongPhap -DS @(
        @{ Ten = "CIM Battery"; Script = { Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1 } },
        @{ Ten = "WMI Battery"; Script = { Get-WmiObject Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1 } }
    )
    if ($pin) {
        $tg = if ($pin.EstimatedRunTime -and $pin.EstimatedRunTime -ne 71582788) {
            $h = [math]::Floor($pin.EstimatedRunTime / 60); $m = $pin.EstimatedRunTime % 60; "$h gio $m phut"
        } else { "Khong xac dinh (dang cam sac)" }
        Ghi-BaoCao "  + Ten: $($pin.Name) | Trang thai: $($pin.Status) | Con: $($pin.EstimatedChargeRemaining)% | Thoi gian: $tg"
        Ghi-BaoCao "  + Ghi chu: Chay 'powercfg /batteryreport' de xem chi tiet"
    } else { Ghi-BaoCao "  + Khong phat hien pin (co the la PC de ban)" }
    Ghi-BaoCao ""

    # --- PHAN MEM & MANG ---
    Ghi-BaoCao "--- THONG TIN PHAN MEM & MANG ---"
    $os2 = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
    $osBit = if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" }
    Ghi-BaoCao "He dieu hanh    : $($os2.ProductName) $osBit"

    $bl = "Khong ho tro"
    try {
        $bv = Get-BitLockerVolume -MountPoint C: -ErrorAction SilentlyContinue
        if ($bv) { $bl = if ($bv.ProtectionStatus -eq "On") { "BAT" } else { "TAT" } }
        else { $bs = manage-bde -status C: 2>$null | Select-String "Protection Status"; if ($bs) { if ($bs -match "On") { $bl = "BAT" } elseif ($bs -match "Off") { $bl = "TAT" } } }
    } catch {}
    Ghi-BaoCao "Bitlocker (C:)  : $bl"
    Ghi-BaoCao "Ten PC          : $tenMay"
    Ghi-BaoCao "User dang chay  : $($env:USERNAME)"

    $nets = @(); try { $nets = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue) } catch {}
    if ($nets.Count -eq 0) { try { $nets = @(Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue) } catch {} }
    foreach ($n in $nets) {
        $ip = ($n.IPAddress | Where-Object { $_ -match '\.' }) | Select-Object -First 1
        Ghi-BaoCao "MAC             : $($n.MACAddress)"
        Ghi-BaoCao "IP              : $ip"
    }

    # Mui gio
    $tz = "Khong lay duoc"; $tzMa = "Khong xac dinh"
    try { $t = Get-TimeZone -ErrorAction Stop; if ($t) { $tz = "$($t.DisplayName) ($($t.Id))"; $tzMa = $t.Id } } catch {}
    if ($tz -eq "Khong lay duoc") {
        try {
            $r = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" -ErrorAction Stop
            if ($r.TimeZoneKeyName) {
                $tzMa = $r.TimeZoneKeyName
                try { $i = [System.TimeZoneInfo]::FindSystemTimeZoneById($tzMa); $tz = "$($i.DisplayName) ($tzMa)" } catch { $tz = $tzMa }
            } elseif ($r.StandardName) { $tz = $r.StandardName; $tzMa = $r.StandardName }
        } catch {}
    }
    Ghi-BaoCao "Mui gio         : $tz"
    if ($tzMa -ne "Khong xac dinh" -and $tzMa -ne $tz) { Ghi-BaoCao "Ma mui gio      : $tzMa" }

    try { $sl = Get-WinSystemLocale -ErrorAction SilentlyContinue; if ($sl) { Ghi-BaoCao "Ngon ngu he thong: $($sl.DisplayName) ($($sl.Name))" } } catch { Ghi-BaoCao "Ngon ngu he thong: Khong lay duoc" }
    try { $cl = Get-Culture -ErrorAction SilentlyContinue; if ($cl) { Ghi-BaoCao "Region format   : $($cl.Name) | $($cl.DisplayName)" } } catch {}
    try { $lc = Get-WinHomeLocation -ErrorAction SilentlyContinue; if ($lc) { Ghi-BaoCao "Location (GeoID): $($lc.HomeLocation)" } } catch { Ghi-BaoCao "Location        : Khong lay duoc" }
    Ghi-BaoCao ""

    # Goi y driver
    Ghi-BaoCao "--- GOI Y TIM DRIVER ---"
    $mh = if ($main) { $main.Manufacturer } else { "Unknown" }
    $mm = if ($main) { $main.Product } else { "Unknown" }
    Ghi-BaoCao "Tim driver cho: $mh $mm"
    Ghi-BaoCao "Link tim kiem : https://www.google.com/search?q=driver+$mh+$mm+windows+10"
    $links = @{ "ASUS" = "https://www.asus.com/support"; "Gigabyte" = "https://www.gigabyte.com/Support"; "MSI" = "https://www.msi.com/support"; "ASRock" = "https://www.asrock.com/support/index.asp"; "Dell" = "https://www.dell.com/support/home/drivers"; "HP" = "https://support.hp.com"; "Hewlett" = "https://support.hp.com"; "Lenovo" = "https://support.lenovo.com" }
    foreach ($k in $links.Keys) { if ($mh -match $k) { Ghi-BaoCao "Trang chinh hang: $($links[$k])"; break } }
    Ghi-BaoCao ""
}

# ==========================================
# MENU VA CHUONG TRINH CHINH
# ==========================================
function HienThi-Menu {
    Clear-Host
    Write-Host "========================================"
    Write-Host "  CONG CU KIEM TRA HE THONG"
    Write-Host "  Windows 10/11 | PowerShell 5.1+"
    if ($script:Debug) { Write-Host "  [CHE DO CHI TIET - DEBUG]" -ForegroundColor Yellow }
    Write-Host "========================================"
    Write-Host "  1. Kiem tra ban quyen Windows"
    Write-Host "  2. Kiem tra ban quyen Office"
    Write-Host "  3. Kiem tra phan mem bao mat"
    Write-Host "  4. Hien thi thong tin may tinh"
    Write-Host "  5. Hien thi TAT CA"
    Write-Host "  6. Xuat TAT CA ra Desktop (TXT)"
    Write-Host "  7. Xuat Thong tin may ra Desktop (TXT)"
    Write-Host "  0. Thoat"
    Write-Host "========================================"
}

function Xuat-File {
    $fn = "BC_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $fp = Join-Path ([Environment]::GetFolderPath("Desktop")) $fn
    
    # === THÊM HEADER VÀO ĐẦU MẢNG BÁO CÁO ===
    $header = @(
        "========================================"
        "  BAO CAO KIEM TRA HE THONG"
        "========================================"
        "Ten may    : $($env:COMPUTERNAME)"
        "Thoi gian  : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
        "Nguoi dung : $($env:USERNAME)"
        "========================================"
        ""
    )
    
    # Gộp header + nội dung báo cáo
    $noiDungXuat = $header + $script:BaoCao
    
    try {
        $noiDungXuat | Out-File -FilePath $fp -Encoding utf8 -ErrorAction Stop
        Write-Host "`nDa xuat bao cao thanh cong:" -ForegroundColor Green
        Write-Host $fp -ForegroundColor Green
    } catch { Write-Host "`nLoi xuat file: $_" -ForegroundColor Red }
}

do {
    HienThi-Menu
    $lc = Read-Host "Chon chuc nang (0-7)"
    switch ($lc) {
        "1" { $script:BaoCao = @(); KiemTra-BanQuyenWindows; Ghi-BaoCao "========================================"; Ghi-BaoCao "KET THUC MUC 1"; Ghi-BaoCao "========================================"; Pause }
        "2" { $script:BaoCao = @(); KiemTra-BanQuyenOffice; Ghi-BaoCao "========================================"; Ghi-BaoCao "KET THUC MUC 2"; Ghi-BaoCao "========================================"; Pause }
        "3" { $script:BaoCao = @(); KiemTra-BaoMat; Ghi-BaoCao "========================================"; Ghi-BaoCao "KET THUC MUC 3"; Ghi-BaoCao "========================================"; Pause }
        "4" { $script:BaoCao = @(); HienThi-ThongTinMay; Ghi-BaoCao "========================================"; Ghi-BaoCao "KET THUC MUC 4"; Ghi-BaoCao "========================================"; Pause }
        "5" { $script:BaoCao = @(); KiemTra-BanQuyenWindows; KiemTra-BanQuyenOffice; KiemTra-BaoMat; HienThi-ThongTinMay; Ghi-BaoCao "========================================"; Ghi-BaoCao "KET THUC TONG HOP"; Ghi-BaoCao "========================================"; Pause }
        "6" { $script:BaoCao = @(); KiemTra-BanQuyenWindows; KiemTra-BanQuyenOffice; KiemTra-BaoMat; HienThi-ThongTinMay; Ghi-BaoCao "========================================"; Ghi-BaoCao "KET THUC TONG HOP"; Ghi-BaoCao "========================================"; Xuat-File; Pause }
        "7" { $script:BaoCao = @(); HienThi-ThongTinMay; Ghi-BaoCao "========================================"; Ghi-BaoCao "KET THUC XUAT TT MAY"; Ghi-BaoCao "========================================"; Xuat-File; Pause }
        "0" { Write-Host "Tam biet!"; exit }
        default { Write-Host "Lua chon khong hop le!"; Start-Sleep -Seconds 2 }
    }
} while ($true)
