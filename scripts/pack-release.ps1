<#
.SYNOPSIS
    Собирает архив для раздачи: программа, короткое описание и контрольная сумма.

.DESCRIPTION
    Раздаётся не голый .exe, а архив: так у человека рядом с программой оказывается
    объяснение, откуда она и что с ней делать, а контрольная сумма позволяет сверить
    скачанное с тем, что опубликовано.

    Перед упаковкой проверяется, что ключ приложения не лежит в файле открытым текстом —
    сборка с открытым ключом раздаче не подлежит.

.EXAMPLE
    powershell -File scripts\pack-release.ps1 -Exe D:\Build\TelegramTeam\tdesktop\out\Telegram\Release\TelegramTeam.exe
#>
[CmdletBinding()]
param(
    [string]$Exe = 'D:\Build\TelegramTeam\tdesktop\out\Telegram\Release\TelegramTeam.exe',
    [string]$OutDir = 'G:\Build\TelegramTeam\artifacts',
    [string]$ApiHash = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Exe)) { throw "Программа не найдена: $Exe" }

$version = (Get-Item $Exe).VersionInfo.ProductVersion
if ([string]::IsNullOrWhiteSpace($version)) { $version = (Get-Item $Exe).VersionInfo.FileVersion }
$version = ($version -split '\s')[0]
# У ресурса версии четыре числа (7.1.1.0), а людям привычны три — лишний ноль в имени
# файла только путает при сверке с версией в самом клиенте.
if ($version -match '^(\d+\.\d+\.\d+)\.0$') { $version = $Matches[1] }
Write-Host "Версия программы: $version" -ForegroundColor Cyan

# Ключ приложения в раздаваемом файле открытым текстом лежать не должен: он вынимается
# оттуда поиском строк, а дальше ограничения Telegram прилетают нашим же пользователям.
if ($ApiHash) {
    $bytes = [System.IO.File]::ReadAllBytes($Exe)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    if ($text.Contains($ApiHash)) {
        throw 'Ключ приложения найден в файле открытым текстом — раздавать такую сборку нельзя.'
    }
    Write-Host 'Ключ приложения в файле открытым текстом не найден.' -ForegroundColor Green
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$stage = Join-Path $OutDir "stage-$version"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null

Copy-Item $Exe (Join-Path $stage 'TelegramTeam.exe')

$readme = @"
Telegram Team $version
======================

Своя сборка Telegram для Windows из оригинальных исходников. Чем отличается:
- аккаунтов до пятидесяти вместо трёх;
- ссылка умеет открыть нужное сообщение сразу под нужным аккаунтом;
- закрепление чатов не режется подпиской;
- администратор канала с запретом копирования может пересылать и сохранять
  свои посты;
- код подтверждения копируется прямо из уведомления: наведите на уведомление,
  рядом с "Ответить" появится кнопка с кодом.

Как пользоваться
----------------
1. Распакуйте папку куда угодно - например, в C:\Programs\TelegramTeam.
2. Запустите TelegramTeam.exe. Программа портативная: данные аккаунтов она
   держит рядом с собой, в папке tdata.
3. Вход - только по QR-коду: в обычном Telegram на телефоне откройте
   Настройки -> Устройства -> Подключить устройство и наведите камеру.

Предупреждение Windows при первом запуске
-----------------------------------------
Программа не подписана сертификатом издателя, поэтому SmartScreen покажет окно
"Windows защитила ваш компьютер". Это про отсутствие подписи, а не про вирус:
нажмите "Подробнее" -> "Выполнить в любом случае". Убедиться, что скачан именно
опубликованный файл, можно по контрольной сумме из файла .sha256 рядом с архивом.

Обновление
----------
Заменить TelegramTeam.exe на новый. Папку tdata не трогать - в ней аккаунты.

Исходный код и описание всех правок
-----------------------------------
https://github.com/upsoftt/telegram-team
https://team.bozex.ru

Telegram Desktop распространяется под лицензией GPLv3. Это не официальный
Telegram, проект не связан с Telegram FZ-LLC.
"@
[System.IO.File]::WriteAllText((Join-Path $stage 'ЧИТАТЬ.txt'), $readme, (New-Object System.Text.UTF8Encoding($true)))

$zip = Join-Path $OutDir "TelegramTeam-$version-windows-x64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
Remove-Item $stage -Recurse -Force

$sha = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
$shaFile = "$zip.sha256"
[System.IO.File]::WriteAllText($shaFile, "$sha  $(Split-Path $zip -Leaf)`n", (New-Object System.Text.UTF8Encoding($false)))

$sizeMb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "Готово: $zip ($sizeMb МБ)" -ForegroundColor Green
Write-Host "SHA-256: $sha"
