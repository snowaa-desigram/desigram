## 1. Репозиторий и каркас (desktop)

- [x] 1.1 Создать `snowaa-desigram/desktop` (`gh repo create --public` — остальные репо публичные, `/download` качает без авторизации), добавить как сабмодуль `desktop/` в корень (`.gitmodules`); проверить `git submodule status`
- [x] 1.2 Каркас по спеке `architecture-desktop`: `package.json` (electron 44.4.3, electron-vite 5.0.0, electron-builder 26.15.3, electron-updater 6.8.9, vitest, eslint, typescript — точные версии), `electron.vite.config.ts` (main + preload), `tsconfig`, eslint с `no-restricted-imports` по слоям, `.gitignore`, LICENSE MIT; проверить `pnpm typecheck && pnpm lint` на пустом каркасе
- [x] 1.3 `src/shared/bridge.ts`: тип `DesktopBridge`, каналы `desktop:link:received`, `desktop:link:open`; проверить typecheck

## 2. Main и preload (desktop)

- [x] 2.1 `src/main/window.ts`: `createMainWindow()` с безопасными webPreferences, восстановление размера/положения (`electron-window-state` или свой JSON в `userData`), фон до загрузки; `tests/window.test.ts` проверяет четыре флага
- [x] 2.2 `src/main/navigation.ts`: `will-navigate` + `setWindowOpenHandler`, разрешён только origin `GRAM_DESIGNER_URL` и поддомены, внешние → `shell.openExternal`; `tests/navigation.test.ts` с таблицей URL → allow/external
- [x] 2.3 `src/main/offline.ts` + `offline.html`: при `did-fail-load` показать экран с «Повторить» (ручная проверка — в 6.1)
- [x] 2.4 `src/main/deep-link.ts`: `setAsDefaultProtocolClient('gram-designer')`, single instance, `open-url`/`second-instance` → `desktop:link:received` + фокус окна; ручная проверка `open gram-designer://test` — в 6.1
- [x] 2.5 `src/main/updater.ts`: electron-updater, проверка на старте и раз в час, диалог перезапуска, выключен в dev; на macOS без подписи — диалог со ссылкой на релиз; проверить typecheck и unit-тест расписания (fake timers)
- [x] 2.6 `src/main/menu.ts` (Файл/Правка/Вид/Окно/Справка, «Проверить обновления», «Сайт»), `src/main/index.ts` — композиция; `pnpm dev` открывает `https://gram-designer.localhost:8443`
- [x] 2.7 `src/preload/index.ts`: `contextBridge.exposeInMainWorld('desktop', …)` строго по `DesktopBridge`; `tests/bridge-contract.test.ts` сверяет `src/shared/bridge.ts` с `../frontend/src/shared/platform/desktop.d.ts`

## 3. Сборка и релизы (desktop)

- [x] 3.1 `electron-builder.yml`: appId `com.gram-designer.desktop`, mac dmg universal, win nsis x64, linux AppImage x64, `publish: github`, иконка-плейсхолдер `build/icon.png`; `electron-vite build` проверен (бинарник Electron не скачивался — `pnpm build` целиком в 6.1)
- [x] 3.2 `.github/workflows/release.yml` (тег `v*`, матрица macos/windows/ubuntu, `electron-builder --publish always`, checkout монорепо с сабмодулями для теста контракта) и `ci.yml` (PR: lint, typecheck, test, build без публикации); проверить `actionlint`/синтаксис
- [x] 3.3 README `desktop`: dev, сборка, релиз тегом, известные ограничения (без подписи; macOS — обновление вручную)

## 4. Фронт (frontend)

- [x] 4.1 `src/shared/platform/{index.ts,desktop.d.ts}`: `isDesktop`, `desktop` (типизированный `window.desktop | undefined`); eslint-правило запрещает `window.desktop` вне `shared/platform`; `pnpm lint && pnpm typecheck`
- [x] 4.2 Страница `/download` (`src/_pages/download`, `app/download/page.tsx`): три кнопки на `releases/latest/download/<file>`, подсветка текущей ОС, примечание про подпись; `pnpm lint && pnpm typecheck`

## 5. Корень

- [x] 5.1 README: раздел «Десктоп» (что это, dev, релиз, ограничения), строка в «Структура»; `openspec/config.yaml`: контекст про `desktop` и правило «нативное — только через мост»; `openspec doctor`
- [x] 5.2 Закоммитить и запушить `desktop`, `frontend`, корень (поинтеры)

## 6. Проверка пользователем

- [ ] 6.1 `cd desktop && pnpm install && pnpm dev` при поднятом `make dev` — окно с локальным сайтом, внешняя ссылка уходит в браузер
- [ ] 6.2 `git tag v0.1.0 && git push --tags` в `desktop` — Release с dmg/exe/AppImage; установка на своей ОС; `/download` ведёт на файлы
