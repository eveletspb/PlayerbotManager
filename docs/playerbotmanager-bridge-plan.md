# План интеграции PlayerBotManager с mod-multibot-bridge

## Цель

Добавить в клиентский addon выбор транспорта:

1. при наличии и подтверждённой доступности `mod-multibot-bridge` использовать structured MBOT protocol;
2. при отсутствии bridge, отсутствии ответа или неподдерживаемой операции сохранять текущие chat-команды `mod-playerbots`;
3. не ломать существующий UI и не требовать bridge для установки addon.

## Исходное состояние

- Основной legacy transport — `SendChatMessage` через `PBM.SendToBot`, `PBM.SendToGroup` и прямые вызовы в UI.
- Часть административных команд отправляется напрямую (`.playerbots ...`).
- Ответы legacy обрабатываются главным образом через `CHAT_MSG_WHISPER` и текстовые state machines.
- `mod-multibot-bridge` принимает `MBOT\t<opcode>~<payload>` через chat hook.
- Bridge отвечает `HELLO_ACK`, capability frames, `STRATEGY_ACK` и другими structured messages.
- Bridge не является generic executor для произвольных playerbot chat-команд. Поэтому fallback должен быть capability/operation-aware, а не пытаться завернуть legacy command в MBOT.

## Архитектурное решение

Добавить отдельный `PBM_Bridge.lua`, загружаемый до command/UI файлов.

Состояния транспорта:

```text
unknown → probing → available
                   ↘ unavailable
```

- На `PLAYER_LOGIN` отправлять `HELLO` с protocol version `1`.
- Считать bridge доступным только после валидного `HELLO_ACK` и завершённого `CAPS_END`.
- Если handshake ACK не пришёл за короткий timeout — пометить bridge unavailable и использовать legacy. Для уже отправленных bridge writes не выполнять автоматический legacy retry: это предотвращает duplicate mutations.
- Если bridge уже подтверждён, protocol errors не должны молча превращаться в legacy повторную операцию: это предотвращает duplicate writes.
- Ответы должны проверять envelope, opcode, token и размер payload; unknown packets игнорировать.

## Этапы

### Этап 1 — transport foundation

- Добавить `PBM_Bridge.lua`.
- Зарегистрировать chat events для ответов bridge.
- Реализовать MBOT envelope, URL field encoding и request token generation.
- Реализовать handshake, timeout, capabilities и public status API.
- Не менять поведение legacy при отсутствии bridge.

### Этап 2 — безопасная маршрутизация совместимых операций

- Перевести strategy mutations `co +/-name,?` и `nc +/-name,?` на `RUN~STRATEGY~BOT~...` при доступном capability `STRATEGY_MUTATION_V1`.
- Оставить strategy queries (`co ?`, `nc ?`, `ss ?`) на legacy до адаптации structured state parser.
- На `STRATEGY_ACK` не выполнять дополнительную legacy mutation; UI refresh при необходимости запускать отдельным structured GET или legacy read.
- Добавить mapping group scope и structured formation/combat/position/loot/RTI только после проверки UI callback semantics.

### Этап 3 — structured reads

- Добавить parser для `ROSTER`, `ALT_ROSTER`, `STATE(S)`, `DETAIL`, `STATS`, `INVENTORY`, `SPELLBOOK`, framed `BEGIN/ITEM/END` sequences.
- Заменить текстовые whisper state machines только там, где parser и UI model покрывают все success/error/empty cases.
- Закрытый UI не должен открываться от delayed response; token mismatch должен игнорироваться.

### Этап 4 — structured writes и административные операции

- Перевести item/talent/quest/profession/lifecycle operations по одному endpoint за раз.
- Для каждой операции добавить capability gate, token callback, error mapping и postcondition refresh.
- Административные `.playerbots` команды оставить legacy, если для них нет явного bridge endpoint.

### Этап 4a — talents/spec

- Перевести применение talent build на `TALENT_APPLY_V1`.
- Сохранить legacy fallback при отсутствии capability.
- Не повторять write через chat после принятого bridge-запроса, чтобы не получить двойное применение.
- Перевод выбора именованных шаблонов (`talents spec <name>`) выполнять отдельно: bridge endpoint работает по индексу сохранённого spec и требует UI mapping.

### Этап 4b — inventory/equipment

- Перевести чтение инвентаря на framed `INVENTORY_V1` (`INV_BEGIN/ITEM/END`) с адаптацией в существующую модель PBM.
- При таймауте чтения возвращаться к `items`/legacy parser.
- Перевод equip/unequip выполнять отдельным шагом после добавления source bag/slot в модель UI: endpoint требует точную позицию и количество, а текущий агрегированный inventory snapshot её не содержит.

### Этап 5 — QA и документация

- Проверить addon с bridge и без bridge.
- Проверить задержанный/дублированный/неполный/неизвестный ответ, timeout handshake, logout и повторный клик.
- Проверить no-duplicate write при bridge error.
- Обновить README и project context модуля после стабилизации протокола.

## Выполнено в текущей итерации

- Создана отдельная ветка `sbol/playerbotmanager-bridge`.
- Реализован Этап 1: handshake, timeout, capability negotiation, token/payload parsing.
- Реализована часть Этапа 2: strategy mutations и strategy state queries используют structured bridge endpoints при наличии соответствующих capabilities.
- Strategy mutation payload очищает legacy suffix `,?`; ACK/timeout обрабатываются с последующей structured-синхронизацией UI.
- Реализован Этап 4a для применения talent build и именованных talent templates через `TALENT_APPLY_V1`/`TALENT_SPEC_APPLY_V1`.
- Реализован read-path Этапа 4b: inventory snapshot использует `INVENTORY_V1` и существующий UI adapter.
- При таймауте structured state read запрос очищается и запускается legacy `co ?` chain.
- Inventory equip/unequip пока остаются fallback: текущий UI не хранит точные bag/slot/count для безопасного bridge write.
- Legacy stats/who chain для расширенной карточки и остальные неподдерживаемые операции пока остаются fallback.
- Legacy transport остаётся default до подтверждения handshake.
