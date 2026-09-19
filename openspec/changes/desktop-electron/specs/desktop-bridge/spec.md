## Purpose

Фиксирует контракт между Electron и фронтом: как сайт узнаёт, что он внутри приложения, и какие нативные возможности ему доступны.

## ADDED Requirements

### Requirement: window.desktop — единственный мост
Preload SHALL публиковать через `contextBridge` объект `window.desktop` с полями: `platform` (`'darwin' | 'win32' | 'linux'`), `version` (версия приложения), `openExternal(url)`, `onDeepLink(handler) → unsubscribe`. Ничего из Node/Electron сверх этого во фронт MUST NOT попадать. Тип объекта объявлен в одном файле, общем для `desktop` и `frontend` (копия в `frontend/src/shared/platform/desktop.d.ts`, тест в `desktop` сверяет их идентичность).

#### Scenario: Сайт в обычном браузере
- **WHEN** сайт открыт в Chrome
- **THEN** `window.desktop` отсутствует, `isDesktop === false`, всё работает как раньше

#### Scenario: Сайт в приложении
- **WHEN** сайт открыт в Electron
- **THEN** `isDesktop === true`, `desktop.platform` совпадает с ОС, `openExternal` открывает системный браузер

### Requirement: Фронт обращается к мосту только через shared/platform
Код фронта MUST NOT читать `window.desktop` напрямую — только через `src/shared/platform` (`isDesktop`, `desktop`), чтобы контракт менялся в одном месте; проверяется eslint-правилом `no-restricted-globals`/`no-restricted-syntax`.

#### Scenario: Прямое обращение
- **WHEN** в `src/features/**` появляется `window.desktop.openExternal(...)`
- **THEN** `pnpm lint` падает с подсказкой использовать `@shared/platform`
