#!/bin/sh
# Номер сборки передаётся первым аргументом: TestFlight не принимает
# повторный номер, каждая загрузка должна быть больше предыдущей.
BUILD_NUMBER="${1:-1}"
# Признак конца от прошлого прогона убирается сразу: иначе ждущий цикл увидит
# старый код возврата и решит, что новая сборка уже закончилась.
rm -f "$HOME/tgteam-build.status"

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
# Версия Bazel меняется вместе с апстримом (8.4.2 до 13.0, 9.2.0 с 13.0) —
# гасим демон любой скачанной.
for bazel in ./build-input/bazel-*-darwin-x86_64; do
	[ -x "$bazel" ] && "$bazel" shutdown >/dev/null 2>&1
done
# Telegram 13.0 объявляет Xcode 26.6, на сборочной машине может стоять более ранний: Make.py без
# флага останавливается на сверке версии, с ним берёт установленный Xcode.
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir="$HOME/telegram-bazel-cache" build \
  --configurationPath=build-system/tgteam-configuration.json \
  --buildNumber="$BUILD_NUMBER" --configuration=release_arm64 \
  --codesigningInformationPath="$HOME/tgteam-codesigning" > "$HOME/tgteam-build.log" 2>&1
echo $? > "$HOME/tgteam-build.status"
