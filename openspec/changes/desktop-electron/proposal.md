## Why

Продукт должен работать и как сайт, и как устанавливаемое приложение на macOS / Windows / Linux — как Figma. Local-first-план (`plans/localfirst-arch.md`) кладёт данные и логику в браузерный слой (SQLite WASM, воркеры), поэтому десктоп — тонкая оболочка над тем же фронтом, а не второе приложение. Закладываем оболочку сейчас, пока фронт маленький, чтобы фронт с первого дня знал о платформе (`isDesktop`, мост к нативному API).

## What Changes

- Новый сабмодуль **`desktop/`** (репозиторий `snowaa-desigram/desktop`): Electron-приложение, окно которого загружает сайт по URL (`https://gram-designer.com`, в dev — `https://gram-designer.localhost:<port>`). Никакого бандла фронта внутри: один деплой фронта обновляет и сайт, и десктоп.
- Нативная часть: главное окно с сохранением размера/положения, системное меню, внешние ссылки — в браузер, навигация только внутри своего origin, deep-links `gram-designer://…`, автообновление через GitHub Releases (`electron-updater`).
- Мост в фронт: `preload` через `contextBridge` публикует `window.desktop` (платформа, версия, подписка на deep-link, `openExternal`). `contextIsolation: true`, `nodeIntegration: false`, `sandbox: true`.
- **Фронт**: `src/shared/platform` — `isDesktop`, типизированный доступ к `window.desktop`; страница `/download` со ссылками на последний релиз.
- **CI** (в `desktop`): сборка dmg / nsis / AppImage на push тега `v*` в матрице macOS/Windows/Ubuntu, публикация в GitHub Releases; на PR — lint + typecheck + сборка без публикации.
- Корень: сабмодуль в `.gitmodules`, README «Десктоп», `openspec/config.yaml` — контекст и правила для `desktop`, спека `architecture-desktop`.

## Capabilities

### New Capabilities
- `desktop-shell`: что делает десктоп-приложение — загрузка сайта, окно, ссылки, deep-links, автообновление, безопасность.
- `desktop-bridge`: контракт `window.desktop` между Electron и фронтом и как фронт определяет платформу.
- `desktop-release`: как собирается и публикуется приложение, страница загрузки.
- `architecture-desktop`: структура кода Electron-приложения (папки, слои, нейминг) — в один ряд с `architecture-*` других языков.

### Modified Capabilities
<!-- нет -->

## Impact

- **Новый репозиторий** `snowaa-desigram/desktop` (создаётся через `gh repo create`), сабмодуль `desktop/` в корне.
- **frontend**: `src/shared/platform/`, страница `/download`, ничего в существующем поведении сайта не меняется.
- **enviropment**: не меняется (десктоп — не контейнер). Traefik/CSP не трогаем: Electron загружает сайт как обычный браузер.
- **Не входит**: подпись и нотаризация macOS/Windows (нужны аккаунты Apple Developer / сертификат — без них сборки устанавливаются с предупреждением ОС), офлайн-старт без сети (app-shell кеш — после local-first), нативные фичи сверх перечисленных.
