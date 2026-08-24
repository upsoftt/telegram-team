<#
.SYNOPSIS
    Собирает Telegram Team из оригинальных исходников Telegram Desktop.

.DESCRIPTION
    Сборка нужна для двух вещей, которых нет в официальном клиенте: больше шести
    аккаунтов и открытие сообщения под нужным аккаунтом (ссылки
    tgteam://…&account=<user id>). Исходники берутся из telegramdesktop/tdesktop
    нужного тега, поверх накатываются патчи из patches/desktop.

    Ключ приложения задаётся переменными окружения TELEGRAM_API_ID и
    TELEGRAM_API_HASH — своя пара берётся на my.telegram.org.

    Этапы включаются по отдельности, потому что подготовка библиотек идёт часы,
    а пересборка после правки — минуты.

.EXAMPLE
    powershell -File scripts\build.ps1 -All
    Полный проход: исходники, библиотеки, конфигурация, сборка, выкладка.

.EXAMPLE
    powershell -File scripts\build.ps1 -Build -Deploy
    Быстрая пересборка после правки исходников.
#>
[CmdletBinding()]
param(
    [string]$Tag = 'v7.1.1',
    [string]$Root = 'D:\Build\TelegramTeam',
    [string]$InstallPath = 'D:\Apps\TelegramTeam',
    [switch]$Sources,
    [switch]$Prepare,
    [switch]$Configure,
    [switch]$Build,
    [switch]$Deploy,
    [switch]$All,
    [int]$Jobs = 0
)

$ErrorActionPreference = 'Stop'

if ($All) { $Sources = $true; $Prepare = $true; $Configure = $true; $Build = $true; $Deploy = $true }
if (-not ($Sources -or $Prepare -or $Configure -or $Build -or $Deploy)) {
    throw 'Нечего делать: укажите -All либо отдельные этапы (-Sources -Prepare -Configure -Build -Deploy).'
}

# Скрипт лежит в <проект>\scripts, поэтому корень проекта — на уровень выше.
# Считать через два Split-Path нельзя: так получается родитель проекта, и файл
# .env с ключом приложения ищется не там, где лежит.
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$sourcePath = Join-Path $Root 'tdesktop'
$patchPath = Join-Path $projectRoot 'patches\desktop'
$logPath = Join-Path $Root 'build.log'

function Write-Step([string]$text) {
    $stamp = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$stamp] $text" -ForegroundColor Cyan
    Add-Content -Path $logPath -Value "[$stamp] $text" -Encoding utf8
}

function Get-VcVarsPath {
    $vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw 'Visual Studio не найдена: нет vswhere.exe.' }
    $installation = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ([string]::IsNullOrWhiteSpace($installation)) {
        throw 'В Visual Studio не установлен компонент "Разработка классических приложений на C++".'
    }
    $vcvars = Join-Path $installation 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path $vcvars)) { throw "Не найден $vcvars." }
    return $vcvars
}

function Invoke-InBuildEnvironment([string]$workingDirectory, [string]$command, [string]$display = '') {
    # Требуется именно тот компилятор, который называет документация tdesktop:
    # у Visual Studio 2026 компилятор по умолчанию не поддерживает Windows 7,
    # поэтому версия задаётся явно и на 2022, и на 2026.
    $vcvars = Get-VcVarsPath
    # Каталог с vswhere.exe в PATH не входит, и vcvars ругается на его отсутствие
    # при каждом вызове. На сборку это не влияет, но прячет настоящие ошибки.
    $installer = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer'
    # 2>&1 — иначе ошибки уходят мимо основного лога, и упавшая сборка выглядит
    # как молча оборвавшаяся.
    $full = "set `"PATH=%PATH%;$installer`" && call `"$vcvars`" -vcvars_ver=14.44 >nul && cd /d `"$workingDirectory`" && $command 2>&1"
    & cmd.exe /c $full
    if ($LASTEXITCODE -ne 0) {
        # В командной строке лежит ключ приложения, поэтому в сообщение об ошибке
        # идёт только человекочитаемое название шага.
        $safe = if ($display) { $display } else { $command }
        throw "Шаг завершился с кодом ${LASTEXITCODE}: $safe"
    }
}

function Repair-LibvpxDebugAssembly {
    # NASM 3.02 падает с segmentation fault на флаге -gcv8 (отладочная информация
    # CodeView) и оставляет объектный файл нулевой длины. libvpx просит этот флаг
    # только в Debug, поэтому Release собирается начисто, а Debug роняет линковку
    # с LNK1136 «недопустимый или поврежденный файл» — ровно 26 раз и всегда на
    # одних и тех же ассемблерных модулях. Прецедент 2026-07-28: выглядит как
    # повреждение файлов или гонка сборки, хотя это отказ ассемблера.
    # Отладочная информация ассемблерных модулей Debug-библиотеки нам не нужна:
    # клиент собирается в Release.
    $patchDirectory = Join-Path $Root 'Libraries\win64\patches\libvpx'
    if (-not (Test-Path $patchDirectory)) { return }
    $patchPath = Join-Path $patchDirectory '0006-drop-nasm-codeview-debug-info.patch'
    if (Test-Path $patchPath) { return }
    $lines = @(
        'diff --git a/build/make/gen_msvs_vcxproj.sh b/build/make/gen_msvs_vcxproj.sh'
        '--- a/build/make/gen_msvs_vcxproj.sh'
        '+++ b/build/make/gen_msvs_vcxproj.sh'
        '@@ -262,5 +262,5 @@ case "$target" in'
        '     x86_64*)'
        '         platforms[0]="x64"'
        '-        asm_Debug_cmdline="${as} -Xvc -gcv8 -f win64 ${yasmincs} &quot;%(FullPath)&quot;"'
        '+        asm_Debug_cmdline="${as} -Xvc -f win64 ${yasmincs} &quot;%(FullPath)&quot;"'
        '         asm_Release_cmdline="${as} -Xvc -f win64 ${yasmincs} &quot;%(FullPath)&quot;"'
        '     ;;'
        '@@ -267,5 +267,5 @@ case "$target" in'
        '     x86*)'
        '         platforms[0]="Win32"'
        '-        asm_Debug_cmdline="${as} -Xvc -gcv8 -f win32 ${yasmincs} &quot;%(FullPath)&quot;"'
        '+        asm_Debug_cmdline="${as} -Xvc -f win32 ${yasmincs} &quot;%(FullPath)&quot;"'
        '         asm_Release_cmdline="${as} -Xvc -f win32 ${yasmincs} &quot;%(FullPath)&quot;"'
        '     ;;'
    )
    # Только LF: git apply не примет патч с переводами строк Windows.
    [System.IO.File]::WriteAllText($patchPath, ($lines -join "`n") + "`n")
    Write-Step 'libvpx: убран флаг -gcv8, на котором падает NASM 3.02'
}

function Repair-QtVulkanLink {
    # Qt собирается с поддержкой Vulkan, если на машине установлен Vulkan SDK
    # (достаточно самого факта установки). Тогда qwindows.lib ссылается на
    # QBasicPlatformVulkanInstance, а список библиотек Qt в сборке Telegram эту
    # реализацию не подключает: официальная сборка идёт без Vulkan. Линковка
    # падает с LNK2019 на четырнадцати символах — и не в самом клиенте, а во
    # вспомогательной утилите codegen_emoji, что уводит от причины.
    # Файл лежит в подмодуле cmake, поэтому патчем репозитория не переносится.
    $file = Join-Path $Root 'tdesktop\cmake\external\qt\CMakeLists.txt'
    if (-not (Test-Path $file)) { return }
    $text = [System.IO.File]::ReadAllText($file)
    if ($text -match 'VulkanSupport') { return }
    $anchor = '            lib/${qt_lib_prefix}Qt${QT_VERSION_MAJOR}WindowsUIAutomationSupport'
    if (-not $text.Contains($anchor)) {
        Write-Warning 'Не нашёл список библиотек Qt — поддержку Vulkan придётся подключить вручную.'
        return
    }
    $text = $text.Replace($anchor, $anchor + "`n" + '            lib/${qt_lib_prefix}Qt${QT_VERSION_MAJOR}VulkanSupport')
    [System.IO.File]::WriteAllText($file, $text)
    Write-Step 'Qt: подключена библиотека поддержки Vulkan, без неё не линкуется'
}

function Read-DotEnvValue([string]$path, [string]$key) {
    if (-not (Test-Path $path)) { return '' }
    foreach ($line in Get-Content -Path $path -Encoding utf8) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith('#')) { continue }
        $separator = $trimmed.IndexOf('=')
        if ($separator -lt 1) { continue }
        if ($trimmed.Substring(0, $separator).Trim() -ne $key) { continue }
        return $trimmed.Substring($separator + 1).Trim().Trim('"')
    }
    return ''
}

function Get-TelegramCredentials {
    # Ключ приложения берётся из окружения либо из файла .env рядом с проектом.
    # В репозиторий, в аргументы командной строки и в лог сборки значение не
    # попадает: CMake получает его переменными окружения процесса.
    $apiID = [string]$env:TELEGRAM_API_ID
    $apiHash = [string]$env:TELEGRAM_API_HASH
    if ([string]::IsNullOrWhiteSpace($apiID) -or [string]::IsNullOrWhiteSpace($apiHash)) {
        $local = Join-Path $projectRoot '.env'
        $apiID = Read-DotEnvValue $local 'TELEGRAM_API_ID'
        $apiHash = Read-DotEnvValue $local 'TELEGRAM_API_HASH'
    }
    if ([string]::IsNullOrWhiteSpace($apiID) -or [string]::IsNullOrWhiteSpace($apiHash)) {
        throw 'Не найден ключ приложения Telegram: задайте TELEGRAM_API_ID и TELEGRAM_API_HASH (получить — my.telegram.org).'
    }
    return @{ ID = $apiID; Hash = $apiHash }
}

function Get-ScrambledApiHash([string]$hash) {
    # Ключ уходит в компилятор уже перемешанным: считать перемешивание в самом
    # коде бесполезно — MSVC всё равно кладёт исходный литерал в .exe, и после
    # сборки 24.08.2026 api_hash находился в файле обычным поиском строк.
    # Обратное преобразование живёт в config.h; маска здесь и там обязана
    # совпадать.
    if ($hash.Length -ne 32) { throw "api_hash должен быть длиной 32 знака, а не $($hash.Length)" }
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($hash)
    $result = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt 32; $i++) {
        $mask = (0x5A + $i * 7 + [Math]::Floor($i / 4)) -band 0xFF
        [void]$result.Append(('{0:x2}' -f ($bytes[$i] -bxor $mask)))
    }
    return $result.ToString()
}

New-Item -ItemType Directory -Force $Root | Out-Null
Write-Step "Сборка Telegram Team: тег $Tag, каталог $Root"

$freeGB = [math]::Round((Get-PSDrive -Name ($Root.Substring(0,1))).Free / 1GB, 1)
Write-Step "Свободно на диске: $freeGB ГБ"
if ($freeGB -lt 100 -and ($Prepare -or $All)) {
    Write-Warning "Подготовка библиотек занимает 60-80 ГБ, свободно $freeGB ГБ."
}

if ($Sources) {
    if (-not (Test-Path $sourcePath)) {
        Write-Step 'Скачиваю исходники Telegram'
        & git clone -b $Tag --recurse-submodules --shallow-submodules https://github.com/telegramdesktop/tdesktop.git $sourcePath
        if ($LASTEXITCODE -ne 0) { throw 'Не удалось скачать исходники.' }
    } else {
        Write-Step 'Исходники уже на месте'
    }

    $branch = (& git -C $sourcePath branch --show-current)
    if ($branch -ne 'leadsearcher') {
        # Пустой каталог патчей молча дал бы ванильный Telegram Desktop: ветка
        # осталась бы чистым тегом, и выяснилось бы это только на выкладке.
        $patches = @(Get-ChildItem $patchPath -Filter '*.patch' -ErrorAction SilentlyContinue | Sort-Object Name)
        if (-not $patches) { throw "Патчи не найдены в $patchPath — без них соберётся не наш клиент." }
        Write-Step 'Накатываю наши правки на чистый тег'
        & git -C $sourcePath checkout -q -B leadsearcher $Tag
        if ($LASTEXITCODE -ne 0) { throw 'Не удалось переключиться на ветку leadsearcher.' }
        foreach ($patch in $patches) {
            Write-Step "  патч $($patch.Name)"
            & git -C $sourcePath am --keep-cr $patch.FullName
            if ($LASTEXITCODE -ne 0) {
                & git -C $sourcePath am --abort
                throw "Патч $($patch.Name) не лёг на тег $Tag — правки нужно перенести вручную."
            }
        }
    } else {
        Write-Step 'Правки уже применены'
    }
}

if ($Prepare) {
    # Самый долгий этап: Qt, WebRTC, ffmpeg, OpenSSL собираются из исходников.
    Repair-LibvpxDebugAssembly
    Write-Step 'Готовлю сторонние библиотеки (несколько часов)'
    # silent = отвечать «пересобрать» самому. Без него скрипт Telegram на любой
    # изменившейся библиотеке задаёт вопрос в консоль и ждёт нажатия клавиши —
    # в фоновом запуске это выглядит как зависшая сборка.
    Invoke-InBuildEnvironment $Root "`"$sourcePath\Telegram\build\prepare\win.bat`" silent"
    Write-Step 'Библиотеки готовы'
}

if ($Configure) {
    Repair-QtVulkanLink
    $credentials = Get-TelegramCredentials
    Write-Step 'Настраиваю проект'
    # Полный путь обязателен: в окружении задана NoDefaultCurrentDirectoryInExePath,
    # и cmd не ищет команды в текущем каталоге — короткое имя не находится, хотя
    # файл лежит рядом.
    # Имя переменной не должно повторять имя параметра скрипта: PowerShell не
    # различает регистр, и $configure затирает переключатель $Configure.
    $configureScript = Join-Path $sourcePath 'Telegram\configure.bat'
    $scrambled = Get-ScrambledApiHash $credentials.Hash
    Invoke-InBuildEnvironment (Join-Path $sourcePath 'Telegram') `
        "call `"$configureScript`" x64 -D TDESKTOP_API_ID=$($credentials.ID) -D TDESKTOP_API_HASH=$($credentials.Hash) -D TDESKTOP_API_HASH_SCRAMBLED=$scrambled" `
        'настройка проекта'
    Write-Step 'Проект настроен'
}

if ($Build) {
    # По умолчанию MSBuild запускает компилятор на каждое ядро. На двадцати
    # четырёх ядрах это двадцать пять процессов, а каждый под tdesktop берёт
    # три-четыре гигабайта — память кончается, и компилятор падает с C1060
    # («не хватает размера кучи») и C3859 (нет памяти под предкомпилированные
    # заголовки). Ошибки выглядят как проблема кода, хотя это нехватка ОЗУ.
    # Считать надо по свободной памяти, а не по всей: машина одновременно
    # работает как сервер, и половина ОЗУ занята постоянно.
    #
    # Десять гигабайт на процесс, а не шесть: 29.07.2026 при 27,9 ГБ свободных
    # формула дала четыре процесса, и сборка упала на mainwindow.cpp с C3859
    # («не удалось создать виртуальную память для PCH») и C1076 («достигнут
    # предел внутренней кучи»). Компилятор x64, адресного пространства ему
    # хватает — не хватило именно физической памяти под четыре PCH разом.
    # Тот же файл с двумя процессами собирается. Свободная память к тому же
    # меряется в момент запуска и за часы сборки успевает уйти под сервер,
    # поэтому запас нужен кратный, а не впритык.
    if ($Jobs -le 0) {
        $freeGB = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
        $cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
        $Jobs = [Math]::Max(2, [Math]::Min($cores, [Math]::Floor($freeGB / 10)))
    }
    Write-Step "Собираю клиент, одновременно $Jobs процессов компиляции"
    Invoke-InBuildEnvironment $sourcePath `
        "cmake --build out --config Release --target Telegram -- -m:1 -p:CL_MPCount=$Jobs" `
        'сборка клиента'
    Write-Step 'Сборка завершена'
}

if ($Deploy) {
    $binary = Get-ChildItem (Join-Path $sourcePath 'out') -Filter 'TelegramTeam.exe' -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $binary) { throw 'Собранный TelegramTeam.exe не найден.' }
    New-Item -ItemType Directory -Force $InstallPath | Out-Null
    Copy-Item $binary.FullName (Join-Path $InstallPath 'TelegramTeam.exe') -Force
    Write-Step "Клиент выложен: $(Join-Path $InstallPath 'TelegramTeam.exe')"
    Write-Step 'Первый запуск: войти в аккаунты по QR-коду, схемы tg:// и tgteam:// клиент запишет за собой сам'
}
