## Purpose

Фиксирует структуру Electron-приложения по слоям и нейминг, в один ряд со спеками архитектуры других языков.

## ADDED Requirements

### Requirement: Дерево приложения фиксировано
Репозиторий `desktop` SHALL иметь структуру:

```
desktop/
  package.json            electron, electron-vite, electron-builder, electron-updater; scripts dev/build/lint/typecheck/test
  electron.vite.config.ts main + preload (renderer — сайт, не собирается)
  electron-builder.yml    appId, artifacts, publish: github
  src/
    main/                 процесс main — только здесь есть доступ к Electron API и Node
      index.ts            точка входа: single instance, app lifecycle, композиция модулей
      window.ts           createMainWindow(): BrowserWindow, webPreferences, состояние окна
      navigation.ts       политика ссылок: свой origin / внешние → shell.openExternal
      menu.ts             системное меню
      deep-link.ts        регистрация схемы, обработка URL, отправка в renderer
      updater.ts          electron-updater: расписание, диалог
      offline.ts          экран «нет соединения»
    preload/
      index.ts            contextBridge.exposeInMainWorld('desktop', …) — реализация контракта
    shared/
      bridge.ts           тип DesktopBridge + имена IPC-каналов — единственное место, общее для main и preload
  tests/                  vitest: window.test.ts (webPreferences), navigation.test.ts, bridge-contract.test.ts (сверка с frontend)
  build/                  иконки (icon.icns/ico/png)
```

#### Scenario: Новая нативная возможность
- **WHEN** добавляется, например, «показать файл в Finder»
- **THEN** появляется модуль `src/main/<feature>.ts`, канал и тип в `src/shared/bridge.ts`, метод в `src/preload/index.ts`, копия типа во фронте — и ничего в других местах

### Requirement: Направление зависимостей
`preload` MUST импортировать только `electron` и `src/shared`; `main` MUST NOT импортировать `preload`; `shared` MUST NOT импортировать `electron` (только типы через `import type`). Проверяется eslint `no-restricted-imports` по папкам.

#### Scenario: Preload тянет main
- **WHEN** `src/preload/index.ts` импортирует `../main/window`
- **THEN** `pnpm lint` падает

### Requirement: Нейминг
Модули main — по возможности (`window.ts`, `updater.ts`), экспорт — функции `create*`/`register*`/`setup*` без классов; IPC-каналы — `desktop:<domain>:<action>` (`desktop:link:open`), события в renderer — `desktop:<domain>:<event>`; версии зависимостей закреплены точно (без `^`).

#### Scenario: Канал без префикса
- **WHEN** в `bridge.ts` появляется канал `openLink`
- **THEN** ревью возвращает change: формат `desktop:<domain>:<action>`
