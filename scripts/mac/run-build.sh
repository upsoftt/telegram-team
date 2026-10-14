#!/bin/sh
# Номер сборки передаётся первым аргументом: TestFlight не принимает
# повторный номер, каждая загрузка должна быть больше предыдущей.
BUILD_NUMBER="${1:-1}"
# Признак конца от прошлого прогона убирается сразу: иначе ждущий цикл увидит
# старый код возврата и решит, что новая сборка уже закончилась.
rm -f "$HOME/tgteam-build.status"
trap 'code=$?; echo "$code" > "$HOME/tgteam-build.status"' EXIT

# Пароль связки в репозиторий не кладётся — он живёт только на сборочной
# машине, в ~/.tgteam-build.env со строкой KEYCHAIN_PASSWORD=<пароль>.
# Там же можно задать:
#   TGTEAM_KEYCHAIN — связка с ключом подписи, если это не login (например,
#                     перенесённая с другой машины);
#   TGTEAM_XCODE    — каким Xcode собирать, если системный не годится.
if [ -f "$HOME/.tgteam-build.env" ]; then
	. "$HOME/.tgteam-build.env"
fi
if [ -z "$KEYCHAIN_PASSWORD" ]; then
	echo "нет KEYCHAIN_PASSWORD: заведите ~/.tgteam-build.env со строкой KEYCHAIN_PASSWORD=<пароль связки>" >&2
	exit 1
fi
KEYCHAIN="${TGTEAM_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

# Связка должна быть открыта ДО старта демона Bazel: действия подписи идут
# детьми демона и наследуют его сессию безопасности, а не сессию SSH.
# Неудачу здесь ловим сразу: иначе она всплывёт через полчаса на подписи как
# невнятный errSecInternalComponent.
if ! security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"; then
	echo "связку $KEYCHAIN открыть не удалось — проверьте KEYCHAIN_PASSWORD" >&2
	exit 1
fi
security set-keychain-settings "$KEYCHAIN"

# Make.py и Bazel слушают только xcode-select, а не DEVELOPER_DIR. Если системный
# Xcode 27, а собирать надо 26.x (с SDK iOS 27 приложению без сцен
# грозит падение на старте), поэтому на время сборки Xcode переключается и
# возвращается на выходе.
if [ -n "$TGTEAM_XCODE" ]; then
	PREV_XCODE=$(xcode-select -p)
	sudo xcode-select -s "$TGTEAM_XCODE" || exit 1
	trap 'code=$?; sudo xcode-select -s "$PREV_XCODE"; echo "$code" > "$HOME/tgteam-build.status"' EXIT
fi

cd "$HOME/Projects/Telegram-iOS" || exit 1
# Версия Bazel меняется вместе с апстримом (8.4.2 до 13.0, 9.2.0 с 13.0), а
# архитектура — вместе с машиной: гасим демон любой скачанной.
for bazel in ./build-input/bazel-*-darwin-*; do
	[ -x "$bazel" ] && "$bazel" shutdown >/dev/null 2>&1
done
# Telegram 13.0 объявляет Xcode 26.6, у нас 26.2: Make.py без флага
# останавливается на сверке версии, с ним берёт выбранный Xcode.
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir="$HOME/telegram-bazel-cache" build \
  --configurationPath=build-system/tgteam-configuration.json \
  --buildNumber="$BUILD_NUMBER" --configuration=release_arm64 \
  --codesigningInformationPath="$HOME/tgteam-codesigning" > "$HOME/tgteam-build.log" 2>&1
