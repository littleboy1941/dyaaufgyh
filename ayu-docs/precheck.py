#!/usr/bin/env python3
"""Проверки перед сборкой: то, что ловится глазами, но стоит часа CI.

Запуск: python3 ayu-docs/precheck.py

Проверяет только наши файлы (изменённые относительно upstream-коммита или переданные
аргументами) и только те ошибки, на которых мы уже обожглись:

1. Разорванные строковые литералы и несбалансированные скобки — сборка 35423213616
   умерла на 1 ч 13 мин из-за настоящего переноса строки вместо \\n.
2. Порядок записей на экране настроек AyuGram. ItemListControllerNode.swift делает
   assert(entries[i-1].isLessThan(entries[i])), то есть список обязан идти строго по
   возрастанию stableId. Нарушение роняет приложение при открытии экрана, а компилятор
   об этом молчит.
"""

import io
import re
import subprocess
import sys

CONTROLLER = "submodules/SettingsUI/Sources/AyuSettingsController.swift"


def changed_swift_files():
    if len(sys.argv) > 1:
        return [f for f in sys.argv[1:] if f.endswith(".swift")]
    try:
        out = subprocess.check_output(
            ["git", "diff", "--name-only", "6ad963e5", "HEAD"], text=True
        )
    except subprocess.CalledProcessError:
        out = subprocess.check_output(["git", "diff", "--name-only", "HEAD"], text=True)
    return [f for f in out.split() if f.endswith(".swift")]


def strip_comments_and_strings(source):
    """Выкидывает комментарии и содержимое строк: скобки внутри них считать нельзя.

    Возвращает (код без строк и комментариев, номера строк с незакрытым литералом).
    """
    out = []
    unterminated = []
    line = 1
    i = 0
    n = len(source)
    while i < n:
        c = source[i]
        if c == "\n":
            out.append(c)
            line += 1
            i += 1
        elif source.startswith("//", i):
            while i < n and source[i] != "\n":
                i += 1
        elif source.startswith("/*", i):
            depth = 1
            i += 2
            while i < n and depth:
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    if source[i] == "\n":
                        line += 1
                        out.append("\n")
                    i += 1
        elif source.startswith('"""', i):
            i += 3
            while i < n and not source.startswith('"""', i):
                if source[i] == "\n":
                    line += 1
                    out.append("\n")
                i += 1
            i += 3
        elif c == '"':
            start_line = line
            i += 1
            closed = False
            while i < n:
                if source[i] == "\\":
                    i += 2
                    continue
                if source[i] == '"':
                    closed = True
                    i += 1
                    break
                if source[i] == "\n":
                    break
                i += 1
            if not closed:
                unterminated.append(start_line)
        else:
            out.append(c)
            i += 1
    return "".join(out), unterminated


def check_syntax(paths):
    problems = []
    for path in paths:
        try:
            source = io.open(path, encoding="utf-8").read()
        except OSError:
            continue
        code, unterminated = strip_comments_and_strings(source)
        for line in unterminated:
            problems.append(
                "%s:%d: незакрытый строковый литерал (настоящий перенос строки вместо \\n?)"
                % (path, line)
            )
        if code.count("{") != code.count("}"):
            problems.append("%s: не сходятся фигурные скобки" % path)
        if code.count("(") != code.count(")"):
            problems.append("%s: не сходятся круглые скобки" % path)
    return problems


def check_settings_order():
    """Собирает порядок записей так же, как ayuSettingsEntries, и сверяет stableId."""
    source = io.open(CONTROLLER, encoding="utf-8").read()

    enum_body = re.search(
        r"private enum AyuSettingsToggle: Int32 \{(.*?)\n    var keyPath", source, re.S
    ).group(1)
    raw_values = {
        name: index
        for index, name in enumerate(re.findall(r"^    case (\w+)", enum_body, re.M))
    }

    stable_body = re.search(r"var stableId: Int32 \{(.*?)\n    \}\n", source, re.S).group(1)
    toggle_switch = re.search(r"switch toggle \{(.*?)\n            \}", stable_body, re.S).group(1)

    toggle_ids = {
        name: int(value)
        for name, value in re.findall(r"case \.(\w+):\s*\n\s*return (\d+)", toggle_switch)
    }
    # то, что попадает в `default: return 100 + toggle.rawValue`
    for name, index in raw_values.items():
        toggle_ids.setdefault(name, 100 + index)

    entry_ids = {
        name: int(value)
        for name, value in re.findall(
            r"case \.(\w+):\s*\n\s*return (\d+)", stable_body.replace(toggle_switch, "")
        )
    }

    entries_fn = re.search(r"private func ayuSettingsEntries.*?\n\}", source, re.S).group(0)
    sequence = []
    for line in entries_fn.split("\n"):
        match = re.search(r"entries\.append\(\.toggle\(\.(\w+)", line)
        if match:
            sequence.append((match.group(1), toggle_ids[match.group(1)]))
            continue
        match = re.search(r"entries\.append\(\.(\w+)\)", line)
        if match:
            sequence.append((match.group(1), entry_ids[match.group(1)]))
            continue
        match = re.search(r"(?:\[AyuSettingsToggle\] = |for toggle in )\[(.*?)\]", line)
        if match:
            for name in re.findall(r"\.(\w+)", match.group(1)):
                sequence.append((name, toggle_ids[name]))

    problems = []
    for i in range(1, len(sequence)):
        if sequence[i][1] <= sequence[i - 1][1]:
            problems.append(
                "порядок записей настроек нарушен: %s (%d) идёт после %s (%d) — приложение упадёт на открытии экрана"
                % (sequence[i][0], sequence[i][1], sequence[i - 1][0], sequence[i - 1][1])
            )
    ids = [stable_id for _, stable_id in sequence]
    if len(ids) != len(set(ids)):
        problems.append("у записей настроек есть одинаковые stableId")
    return sequence, problems


def main():
    paths = changed_swift_files()
    problems = check_syntax(paths)
    sequence, order_problems = check_settings_order()
    problems += order_problems

    print("проверено файлов: %d, записей на экране настроек: %d" % (len(paths), len(sequence)))
    if problems:
        print("\nНАЙДЕНО:")
        for problem in problems:
            print("  - " + problem)
        return 1
    print("чисто")
    return 0


if __name__ == "__main__":
    sys.exit(main())
