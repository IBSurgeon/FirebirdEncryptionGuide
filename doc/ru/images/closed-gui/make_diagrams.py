"""Makes the SVG diagrams of the guide "Encryption for an application without source code".

Run:  python make_diagrams.py
The script writes the *.svg files next to itself. Edit the diagrams here, not in the SVG files.

The font list starts with "Noto Serif": asciidoctor-pdf has this font with Cyrillic letters.
A browser that has no such font takes the next one.
"""
from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path(__file__).parent
FONT = "Noto Serif, Segoe UI, Arial, sans-serif"

# Colours
INK = "#1f2933"
LINE = "#52606d"
BLUE = "#dbeafe"
BLUE_EDGE = "#3b82f6"
GREEN = "#dcfce7"
GREEN_EDGE = "#16a34a"
YELLOW = "#fef9c3"
YELLOW_EDGE = "#ca8a04"
RED = "#fee2e2"
RED_EDGE = "#dc2626"
GREY = "#f1f5f9"
GREY_EDGE = "#94a3b8"
STEP = 19   # distance between text lines


class Svg:
    def __init__(self, width: int, height: int):
        self.width, self.height = width, height
        self.items: list[str] = []

    def rect(self, x, y, w, h, fill=GREY, edge=GREY_EDGE, radius=6, dash=False, width=1.2):
        d = ' stroke-dasharray="6 4"' if dash else ""
        self.items.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}" '
                          f'stroke="{edge}" stroke-width="{width}"{d}/>')

    def text(self, x, y, text, size=14, anchor="middle", bold=False, color=INK, italic=False):
        """Text with line breaks. y is the baseline of the first line."""
        weight = ' font-weight="bold"' if bold else ""
        style = ' font-style="italic"' if italic else ""
        for i, line in enumerate(str(text).split("\n")):
            self.items.append(f'<text x="{x}" y="{y + i * STEP}" font-family="{FONT}" font-size="{size}" '
                              f'text-anchor="{anchor}" fill="{color}"{weight}{style}>{escape(line)}</text>')

    def box(self, x, y, w, h, text, fill=GREY, edge=GREY_EDGE, size=14, bold=False, dash=False):
        self.rect(x, y, w, h, fill, edge, dash=dash)
        lines = str(text).split("\n")
        first = y + h / 2 - (len(lines) - 1) * STEP / 2 + size * 0.35
        self.text(x + w / 2, first, text, size=size, bold=bold)

    def line(self, x1, y1, x2, y2, color=LINE, dash=False, width=1.4, arrow=True):
        d = ' stroke-dasharray="6 4"' if dash else ""
        marker = ' marker-end="url(#arrow)"' if arrow else ""
        self.items.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" '
                          f'stroke-width="{width}"{d}{marker}/>')

    def save(self, name: str) -> None:
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="{self.height}" '
                f'viewBox="0 0 {self.width} {self.height}">\n'
                '<defs><marker id="arrow" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto">'
                f'<path d="M0,0 L10,4 L0,8 z" fill="{LINE}"/></marker></defs>\n'
                f'<rect x="0" y="0" width="{self.width}" height="{self.height}" fill="#ffffff"/>\n')
        (OUT / name).write_text(head + "\n".join(self.items) + "\n</svg>\n", encoding="utf-8", newline="\n")
        print(name)


FILLS = {"blue": (BLUE, BLUE_EDGE), "green": (GREEN, GREEN_EDGE), "yellow": (YELLOW, YELLOW_EDGE),
         "red": (RED, RED_EDGE), "grey": (GREY, GREY_EDGE)}


def sequence(name: str, participants: list[tuple[str, str]], steps: list[tuple], width: int = 980) -> None:
    """Sequence diagram.

    participants: (label, colour key) from left to right.
    steps: ("msg", from, to, text)  solid arrow, a call
           ("ret", from, to, text)  dashed arrow, an answer
           ("self", who, text)      action of one participant
           ("note", from, to, text, colour key)
           ("gap", text)            divider with a title
    Arrows and actions get numbers.
    """
    n = len(participants)
    margin = 80
    xs = [margin + i * (width - 2 * margin) / (n - 1) for i in range(n)]
    top = 16
    head_h = 50
    y = top + head_h + 26

    heights = []
    for step in steps:
        kind = step[0]
        if kind == "gap":
            heights.append(40)
            continue
        text = step[3] if kind in ("msg", "ret", "note") else step[2]
        lines = text.count("\n") + 1
        if kind == "note":
            heights.append(lines * STEP + 30)
        elif kind == "self":
            heights.append(lines * STEP + 28)
        else:
            heights.append(lines * STEP + 24)
    total = y + sum(heights) + 20
    svg = Svg(width, int(total))

    for (label, colour), x in zip(participants, xs):
        fill, edge = FILLS[colour]
        svg.line(x, top + head_h, x, total - 12, color=GREY_EDGE, dash=True, width=1, arrow=False)
        svg.box(x - 70, top, 140, head_h, label, fill, edge, size=14, bold=True)

    number = 0
    for step, h in zip(steps, heights):
        kind = step[0]
        if kind == "gap":
            svg.line(20, y + 18, width - 20, y + 18, color=GREY_EDGE, dash=True, width=1, arrow=False)
            half = 12 + len(step[1]) * 4.4
            svg.rect(width / 2 - half, y + 5, 2 * half, 26, "#ffffff", GREY_EDGE, radius=13, width=1)
            svg.text(width / 2, y + 23, step[1], size=14, italic=True)
        elif kind == "note":
            _, a, b, text, colour = step
            fill, edge = FILLS[colour]
            x1, x2 = sorted((xs[a], xs[b]))
            lines = text.count("\n") + 1
            svg.box(x1 - 70, y + 4, x2 - x1 + 140, 12 + lines * STEP, text, fill, edge, size=14)
        elif kind == "self":
            _, who, text = step
            number += 1
            x = xs[who]
            lines = text.count("\n") + 1
            box_w = 300
            left = x + 14 if x + 14 + box_w < width - 6 else x - 14 - box_w
            svg.box(left, y + 2, box_w, 10 + lines * STEP, f"{number}. {text}", "#ffffff", LINE, size=14)
        else:
            _, a, b, text = step
            number += 1
            lines = text.count("\n") + 1
            mid = (xs[a] + xs[b]) / 2
            svg.text(mid, y + 14, f"{number}. {text}", size=14)
            arrow_y = y + lines * STEP + 6
            pad = 4 if xs[b] > xs[a] else -4
            svg.line(xs[a] + pad, arrow_y, xs[b] - pad, arrow_y, dash=(kind == "ret"))
        y += h
    svg.save(name)


# --------------------------------------------------------------------------- 1. components
def components() -> None:
    svg = Svg(940, 500)
    svg.rect(20, 20, 400, 400, "#ffffff", GREY_EDGE, dash=True)
    svg.text(220, 46, "Рабочее место", size=16, bold=True)
    svg.rect(520, 20, 400, 400, "#ffffff", GREY_EDGE, dash=True)
    svg.text(720, 46, "Сервер", size=16, bold=True)

    left = [("Приложение\n(нет кода шифрования)", GREY, GREY_EDGE),
            ("fbclient.dll", BLUE, BLUE_EDGE),
            ("plugins\\keyholder.dll\nKeyHolder клиента", BLUE, BLUE_EDGE),
            ("KeySource.dll\nваша библиотека: отдаёт ключ", YELLOW, YELLOW_EDGE)]
    right = [("firebird.exe", GREEN, GREEN_EDGE),
             ("plugins\\keyholder.dll\nKeyHolder сервера", GREEN, GREEN_EDGE),
             ("plugins\\dbcrypt.dll и DbCrypt.conf\nDbCrypt и лицензия", GREEN, GREEN_EDGE),
             ("employee.fdb\nстраницы зашифрованы", RED, RED_EDGE)]
    for column, x in ((left, 60), (right, 560)):
        for i, (text, fill, edge) in enumerate(column):
            y = 66 + i * 88
            svg.box(x, y, 320, 58, text, fill, edge, size=14)
            if i < len(column) - 1:
                svg.line(x + 160, y + 58, x + 160, y + 86)
    svg.line(380, 183, 558, 97)
    svg.text(470, 176, "SQL и ключ:", size=13)
    svg.text(470, 194, "в зашифрованном", size=13)
    svg.text(470, 212, "виде", size=13)
    svg.text(220, 448, "Ключ находится только здесь", size=14, bold=True)
    svg.text(720, 448, "Ключей на диске сервера нет.", size=14, bold=True)
    svg.text(720, 470, "Каждое подключение приносит ключ", size=14)
    svg.save("components.svg")


# --------------------------------------------------------------------------- 2. network connection
def seq_remote() -> None:
    sequence("seq-remote.svg", [
        ("Приложение", "grey"), ("fbclient.dll", "blue"), ("KeyHolder\nклиента", "blue"),
        ("KeySource.dll", "yellow"), ("Сервер\nFirebird", "green"), ("KeyHolder\nсервера", "green"),
        ("DbCrypt", "green"),
    ], [
        ("note", 0, 3, "Рабочее место: один процесс приложения", "grey"),
        ("msg", 0, 1, "подключение"),
        ("msg", 1, 4, "подключение, проверка пользователя"),
        ("msg", 4, 5, "база зашифрована:\nнужен ключ Red"),
        ("ret", 4, 1, "запрос ключа у клиента (op_crypt_key_callback)"),
        ("msg", 1, 2, "создать плагин"),
        ("msg", 2, 3, "LoadLibrary,\nMakeKeys()"),
        ("ret", 3, 2, "Key=Red 0x..,"),
        ("self", 2, "FreeLibrary: KeySource.dll\nвыгружена из процесса"),
        ("msg", 2, 5, "ключи в зашифрованном виде (через fbclient.dll и сервер)"),
        ("msg", 5, 6, "ключ Red,\nзащищённо"),
        ("self", 6, "проверка ключа,\nрасшифровка страниц"),
        ("ret", 4, 0, "подключение установлено"),
    ], width=1100)


# --------------------------------------------------------------------------- 3. embedded
def seq_embedded() -> None:
    sequence("seq-embedded.svg", [
        ("Приложение", "grey"), ("fbclient.dll", "blue"), ("Движок\nengine13.dll", "green"),
        ("KeyHolder", "green"), ("KeySource.dll", "yellow"), ("DbCrypt", "green"),
    ], [
        ("note", 0, 5, "Один процесс приложения. Сервера и сети нет", "grey"),
        ("msg", 0, 1, "подключение"),
        ("msg", 1, 2, "Providers = Engine13:\nзагрузить движок"),
        ("self", 2, "открыть файл базы:\nбаза зашифрована, ключ Red"),
        ("msg", 2, 3, "создать плагин"),
        ("msg", 3, 4, "LoadLibrary,\nMakeKeys()"),
        ("ret", 4, 3, "Key=Red 0x..,"),
        ("self", 3, "FreeLibrary: KeySource.dll\nвыгружена из процесса"),
        ("msg", 3, 5, "ключ Red, защищённый обмен"),
        ("self", 5, "проверка лицензии и ключа,\nрасшифровка страниц"),
        ("ret", 2, 0, "подключение установлено"),
    ], width=1040)


# --------------------------------------------------------------------------- 4. life of the library
def dll_life() -> None:
    svg = Svg(960, 400)
    svg.text(20, 30, "Варианты «а», «б», «в»: библиотека загружается и выгружается при каждом подключении",
             size=14, anchor="start", bold=True)
    x = 20
    for n in (1, 2, 3):
        svg.text(x + 150, 62, f"подключение {n}", size=13, italic=True)
        svg.box(x, 72, 92, 44, "LoadLibrary", BLUE, BLUE_EDGE, size=12)
        svg.box(x + 98, 72, 108, 44, "MakeKeys()", YELLOW, YELLOW_EDGE, size=12)
        svg.box(x + 212, 72, 90, 44, "FreeLibrary", GREY, GREY_EDGE, size=12)
        x += 314
    svg.text(20, 142, "Глобальные переменные библиотеки не сохраняются между вызовами.", size=13, anchor="start")

    svg.text(20, 196, "Вариант «г»: библиотека закрепляет себя в процессе и хранит кэш",
             size=14, anchor="start", bold=True)
    svg.text(170, 228, "подключение 1", size=13, italic=True)
    svg.box(20, 238, 92, 62, "LoadLibrary", BLUE, BLUE_EDGE, size=12)
    svg.box(118, 238, 190, 62, "MakeKeys():\nзапрос к службе,\nPinLibrary", YELLOW, YELLOW_EDGE, size=12)
    svg.box(314, 238, 112, 62, "FreeLibrary:\nне выгружает", GREY, GREY_EDGE, size=12)
    svg.text(545, 228, "подключение 2", size=13, italic=True)
    svg.box(465, 238, 160, 62, "MakeKeys():\nключ из кэша", YELLOW, YELLOW_EDGE, size=12)
    svg.text(765, 228, "подключение 3", size=13, italic=True)
    svg.box(685, 238, 160, 62, "MakeKeys():\nключ из кэша", YELLOW, YELLOW_EDGE, size=12)
    svg.rect(118, 316, 822, 30, GREEN, GREEN_EDGE)
    svg.text(529, 336, "KeySource.dll остаётся в памяти процесса до его завершения; кэш действует CacheSeconds",
             size=13)
    svg.text(20, 376, "Библиотека не создаёт потоков. Кэш защищён критической секцией.", size=13, anchor="start")
    svg.save("dll-life.svg")


# --------------------------------------------------------------------------- 5. variants A and B
def variants_ab() -> None:
    svg = Svg(940, 330)
    svg.rect(20, 20, 400, 290, "#ffffff", GREY_EDGE, dash=True)
    svg.text(220, 48, "а) ключ в библиотеке", size=16, bold=True)
    svg.rect(60, 80, 320, 150, YELLOW, YELLOW_EDGE)
    svg.text(220, 106, "KeySource.dll", size=14, bold=True)
    svg.box(90, 126, 260, 70, "константа в коде:\nKey=Red 0xec,0xa1,…", "#ffffff", YELLOW_EDGE, size=13)
    svg.text(220, 262, "Настроек нет. Ключ можно", size=13)
    svg.text(220, 281, "прочитать из файла dll", size=13)

    svg.rect(480, 20, 440, 290, "#ffffff", GREY_EDGE, dash=True)
    svg.text(700, 48, "б) ключ в файле", size=16, bold=True)
    svg.box(500, 80, 170, 60, "KeySource.dll", YELLOW, YELLOW_EDGE, size=14, bold=True)
    svg.box(500, 180, 170, 76, "KeySource.ini\nKeyFile=E:\\keys\\\nemployee.key", GREY, GREY_EDGE, size=12)
    svg.box(730, 100, 170, 110, "employee.key\n\nKey=Red 0xec,…", RED, RED_EDGE, size=13)
    svg.line(585, 140, 585, 178)
    svg.text(596, 164, "путь", size=12, anchor="start")
    svg.line(670, 112, 728, 140)
    svg.text(700, 104, "читает", size=12)
    svg.text(815, 236, "съёмный диск или", size=13)
    svg.text(815, 255, "папка с правами доступа", size=13)
    svg.text(700, 296, "Файл читается при каждом подключении", size=13)
    svg.save("variants-ab.svg")


# --------------------------------------------------------------------------- 6. key provider
def seq_provider() -> None:
    sequence("seq-provider.svg", [
        ("Приложение\nи KeyHolder", "grey"), ("KeySource.dll\nвариант «в»", "yellow"),
        ("KeyProvider.exe\nв трее", "green"), ("Пользователь", "blue"),
    ], [
        ("gap", "первое подключение"),
        ("msg", 0, 1, "LoadLibrary, MakeKeys()"),
        ("self", 1, "канал не найден:\nзапустить KeyProvider.exe"),
        ("msg", 1, 2, "канал:  GETKEYS 1 <pid> <программа>"),
        ("msg", 2, 3, "ключа в памяти нет: окно ввода"),
        ("ret", 3, 2, "парольная фраза или ключ 0x..,"),
        ("self", 2, "проверить ввод,\nсохранить ключ в памяти"),
        ("ret", 2, 1, "OK  +  Key=Red 0x..,"),
        ("ret", 1, 0, "текст ключей; FreeLibrary"),
        ("gap", "следующие подключения"),
        ("msg", 0, 1, "LoadLibrary, MakeKeys()"),
        ("msg", 1, 2, "канал:  GETKEYS 1 <pid> <программа>"),
        ("ret", 2, 1, "OK  +  Key=Red 0x..,  (из памяти)"),
        ("ret", 1, 0, "текст ключей; FreeLibrary"),
    ], width=1000)


# --------------------------------------------------------------------------- 7. REST
def seq_rest() -> None:
    sequence("seq-rest.svg", [
        ("Приложение\nи KeyHolder", "grey"), ("KeySource.dll\nвариант «г»", "yellow"),
        ("Служба ключей\nHTTPS", "green"),
    ], [
        ("gap", "первое подключение"),
        ("msg", 0, 1, "LoadLibrary, MakeKeys()"),
        ("msg", 1, 2, "GET /keys/Red\nAuthorization: Bearer <токен>"),
        ("self", 2, "проверить токен,\nзаписать запрос в журнал"),
        ("ret", 2, 1, "200  Key=Red 0x..,"),
        ("self", 1, "PinLibrary: dll остаётся в процессе;\nключ сохранён в памяти"),
        ("ret", 1, 0, "текст ключей"),
        ("gap", "следующие подключения, пока не истёк CacheSeconds"),
        ("msg", 0, 1, "MakeKeys()"),
        ("self", 1, "ключ из памяти,\nсети нет"),
        ("ret", 1, 0, "текст ключей"),
    ], width=900)


# --------------------------------------------------------------------------- 8. deployment
def deploy() -> None:
    svg = Svg(1000, 560)
    svg.text(190, 30, "Откуда", size=16, bold=True)
    svg.text(750, 30, "Куда", size=16, bold=True)
    sources = [
        (50, "github.com/FirebirdSQL/firebird\nFirebird-<версия>-x64.zip\nскрипт 01", BLUE, BLUE_EDGE),
        (200, "cc.ib-aid.com\nCryptPlugin-FB_<NN>_WINDOWS_64bit.zip\nкаталоги Server и Client\\64bit,\nпробная лицензия DbCrypt.conf\nскрипты 02 и 03", GREEN, GREEN_EDGE),
        (400, "Программы примера: work\\build\nEmployeeRemote.exe, EmployeeEmbedded.exe,\nKeySource.dll, KeyProvider.exe\nскрипт 30 или 05", YELLOW, YELLOW_EDGE),
    ]
    targets = [
        (50, "Сервер: work\\fb<N>\\server  (скрипт 10)\nFirebird целиком + Server\\*\n+ plugins\\DbCrypt.conf\nключей нет", GREY, GREY_EDGE),
        (210, "Рабочее место: work\\fb<N>\\remote  (скрипт 40)\nClient\\64bit\\* + plugins\\keyholder.dll\n+ KeySource.dll + EmployeeRemote.exe\nfirebird.conf: KeyHolderPlugin = KeyHolder", GREY, GREY_EDGE),
        (380, "Embedded: work\\fb<N>\\embedded  (скрипт 41)\nClient\\64bit\\* + keyholder.dll + dbcrypt.dll\n+ engine12/13.dll + intl + DbCrypt.conf\n+ KeySource.dll + EmployeeEmbedded.exe\n+ своя копия базы", GREY, GREY_EDGE),
    ]
    ends_s, ends_t = [], []
    for y, text, fill, edge in sources:
        h = 22 + (text.count("\n") + 1) * STEP
        svg.box(20, y, 340, h, text, fill, edge, size=13)
        ends_s.append((360, y + h / 2))
    for y, text, fill, edge in targets:
        h = 22 + (text.count("\n") + 1) * STEP
        svg.box(540, y, 440, h, text, fill, edge, size=13)
        ends_t.append((538, y + h / 2))
    for a, b in [(0, 0), (0, 2), (1, 0), (1, 1), (1, 2), (2, 1), (2, 2)]:
        svg.line(ends_s[a][0], ends_s[a][1], ends_t[b][0], ends_t[b][1])
    svg.save("deploy.svg")


# --------------------------------------------------------------------------- 9. where the key is
def key_location() -> None:
    columns = ["Диск\nрабочего места", "Память\nприложения", "Другая программа\nили компьютер", "Сеть"]
    rows = [
        ("а) ключ в библиотеке", [("да: внутри dll", RED), ("на время\nподключения", YELLOW), ("нет", GREEN), ("нет", GREEN)]),
        ("б) ключ в файле", [("да: в файле ключа", RED), ("на время\nподключения", YELLOW), ("нет", GREEN),
                              ("если файл\nв сетевой папке", YELLOW)]),
        ("в) поставщик ключа", [("нет", GREEN), ("на время\nподключения", YELLOW),
                                 ("память\nKeyProvider.exe", YELLOW), ("нет", GREEN)]),
        ("г) служба REST", [("только токен", YELLOW), ("кэш в dll:\nCacheSeconds", YELLOW),
                             ("служба ключей", YELLOW), ("HTTPS до службы\nключей", YELLOW)]),
        ("Prompt (без dll)", [("нет", GREEN), ("до выхода\nиз приложения", YELLOW), ("нет", GREEN), ("нет", GREEN)]),
    ]
    left, top, cw, ch, hw = 20, 20, 180, 58, 200
    svg = Svg(left + hw + cw * len(columns) + 20, top + ch * (len(rows) + 1) + 60)
    for i, name in enumerate(columns):
        svg.box(left + hw + i * cw, top, cw, ch, name, GREY, GREY_EDGE, size=13, bold=True)
    for r, (name, cells) in enumerate(rows):
        y = top + ch * (r + 1)
        svg.box(left, y, hw, ch, name, GREY, GREY_EDGE, size=13, bold=True)
        for i, (text, fill) in enumerate(cells):
            svg.box(left + hw + i * cw, y, cw, ch, text, fill, GREY_EDGE, size=13)
    y = top + ch * (len(rows) + 1) + 26
    svg.text(left, y, "Во всех вариантах ключ идёт к серверу базы данных в зашифрованном виде", size=13, anchor="start")
    svg.text(left, y + STEP, "и находится в памяти сервера, пока открыто подключение.", size=13, anchor="start")
    svg.save("key-location.svg")


if __name__ == "__main__":
    components()
    seq_remote()
    seq_embedded()
    dll_life()
    variants_ab()
    seq_provider()
    seq_rest()
    deploy()
    key_location()
