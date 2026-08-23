#!/bin/sh
# Проверка и загрузка собранного пакета в TestFlight.
#
# Проверка делается всегда: она ловит проблемы с иконками и правами до того, как
# загрузка займёт номер сборки, а номера не переиспользуются.
#
# Ключ App Store Connect и идентификатор издателя лежат в ~/.ascenv — файл вне
# репозитория. Код возврата пишется в ~/tgteam-upload.status: по нему видно, что
# заливка закончилась, не вчитываясь в журнал.

# Признак пишется через ловушку на выходе, а не в конце: иначе ранний отказ
# (нет ключа, нет пакета) оставлял бы файл ненаписанным, и всякий, кто ждёт
# конца заливки по этому файлу, ждал бы вечно.
STATUS_FILE="$HOME/tgteam-upload.status"
rm -f "$STATUS_FILE"
trap 'code=$?; echo "$code" > "$STATUS_FILE"' EXIT

if [ ! -f "$HOME/.ascenv" ]; then
	echo "нет ~/.ascenv с ASC_ISSUER_ID и ключом App Store Connect" >&2
	exit 1
fi
. "$HOME/.ascenv"

IPA="${1:-$HOME/Projects/Telegram-iOS/bazel-bin/Telegram/Telegram.ipa}"
if [ ! -f "$IPA" ]; then
	echo "пакет не найден: $IPA" >&2
	exit 1
fi

if [ -z "$ASC_KEY_ID" ]; then
	echo "нет ASC_KEY_ID: добавьте его в ~/.ascenv" >&2
	exit 1
fi
KEY_ID="$ASC_KEY_ID"

xcrun altool --validate-app -f "$IPA" -t ios --apiKey "$KEY_ID" --apiIssuer "$ASC_ISSUER_ID" &&
	xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
