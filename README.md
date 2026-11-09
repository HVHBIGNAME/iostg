# iostg

**WhiteGram** — iOS-клиент с дополнительными настройками. Текущий кандидат исходников — **Telegram 13.1.2 / build 34654**.

## Скачать

[Проверенная IPA — Telegram 13.0 / build 34652](https://github.com/HVHBIGNAME/iostg/actions/runs/40275611466/artifacts/12631305780) · [Сборки](https://github.com/HVHBIGNAME/iostg/actions/workflows/build.yml)

Скачайте ZIP, извлеките `.ipa` и подпишите через ESign, Feather, AltStore или Sideloadly.

## Сборка

GitHub Actions → **Build WhiteGram IPA** → **Run workflow**.

- `simulator_only` — проверка в симуляторе без device IPA.
- `login_check` — проверка связи при входе; отключайте во время `FLOOD_WAIT`.
- Для своего приложения добавьте Secrets `WHITEGRAM_TELEGRAM_API_ID` и `WHITEGRAM_TELEGRAM_API_HASH` из [my.telegram.org/apps](https://my.telegram.org/apps).

Исходники Telegram закреплены на `release-13.1.2` (`279f89e4d4f63f17227bf877dc3d8990f22ecd58`); изменения WhiteGram находятся в `whitegram/`. Требуются Xcode 27.1 и Bazel 9.2.0.

## Статус

Для 13.1.2 прошли локальные проверки переноса и синтаксиса. Новая native-сборка IPA и запуск в симуляторе ещё ожидаются; подтверждённый результат относится к build 34652. Поведение на iPhone и полное соответствие функций оригиналу ещё проверяются.

[Обновление 13.1.2](whitegram/UPGRADE_13_1_2.md) · [Сравнение с Whitegram 8.1.1](whitegram/REFERENCE_8_1_1.md) · [Текущие задачи](whitegram/CURRENT_BACKLOG.md) · [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS)
