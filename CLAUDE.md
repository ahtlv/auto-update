# CLAUDE.md — auto-update

Гайд для Claude Code при доработках этого репо. Читай целиком перед изменениями.

## Что это

Распространяемый скилл Claude Code: проверяет всё окружение разработчика
(плагины, MCP-серверы, git-репо/submodules, brew/pip/CLI-тулзы), показывает что
устарело + краткий changelog, обновляет только выбранное. Сделан под раздачу
студентам курса — поэтому **движок не содержит личных компонентов**, у каждого
пользователя свой реестр.

- **Spec:** `~/Work/claude-config/docs/superpowers/specs/2026-06-18-auto-update-skill-design.md`
- **План реализации:** `~/Work/claude-config/docs/superpowers/plans/2026-06-18-auto-update.md`
- Версия: `VERSION` (semver) + git-теги `vX.Y.Z` + `CHANGELOG.md`.

## Архитектура: гибрид + два слоя

**Гибрид:** детерминированную работу (сравнение версий) делает bash-движок;
«умную» (ресёрч changelog, отчёт, решения, APPLY) — Claude по `SKILL.md`.

**Два слоя** (критично для распространения):
- **Движок** = этот репо. Обновляется `git pull`, версионируется, шарится.
- **Реестр пользователя** = `~/.claude/auto-update/registry.conf` (НЕ в репо).
  Создаётся `install.sh`, наполняется фазой DISCOVER, **никогда не затирается**
  обновлением движка. Per-machine: на каждой машине свой.

`install.sh` симлинкует `~/.claude/skills/auto-update → этот репо`.

## Карта файлов

| Файл | Ответственность |
|------|-----------------|
| `SKILL.md` | Оркестрация Claude: 5 фаз (CHECK→DISCOVER→RESEARCH→REPORT→APPLY). Фронтматтер `name: auto-update` + триггеры. |
| `check.sh` | Точка входа. Парсит реестр, диспатчит по типу, печатает TSV. Флаг `--fetch` (refresh маркетплейсов + git fetch). Реестр: `--registry FILE` / `$AU_REGISTRY` / дефолт `~/.claude/auto-update/registry.conf`. |
| `discover.sh` | Находит компоненты НЕ в реестре (git-репо в `~/Work`, плагины). TSV `type⇥name⇥hint`. `$AU_WORK` переопределяет корень. |
| `install.sh` | Идемпотентный bootstrap: симлинк (не затирает чужое), `.git/info/exclude` если линк внутри git-репо, сид реестра из примера, self-update запись. Уважает `$HOME` (для тестов в песочнице). |
| `lib/registry.sh` | `parse_registry FILE` → TSV, 11 колонок фикс-порядка (awk, блочный формат). |
| `lib/compare.sh` | `decide_status INSTALLED LATEST` → OK / OUTDATED / INFO. |
| `lib/checkers.sh` | `check_<type>` по одному на тип + хелперы `_emit`, `_expand_tilde`. |
| `registry.example.conf` | Шаблон с закомментированными образцами всех 6 типов. В репо едет только он, не реальный реестр. |
| `tests/` | Самописный zero-dep раннер (`lib.sh` + `run.sh`), по тест-файлу на модуль. |

## Контракт чекеров (главный инвариант)

Каждая функция `check_<type>` печатает **ровно одну** TSV-строку:
```
status⇥name⇥type⇥installed⇥latest⇥detail
```
`status ∈ {OK, OUTDATED, SKIP, INFO, ERROR}`. Менять контракт — значит править
ВСЕ чекеры + `check.sh` + тесты. Не ломай его.

Типы: `claude-plugin`, `git-repo`, `git-submodule`, `brew`, `pip-venv`, `custom`.
`custom` с опциональным `latest` (команда печатает последнюю версию) покрывает
agent-browser (сравнение) и claude-cli (только installed → INFO).

## Реестр (блочный формат, НЕ YAML)

Один компонент = блок строк `key=value`, блоки разделены пустой строкой,
`#` — коммент, ключ от значения отделяет **первый** `=`. Значения берутся
вербатим (триммится только ключ) → в них можно `=`, пробелы, кавычки, `&&`, `|`.

`parse_registry` отдаёт 11 колонок в порядке:
`name, type, path, parent, venv, marketplace, post_update, check, latest, update, hosts`.
`check.sh` читает их через `cut -f1..10` (НЕ `IFS=read` — bash 3.2 схлопывает
подряд идущие TAB и сдвигает пустые поля). `hosts` (11-я) парсится, но в v0.1.0
не используется (реестр per-machine).

## Как гонять тесты

```bash
bash ~/Work/auto-update/tests/run.sh      # весь сьют; в конце "N tests, 0 failures"
```
TDD-цикл: тест→красный→код→зелёный→коммит. Тесты git-чекеров поднимают реальные
временные репо в `/tmp`; brew/pip/npm — стабятся через PATH. Новый чекер →
добавь `tests/test_<type>.sh` по образцу существующих (раннер сам подхватит
`test_*.sh`).

## Грабли машины (проверено ресёрчем 2026-06-18)

- **bash 3.2.57** (стоковый macOS): нет ассоциативных массивов, `mapfile`,
  bash-4 фич. `_expand_tilde` использует `${1/#\~/$HOME}`.
- **BSD awk** (`/usr/bin/awk`, one-true-awk): только `index/substr/gsub/sub/split/printf`,
  очистка массива `split("",f)`. Без gawk-измов.
- **`npm` → алиас `pnpm`** в шелле Анатоля: всегда `command npm`.
- **agent-browser** под `~/.nvm/versions/node/*/bin/` (версия node хардкодится
  nvm): глоб, не хардкод.
- **brew**: `HOMEBREW_NO_AUTO_UPDATE=1` (иначе ~40с + шум); под `set -e` guard `|| true`.
- **jq**: нужен ТОЛЬКО для `claude-plugin`; нет jq → чекер отдаёт SKIP, остальное работает.
- **`~/.claude/skills`** у Анатоля сам симлинк в `claude-config/skills` → install.sh
  ветвится + пишет в `.git/info/exclude`.
- **plugin latest**: `claude plugin list --available` НЕ годится (прячет
  установленный плагин) — jq-сравнение `installed_plugins.json` vs `marketplace.json`,
  ветка version-pin / git-sha-pin. Офиц. маркетплейс через GCS (нет `.git`).

## 5 фаз (SKILL.md)

1. **CHECK** `check.sh --fetch` → TSV.
2. **DISCOVER** `discover.sh` → спросить → **дописать** блок в реестр (только append).
3. **RESEARCH** по OUTDATED: краткое «что изменилось» + ⚠️ если breaking.
4. **REPORT**: свернуть OK, пронумеровать actionable, ⚠️ breaking, спросить выбор.
5. **APPLY**: обновить только выбранное по типу + `post_update`; отметить что
   требует рестарта Claude (плагины/скиллы). Self-запись `auto-update` → `git pull` движка.

## Backlog (Minor из финального ревью — кандидаты на доработки)

Не блокеры v0.1.0, но при следующей итерации стоит закрыть:
1. **`install.sh` использует `readlink -f`** — его нет на macOS < Ventura (студенты!).
   Фейл безопасен (уходит в WARN, не затирает), но «already linked»/релинк не
   сработают. Добавить fallback (`pwd -P` / python).
2. **`git-submodule`**: lookup `submodule.$name.branch` берёт имя из реестра, а в
   `.gitmodules` секция обычно по PATH. При расхождении `branch=`-трекинг молча
   мимо (fallback на default-ветку — обычно ок). Выводить секцию из subpath или задокументировать.
3. **`check_brew`**: имя формулы интерполируется в `sed` без экранирования — ломается
   на tap-именах с `/`. Бэр-формулы ок.
4. **submodule `latest`-колонка** несёт имя ветки, а git-repo — SHA (косметика).
5. **`--fetch` refresh и discover-плагины** не покрыты юнит-тестами (guarded `command -v`).

## Конвенции

- DRY/YAGNI/TDD, частые коммиты, по одному деливераблу на задачу.
- Движок остаётся **без личных данных** — личное только в `~/.claude/auto-update/registry.conf`.
- Менять формат реестра/контракт чекеров — только синхронно во всех потребителях + тестах.
