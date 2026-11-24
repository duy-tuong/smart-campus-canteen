<#
.SYNOPSIS
    Làm mới dữ liệu demo Smart Canteen — chạy trước mỗi buổi tập dượt / bảo vệ.

.DESCRIPTION
    Backend phải đang chạy ở môi trường Development. Script gọi lần lượt:
      1. GET  /api/health                     kiểm tra backend
      2. POST /api/dev/accounts               tài khoản demo: mở khóa, đúng vai trò, đúng hồ sơ
      3. POST /api/dev/demo-reset             xóa đơn chạy thử + thông báo, khôi phục thực đơn, gia hạn voucher
      4. POST /api/dev/seed-history?reset=... sinh lại N ngày lịch sử, kết thúc ở HÔM QUA (thống kê luôn có số liệu)
      5. POST /api/dev/seed-images            gắn ảnh món mẫu
      6. GET  /api/canteen/info               cảnh báo nếu căn-tin đang ngoài giờ nhận đơn
    Tài khoản, yêu thích và các món / danh mục trong menu.json được giữ nguyên.

    Giỏ hàng và lịch sử đơn offline nằm trong SQLite TRÊN ĐIỆN THOẠI, server không xóa được:
    dùng -ClearApp để xóa dữ liệu app trên máy ảo / điện thoại đang cắm cáp (adb).

.PARAMETER BaseUrl
    Địa chỉ backend. Mặc định http://localhost:5265.

.PARAMETER Days
    Số ngày lịch sử cần sinh (1–90). Mặc định 30.

.PARAMETER ClearApp
    Xóa dữ liệu app trên thiết bị adb đang kết nối (đăng xuất, xóa giỏ hàng và hóa đơn lưu trên máy,
    đưa giao diện và địa chỉ máy chủ về mặc định). Điện thoại thật sẽ phải nhập lại IP máy chủ.

.EXAMPLE
    .\scripts\demo-reset.ps1

.EXAMPLE
    .\scripts\demo-reset.ps1 -ClearApp
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:5265',
    [ValidateRange(1, 90)][int]$Days = 30,
    [switch]$ClearApp
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$BaseUrl = $BaseUrl.TrimEnd('/')
$AppId = 'vn.edu.smartcanteen.app'
$vi = [System.Globalization.CultureInfo]::GetCultureInfo('vi-VN')

function Write-Step([int]$n, [string]$text) { Write-Host "`n[$n/6] $text" -ForegroundColor Cyan }
function Write-Ok([string]$text) { Write-Host "      $text" -ForegroundColor Green }
function Write-Note([string]$text) { Write-Host "      $text" -ForegroundColor Yellow }
function Format-Money([long]$amount) { $amount.ToString('N0', $vi) + 'đ' }

function Invoke-Api([string]$Method, [string]$Path) {
    try {
        return Invoke-RestMethod -Method $Method -Uri "$BaseUrl$Path" -TimeoutSec 300
    }
    catch {
        $detail = $_.ErrorDetails.Message
        if ($detail) { try { $detail = ($detail | ConvertFrom-Json).detail } catch { } }
        throw "$Method $Path thất bại: $($_.Exception.Message) $detail"
    }
}

Write-Host "Làm mới dữ liệu demo — $BaseUrl" -ForegroundColor White

# 1. Backend
Write-Step 1 'Kiểm tra backend'
try {
    Invoke-RestMethod -Uri "$BaseUrl/api/health" -TimeoutSec 10 | Out-Null
    Write-Ok 'Backend đang chạy.'
}
catch {
    Write-Host "      Không kết nối được $BaseUrl." -ForegroundColor Red
    Write-Host '      Hãy chạy backend trước:  cd backend; dotnet run --project src/CanteenApi --launch-profile http' -ForegroundColor Red
    exit 1
}

try {
    # 2. Tài khoản demo
    Write-Step 2 'Tài khoản demo'
    # PowerShell 5.1 trả mảng JSON thành MỘT phần tử là cả mảng → duỗi ra bằng pipeline.
    $accounts = @(Invoke-Api POST '/api/dev/accounts' | ForEach-Object { $_ })
    foreach ($a in $accounts) { Write-Ok ("{0,-24} {1}" -f $a.email, $a.role) }

    # 3. Dọn đơn chạy thử, khôi phục thực đơn và voucher
    Write-Step 3 'Dọn đơn chạy thử, khôi phục thực đơn và voucher'
    $r = Invoke-Api POST '/api/dev/demo-reset'
    Write-Ok "Đã xóa $($r.ordersDeleted) đơn chạy thử, $($r.reviewsDeleted) đánh giá kèm theo, $($r.notificationsDeleted) thông báo."
    Write-Ok "Thực đơn: khôi phục $($r.foodsRestored) món / $($r.categoriesRestored) danh mục, ẩn $($r.foodsHidden) món / $($r.categoriesHidden) danh mục thêm khi tập."
    Write-Ok "Voucher: gia hạn $($r.vouchersRefreshed) mã mẫu từ hôm nay, gỡ $($r.vouchersRemoved) mã tạo thêm."

    # 4. Lịch sử cho thống kê
    Write-Step 4 "Sinh lại $Days ngày lịch sử"
    $h = Invoke-Api POST "/api/dev/seed-history?days=$Days&reset=true"
    Write-Ok "$($h.from) → $($h.to): $($h.orders) đơn ($($h.completed) hoàn thành, $($h.cancelled) hủy), doanh thu $(Format-Money $h.revenue)."
    Write-Ok "$($h.reviews) đánh giá ($($h.replies) có trả lời), $($h.virtualStudents) sinh viên ảo."

    # 5. Ảnh món
    Write-Step 5 'Ảnh món mẫu'
    $img = Invoke-Api POST '/api/dev/seed-images'
    Write-Ok "Gắn ảnh $($img.updated) món, $($img.skipped) món đã có ảnh."
    if ($img.missingFiles.Count -gt 0) { Write-Note "Thiếu file ảnh: $($img.missingFiles -join ', ')" }

    # 6. Giờ mở cửa
    Write-Step 6 'Giờ nhận đơn'
    $info = Invoke-Api GET '/api/canteen/info'
    if ($info.isOpen) {
        Write-Ok "Căn-tin đang mở ($($info.openTime)–$($info.closeTime)), đặt món được ngay."
    }
    else {
        Write-Note "Căn-tin đang NGOÀI giờ nhận đơn ($($info.openTime)–$($info.closeTime)) → sinh viên sẽ không đặt được món."
        Write-Note 'Nếu demo ngoài giờ, chạy lại backend với:  $env:Canteen__CloseTime="23:59"; dotnet run --project src/CanteenApi --launch-profile http'
    }
}
catch {
    Write-Host "`n$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Dữ liệu trên điện thoại (tùy chọn)
if ($ClearApp) {
    Write-Host "`n[+] Xóa dữ liệu app trên thiết bị (adb)" -ForegroundColor Cyan
    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        Write-Note 'Không tìm thấy adb trong PATH — bỏ qua.'
    }
    else {
        $devices = @(adb devices | Select-String -Pattern "`tdevice$")
        if ($devices.Count -eq 0) {
            Write-Note 'Không có thiết bị nào đang kết nối — bỏ qua.'
        }
        else {
            foreach ($d in $devices) {
                $serial = ($d.Line -split "`t")[0]
                $out = adb -s $serial shell pm clear $AppId 2>&1
                Write-Ok "${serial}: $out"
            }
        }
    }
}

Write-Host "`nXong. Trước khi demo:" -ForegroundColor White
Write-Host '  - Trên app: kéo để làm mới (hoặc đăng xuất / đăng nhập lại) để bỏ dữ liệu cũ đang hiển thị.'
if (-not $ClearApp) {
    Write-Host '  - Giỏ hàng / hóa đơn lưu trên máy không bị xóa. Muốn xóa trên máy ảo: chạy lại với -ClearApp.'
}
Write-Host '  - Mật khẩu chung các tài khoản demo: Canteen@123'
