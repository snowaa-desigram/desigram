# architecture-core Specification

## Purpose

Фиксирует единую структуру bounded context, слои и нейминг классов в Symfony core, чтобы любой контекст читался одинаково и связи между ними были видны из дерева файлов.

## Requirements

### Requirement: Дерево bounded context фиксировано
Каждый контекст `src/<Context>/` SHALL использовать только следующие папки; папка создаётся, когда в ней появляется первый класс:

```
src/<Context>/
  Domain/
    Model/            <Aggregate>.php (extends Shared\Domain\AggregateRoot), сущности
    ValueObject/      неизменяемые значения (Email, Money, …)
    Event/            <Something>Happened.php (implements DomainEvent), прошедшее время
    Repository/       <Aggregate>Repository.php — интерфейс
    Exception/        доменные исключения (extends ApplicationException-наследников не допускается)
  Application/
    Command/<Name>/   <Name>Command.php + <Name>Handler.php
    Query/<Name>/     <Name>Query.php + <Name>Handler.php + <Name>Result.php
    Port/             <Name>Gateway.php | <Name>Notifier.php | <Name>Client.php — интерфейсы к внешним системам
    EventSubscriber/  <Do>When<Event>.php — класс с атрибутом EventSubscriber и __invoke(<Event>)
  Infrastructure/
    Grpc/             Grpc<Port>.php (extends GrpcGateway) — реализация Port через gRPC
    Persistence/Doctrine/  Doctrine<Aggregate>Repository.php (extends CachedRepository)
    <Other>/          иные адаптеры (Http/, Messenger/, …) — по имени технологии
  Presentation/
    Http/             <Name>Controller.php — один экшен, __invoke, только вызов шины
```

#### Scenario: Добавляется новый контекст
- **WHEN** в `src/` появляется папка `<Context>/`
- **THEN** внутри неё есть только `Domain`, `Application`, `Infrastructure`, `Presentation`, а внутри них — только перечисленные подпапки; `composer lint` (deptrac) и `composer test` (архитектурные тесты) проходят

#### Scenario: Класс положен не в свою папку
- **WHEN** обработчик команды лежит в `Application/<Name>Handler.php` (не в `Command/<Name>/`) или контроллер — вне `Presentation/Http/`
- **THEN** архитектурный тест нейминга падает с указанием файла и ожидаемого пути

### Requirement: Нейминг классов однозначно указывает роль
Имена классов SHALL соответствовать роли: `*Command`/`*Query` — сообщения, `*Handler` — обработчики (в той же папке, что и сообщение), `*Result` — ответ запроса, `*Controller` — HTTP-вход, `*Gateway`/`*Notifier`/`*Client` — порты, `Grpc*`/`Doctrine*`/`Http*` — реализации портов и репозиториев с префиксом технологии, `*Happened`/прошедшее время — доменные события, `InMemory*`/`Spy*`/`Fake*` — тестовые подмены в `tests/Fake/`.

#### Scenario: Реализация порта названа без префикса технологии
- **WHEN** в `Infrastructure/Grpc/` появляется класс `PingGatewayImpl`
- **THEN** архитектурный тест нейминга падает: реализации портов в `Infrastructure/<Tech>/` MUST начинаться с `<Tech>`

### Requirement: Направление зависимостей и изоляция контекстов
Слои MUST зависеть только вниз: `Presentation → Application → Domain`, `Infrastructure → Application, Domain`; `Domain` ни от чего. Контекст MUST NOT импортировать классы другого контекста — связь только через события (`EventBus`) или `Shared`.

#### Scenario: Контроллер обращается к репозиторию напрямую
- **WHEN** класс из `Presentation/` импортирует класс из `Infrastructure/` или `Domain/Repository`
- **THEN** `composer lint` (deptrac) падает

#### Scenario: Контекст A импортирует контекст B
- **WHEN** класс из `src/Notification/` использует класс из `src/Ping/`
- **THEN** `ContextIsolationTest` падает

### Requirement: Тесты повторяют структуру src
Тесты SHALL лежать в `tests/<Context>/<Layer>/<Name>Test.php`, зеркально к `src`; общие подмены — в `tests/Fake/`; архитектурные проверки — в `tests/Architecture/`.

#### Scenario: Новый хендлер получает тест
- **WHEN** добавлен `src/Media/Application/Command/Upload/UploadHandler.php`
- **THEN** тест лежит в `tests/Media/Application/UploadHandlerTest.php`, внешние порты подменены фейками из `tests/Fake/`
