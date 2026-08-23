#!/bin/sh
# Номер сборки передаётся первым аргументом: TestFlight не принимает
# повторный номер, каждая загрузка должна быть больше предыдущей.
BUILD_NUMBER="${1:-1}"

# Пароль учётной записи в репозиторий не кладётся — он живёт только на самой
# сборочной машине, в ~/.tgteam-build.env со строкой KEYCHAIN_PASSWORD=<пароль>.
if [ -f "$HOME/.tgteam-build.env" ]; then
	. "$HOME/.tgteam-build.env"
fi
if [ -z "$KEYCHAIN_PASSWORD" ]; then
	echo "нет KEYCHAIN_PASSWORD: заведите ~/.tgteam-build.env со строкой KEYCHAIN_PASSWORD=<пароль учётной записи>" >&2
	exit 1
fi

# Связка должна быть открыта ДО старта демона Bazel: действия подписи идут
# детьми демона и наследуют его сессию безопасности, а не сессию SSH.
# Неудачу здесь ловим сразу: иначе она всплывёт через полчаса на подписи как
# невнятный errSecInternalComponent.
if ! security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$HOME/Library/Keychains/login.keychain-db"; then
	echo "связку ключей открыть не удалось — проверьте KEYCHAIN_PASSWORD" >&2
	exit 1
fi
security set-keychain-settings "$HOME/Library/Keychains/login.keychain-db"
cd "$HOME/Projects/Telegram-iOS"
./build-input/bazel-8.4.2-darwin-x86_64 shutdown >/dev/null 2>&1
python3 build-system/Make/Make.py --cacheDir="$HOME/telegram-bazel-cache" build \
  --configurationPath=build-system/tgteam-configuration.json \
  --buildNumber="$BUILD_NUMBER" --configuration=release_arm64 \
  --codesigningInformationPath="$HOME/tgteam-codesigning" > "$HOME/tgteam-build.log" 2>&1
echo $? > "$HOME/tgteam-build.status"
