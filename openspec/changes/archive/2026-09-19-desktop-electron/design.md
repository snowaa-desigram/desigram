## Context

- Фронт — Next.js 16 (`output: 'standalone'`, SSR, `API_URL_INTERNAL`), FSD, pnpm, Node 22; деплоится контейнером за Traefik. Local-first (`plans/localfirst-arch.md`) держит данные в браузере — оболочке ничего своего хранить не нужно.
- В монорепо каждая часть — сабмодуль со своим CI; десктоп не контейнер и не участвует в compose/Ansible.
- Пользователь выбрал: Electron (как Figma), окно грузит сайт по URL (см. proposal — Why).
- Версии на 2026-09: electron 44.4, electron-builder 26.15, electron-vite 5.0, electron-updater 6.8.

## Goals / Non-Goals

**Goals:**
- Один фронт для сайта и десктопа; десктоп-релиз только при изменении нативной части.
- Безопасные дефолты Electron, поверхность моста минимальна и типизирована.
- Релиз — одна команда (`git tag`), установщики и автообновление без ручных шагов.

**Non-Goals:**
- Подпись/нотаризация (нет аккаунтов); офлайн-старт без сети; бандл фронта в приложение; Tauri (пользователь выбрал Electron; Tauri легче, но WebView зависит от ОС — с OPFS/SharedWorker для local-first это риск).

## Decisions

### D1. Отдельный сабмодуль `desktop`, а не папка во `frontend`
Свой цикл релизов (теги `v*`), своя тяжёлая CI-матрица (3 ОС), свои зависимости (electron ~100 МБ). Внутри `frontend` это раздувало бы образ и CI сайта. Общий контракт моста — один файл, копируемый с проверкой (D4), а не npm-пакет: два потребителя, пакет ради типа — лишний контур.

### D2. electron-vite для main/preload, electron-builder для установщиков
electron-vite даёт HMR/перезапуск main и сборку preload одним конфигом; renderer не собираем (`renderer` отсутствует в конфиге). electron-builder — де-факто стандарт для dmg/nsis/AppImage и `publish: github`; electron-forge потребовал бы отдельных makers на каждую ОС. Альтернатива «tsc + electron-builder» — без перезапуска в dev.

### D3. Политика навигации в `main/navigation.ts`
`will-navigate` + `setWindowOpenHandler`: разрешён только origin из `GRAM_DESIGNER_URL` и его поддомены, остальное — `shell.openExternal` и `deny`. Это единственное место, где решается «куда можно». Проверяется unit-тестом с таблицей URL → решение.

### D4. Контракт моста — `src/shared/bridge.ts` + копия во фронте
Тип `DesktopBridge` и константы каналов живут в `desktop/src/shared/bridge.ts`; во фронте — `src/shared/platform/desktop.d.ts` (только тип). Тест `bridge-contract.test.ts` в `desktop` читает оба файла (фронт — сабмодуль рядом, путь `../frontend/…`; в CI фронт подтягивается checkout'ом монорепо с сабмодулями) и падает при расхождении. Альтернатива — workspace-пакет между сабмодулями: разные репозитории, pnpm workspace через сабмодули хрупок.

### D5. Автообновление — electron-updater с GitHub Releases
`publish: github` в electron-builder генерирует `latest*.yml`; `autoUpdater.checkForUpdatesAndNotify` на старте и по таймеру, `autoInstallOnAppQuit`. Без подписи macOS-обновления electron-updater применять не сможет (Squirrel.Mac требует подпись) — на macOS до появления сертификата показываем диалог «скачать новую версию» со ссылкой на релиз; Windows/Linux обновляются полноценно. Зафиксировано как известное ограничение в README.

### D6. Deep-links и single instance
`app.setAsDefaultProtocolClient('gram-designer')`, `requestSingleInstanceLock`; URL приходит через `open-url` (macOS) или `second-instance` argv (Windows/Linux) → `webContents.send('desktop:link:received', url)` → preload → `onDeepLink`. Нужен для auth-callback'ов и «открыть проект» в будущем; сейчас — только транспорт.

### D7. Dev против локального стека
`GRAM_DESIGNER_URL=https://gram-designer.localhost:8443` (порт из `.env`); mkcert-корень в системном хранилище → Chromium в Electron ему доверяет, флагов отключения TLS нет. Экран офлайна — локальный `offline.html`, загружается через `loadFile` при `did-fail-load`.

## Паттерны

- **Facade** — `window.desktop` (preload) — единственный фасад над IPC для фронта; фронт не знает каналов. Альтернатива «фронт шлёт ipcRenderer.invoke сам» отвергнута: раскрывает каналы и ломает изоляцию.
- **Observer** — `onDeepLink(handler) → unsubscribe` поверх `ipcRenderer.on`; стандартная подписка вместо колбэка-синглтона, чтобы несколько частей фронта могли слушать.
- **Без паттерна** — модули main (`window`, `menu`, `updater`) — функции композиции, вызываемые из `index.ts`; Strategy для «политики навигации» избыточна: одна таблица правил в одной функции.

## Risks / Trade-offs

- [Нет подписи → предупреждения Gatekeeper/SmartScreen, на macOS нет автообновления] → фиксируем в README и на `/download`; подпись — отдельный change, когда появятся аккаунты.
- [Сайт недоступен → пустое приложение] → экран офлайна с retry; полноценный офлайн — после local-first (app-shell кеш).
- [Контракт моста разъедется между репо] → тест D4 в CI `desktop`; на стороне фронта тип — `d.ts`, изменение без обновления `desktop` ловится typecheck'ом при первом использовании нового поля.
- [Electron ~100 МБ на каждую ОС в CI] → сборка только по тегу и на PR в `desktop`; кеш pnpm store.
- [Зависимость frontend в CI `desktop` (D4)] → checkout корневого монорепо с `submodules: true` и `SUBMODULES_TOKEN` (как в `e2e.yml`).

## Migration Plan

1. `gh repo create snowaa-desigram/desktop --private`, `git submodule add` в корень.
2. Каркас `desktop` (electron-vite init → приведение к спеке), тесты, CI.
3. Фронт: `shared/platform`, `/download`, eslint-правило.
4. Пользователь: `pnpm install && pnpm dev` в `desktop` против `make dev`; тег `v0.1.0` → проверить Releases и установку на своей ОС.
Откат: удалить сабмодуль; фронт-часть безвредна без `window.desktop`.

## Open Questions

- Иконка приложения (нужен исходник 1024×1024) — до неё используется плейсхолдер; не влияет на структуру.
