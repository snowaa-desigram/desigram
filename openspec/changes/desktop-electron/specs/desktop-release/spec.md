## Purpose

Определяет, как приложение собирается, публикуется и как пользователь его скачивает.

## ADDED Requirements

### Requirement: Сборка по тегу в GitHub Releases
Push тега `v<semver>` в репозиторий `desktop` SHALL запускать сборку установщиков: macOS (dmg, universal), Windows (nsis x64), Linux (AppImage x64) и публиковать их вместе с файлами метаданных автообновления (`latest*.yml`) в GitHub Release с тем же тегом. Версия приложения MUST совпадать с тегом.

#### Scenario: Релиз
- **WHEN** запушен тег `v0.1.0`
- **THEN** через один прогон CI в Releases есть `.dmg`, `.exe`, `.AppImage` и `latest*.yml`, а установленное приложение прошлой версии видит обновление

#### Scenario: Pull request
- **WHEN** открыт PR в `desktop`
- **THEN** CI гоняет lint, typecheck, тесты и сборку без публикации

### Requirement: Страница загрузки на сайте
Сайт SHALL иметь страницу `/download` с кнопками для macOS / Windows / Linux, ведущими на установщики последнего релиза (`…/releases/latest/download/<file>`), и автоматически подсвечивать вариант для текущей ОС.

#### Scenario: Пользователь на macOS
- **WHEN** открыта `/download` в macOS
- **THEN** кнопка macOS выделена и ведёт на актуальный `.dmg`

### Requirement: Локальная сборка и dev-режим
`pnpm dev` в `desktop` SHALL запускать приложение против `GRAM_DESIGNER_URL` (по умолчанию `https://gram-designer.localhost:8443`, сертификат mkcert из `make cert` доверен системой); `pnpm build` — собирать установщик для текущей ОС без публикации.

#### Scenario: Разработка
- **WHEN** поднят `make dev` и выполнен `pnpm dev` в `desktop`
- **THEN** открывается окно с локальным сайтом, изменения main/preload перезапускают приложение
