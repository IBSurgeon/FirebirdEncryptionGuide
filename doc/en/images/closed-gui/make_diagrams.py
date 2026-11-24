"""Makes the SVG diagrams of the guide "Encryption for a closed-source application" (English version).

Run:  python make_diagrams.py
The script writes the *.svg files next to itself. Edit the diagrams here, not in the SVG files.

The font list starts with "Noto Serif": asciidoctor-pdf has this font.
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
KEY = "#b45309"   # thick line: the way of the key
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

    def card(self, x, y, w, h, title, lines, fill=GREY, edge=GREY_EDGE, dash=False, size=13):
        """Box with a bold title and small lines under it."""
        self.rect(x, y, w, h, fill, edge, dash=dash)
        self.text(x + w / 2, y + 24, title, size=14, bold=True)
        for i, text in enumerate(lines):
            self.text(x + w / 2, y + 44 + i * 18, text, size=size)

    def badge(self, x, y, number, color=INK):
        """Number of a step in a circle."""
        self.items.append(f'<circle cx="{x}" cy="{y}" r="10" fill="{color}"/>')
        self.text(x, y + 4.5, str(number), size=12, bold=True, color="#ffffff")

    def line(self, x1, y1, x2, y2, color=LINE, dash=False, width=1.4, arrow=True, key=False):
        """key=True: thick line, the way of the key."""
        if key:
            color, width = KEY, 3
        d = ' stroke-dasharray="6 4"' if dash else ""
        marker = f' marker-end="url(#{"arrowkey" if key else "arrow"})"' if arrow else ""
        self.items.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" '
                          f'stroke-width="{width}"{d}{marker}/>')

    def save(self, name: str) -> None:
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="{self.height}" '
                f'viewBox="0 0 {self.width} {self.height}">\n'
                '<defs><marker id="arrow" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto">'
                f'<path d="M0,0 L10,4 L0,8 z" fill="{LINE}"/></marker>'
                '<marker id="arrowkey" markerUnits="userSpaceOnUse" markerWidth="14" markerHeight="12" refX="12" '
                f'refY="6" orient="auto"><path d="M0,0 L14,6 L0,12 z" fill="{KEY}"/></marker></defs>\n'
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
    svg = Svg(1000, 870)
    svg.rect(20, 20, 410, 564, "#ffffff", GREY_EDGE, dash=True)
    svg.text(225, 46, "Workstation: application folder", size=16, bold=True)
    svg.rect(570, 20, 410, 564, "#ffffff", GREY_EDGE, dash=True)
    svg.text(775, 46, "Server: Firebird folder", size=16, bold=True)

    rows = [64, 170, 276, 382, 488]
    lx, rx, w, h = 45, 595, 360, 76
    left = [
        ("Application", ["calls the usual Firebird functions,", "knows nothing about encryption"], GREY, GREY_EDGE, False),
        ("fbclient.dll", ["Firebird client library", "firebird.conf: KeyHolderPlugin = KeyHolder"],
         BLUE, BLUE_EDGE, False),
        ("plugins\\keyholder.dll", ["client KeyHolder plugin:", "gets the key from KeySource.dll"],
         BLUE, BLUE_EDGE, False),
        ("KeySource.dll", ["your library:", "function MakeKeys returns the key"], YELLOW, YELLOW_EDGE, False),
        ("Key source", ["library code, file, person at the screen", "or key server: four variants"],
         RED, RED_EDGE, False),
    ]
    right = [
        ("No keys on the server disk", ["no KeyHolder.conf file with keys,", "no KeySource.dll library"],
         "#ffffff", GREY_EDGE, True),
        ("firebird.exe", ["Firebird server", "firebird.conf: KeyHolderPlugin = KeyHolder"], GREEN, GREEN_EDGE, False),
        ("plugins\\keyholder.dll", ["server KeyHolder plugin: gets the key,", "keeps it in connection memory"],
         GREEN, GREEN_EDGE, False),
        ("plugins\\dbcrypt.dll + DbCrypt.conf", ["DbCrypt plugin and license file:", "encrypts and decrypts pages"],
         GREEN, GREEN_EDGE, False),
        ("Database file", ["EMPLOYEE.FDB:", "all pages are encrypted"], GREY, GREY_EDGE, False),
    ]
    for column, x in ((left, lx), (right, rx)):
        for (title, lines, fill, edge, dash), y in zip(column, rows):
            svg.card(x, y, w, h, title, lines, fill, edge, dash=dash)

    cl, cr = lx + w / 2, rx + w / 2
    # workstation, from top to bottom
    svg.line(cl, 140, cl, 168)
    svg.badge(cl + 22, 154, 1)
    svg.line(cl, 246, cl, 274)
    svg.badge(cl + 22, 260, 4)
    svg.line(cl - 30, 352, cl - 30, 380)
    svg.badge(cl - 52, 366, 5)
    svg.line(cl + 30, 382, cl + 30, 355, key=True)
    svg.badge(cl + 54, 366, 6)
    svg.line(cl, 488, cl, 461, key=True)
    # network
    svg.text(500, 180, "connection", size=13)
    svg.line(lx + w, 196, rx - 2, 196)
    svg.badge(500, 196, 2)
    svg.line(rx, 226, lx + w + 2, 226, dash=True)
    svg.badge(500, 226, 3)
    svg.text(500, 252, "server asks for key", size=13)
    svg.text(500, 298, "encrypted key", size=13)
    svg.line(lx + w, 314, rx - 3, 314, key=True)
    svg.badge(500, 314, 7)
    # server, from top to bottom
    svg.line(cr, 246, cr, 274)
    svg.line(cr, 352, cr, 379, key=True)
    svg.badge(cr + 24, 366, 8)
    svg.line(cr - 20, 458, cr - 20, 486)
    svg.line(cr + 20, 488, cr + 20, 460)
    svg.badge(cr + 44, 472, 9)

    steps = [
        "The application calls a connection to the database.",
        "fbclient.dll sends the request to the server.",
        "The server sees that the database is encrypted and asks the client for the key.",
        "fbclient.dll loads the KeyHolder plugin from the plugins folder.",
        "The client KeyHolder calls the function MakeKeys of the KeySource.dll library.",
        "KeySource.dll gets the key from its source and returns it.",
        "The client KeyHolder sends the key to the server in encrypted form.",
        "The server KeyHolder gives the key to the DbCrypt plugin.",
        "DbCrypt decrypts pages when it reads them and encrypts pages when it writes them.",
    ]
    y = 616
    for i, text in enumerate(steps):
        svg.badge(40, y, i + 1)
        svg.text(60, y + 5, text, size=14, anchor="start")
        y += 24
    svg.line(30, y + 4, 96, y + 4, key=True)
    svg.text(108, y + 9, "thick line: the way of the key", size=14, anchor="start", italic=True)
    svg.save("components.svg")


# --------------------------------------------------------------------------- 2. network connection
def seq_remote() -> None:
    sequence("seq-remote.svg", [
        ("Application", "grey"), ("fbclient.dll", "blue"), ("Client\nKeyHolder", "blue"),
        ("KeySource.dll", "yellow"), ("Firebird\nserver", "green"), ("Server\nKeyHolder", "green"),
        ("DbCrypt", "green"),
    ], [
        ("note", 0, 3, "Workstation: one application process", "grey"),
        ("msg", 0, 1, "connection"),
        ("msg", 1, 4, "connection, user check"),
        ("msg", 4, 5, "encrypted database:\nneeds key Red"),
        ("ret", 4, 1, "key request to the client (op_crypt_key_callback)"),
        ("msg", 1, 2, "create plugin"),
        ("msg", 2, 3, "LoadLibrary,\nMakeKeys()"),
        ("ret", 3, 2, "Key=Red 0x..,"),
        ("self", 2, "FreeLibrary: KeySource.dll\nis unloaded from the process"),
        ("msg", 2, 5, "keys in encrypted form (through fbclient.dll and the server)"),
        ("msg", 5, 6, "key Red,\nprotected"),
        ("self", 6, "key check,\npage decryption"),
        ("ret", 4, 0, "connection is open"),
    ], width=1100)


# --------------------------------------------------------------------------- 3. embedded
def seq_embedded() -> None:
    sequence("seq-embedded.svg", [
        ("Application", "grey"), ("fbclient.dll", "blue"), ("Engine\nengine13.dll", "green"),
        ("KeyHolder", "green"), ("KeySource.dll", "yellow"), ("DbCrypt", "green"),
    ], [
        ("note", 0, 5, "One application process. No server and no network", "grey"),
        ("msg", 0, 1, "connection"),
        ("msg", 1, 2, "Providers = Engine13:\nload the engine"),
        ("self", 2, "open the database file:\ndatabase is encrypted, key Red"),
        ("msg", 2, 3, "create plugin"),
        ("msg", 3, 4, "LoadLibrary,\nMakeKeys()"),
        ("ret", 4, 3, "Key=Red 0x..,"),
        ("self", 3, "FreeLibrary: KeySource.dll\nis unloaded from the process"),
        ("msg", 3, 5, "key Red, protected exchange"),
        ("self", 5, "license and key check,\npage decryption"),
        ("ret", 2, 0, "connection is open"),
    ], width=1040)


# --------------------------------------------------------------------------- 4. life of the library
def dll_life() -> None:
    svg = Svg(960, 400)
    svg.text(20, 30, "Without pinning: the plugin loads and unloads the library for each connection",
             size=14, anchor="start", bold=True)
    x = 20
    for n in (1, 2, 3):
        svg.text(x + 150, 62, f"connection {n}", size=13, italic=True)
        svg.box(x, 72, 92, 44, "LoadLibrary", BLUE, BLUE_EDGE, size=12)
        svg.box(x + 98, 72, 108, 44, "MakeKeys()", YELLOW, YELLOW_EDGE, size=12)
        svg.box(x + 212, 72, 90, 44, "FreeLibrary", GREY, GREY_EDGE, size=12)
        x += 314
    svg.text(20, 142, "Library variables are not kept. A multithreaded application leaks memory.", size=13, anchor="start")

    svg.text(20, 196, "With pinning (all example libraries): PinLibrary at the start of MakeKeys",
             size=14, anchor="start", bold=True)
    svg.text(170, 228, "connection 1", size=13, italic=True)
    svg.box(20, 238, 92, 62, "LoadLibrary", BLUE, BLUE_EDGE, size=12)
    svg.box(118, 238, 190, 62, "MakeKeys():\nPinLibrary,\nget the key", YELLOW, YELLOW_EDGE, size=12)
    svg.box(314, 238, 112, 62, "FreeLibrary:\ndoes not unload", GREY, GREY_EDGE, size=12)
    svg.text(545, 228, "connection 2", size=13, italic=True)
    svg.box(465, 238, 160, 62, "MakeKeys()", YELLOW, YELLOW_EDGE, size=12)
    svg.text(765, 228, "connection 3", size=13, italic=True)
    svg.box(685, 238, 160, 62, "MakeKeys()", YELLOW, YELLOW_EDGE, size=12)
    svg.rect(118, 316, 822, 30, GREEN, GREEN_EDGE)
    svg.text(529, 336, "KeySource.dll stays in the process memory until the process ends; variables are kept",
             size=13)
    svg.text(20, 376, "Variant d keeps a key cache in this memory. A critical section protects the cache.", size=13, anchor="start")
    svg.save("dll-life.svg")


# --------------------------------------------------------------------------- 5. variants A and B
def variants_ab() -> None:
    svg = Svg(1000, 548)

    def steps(x, y, texts):
        for i, text in enumerate(texts):
            svg.badge(x, y + i * 26, i + 1)
            svg.text(x + 18, y + i * 26 + 5, text, size=13, anchor="start")

    def facts(x0, rows):
        for i, (label, text) in enumerate(rows):
            svg.text(x0 + 20, 462 + i * 24, label, size=13, anchor="start", bold=True)
            svg.text(x0 + 132, 462 + i * 24, text, size=13, anchor="start")

    # ---- a: the key is in the library
    svg.rect(20, 20, 470, 508, "#ffffff", GREY_EDGE, dash=True)
    svg.text(255, 48, "a) key in the library", size=16, bold=True)
    svg.box(40, 114, 170, 64, "Application,\nclient KeyHolder", GREY, GREY_EDGE, size=13)
    svg.rect(280, 76, 190, 262, YELLOW, YELLOW_EDGE)
    svg.text(375, 102, "KeySource.dll", size=14, bold=True)
    svg.box(294, 118, 162, 56, "function\nMakeKeys", "#ffffff", YELLOW_EDGE, size=13)
    svg.box(294, 206, 162, 76, "constant in code:\nKey=Red\n0xec,0xa1,…,0x75,", RED, RED_EDGE, size=13)
    svg.text(375, 308, "the key is written", size=13)
    svg.text(375, 326, "in the dll file", size=13)
    svg.line(210, 134, 292, 134)
    svg.badge(251, 134, 1)
    svg.line(294, 160, 213, 160, key=True)
    svg.badge(251, 160, 2)
    svg.line(375, 206, 375, 177, key=True)
    steps(50, 222, ["MakeKeys call", "key from library code"])
    svg.box(40, 362, 430, 62, "On the workstation disk: only KeySource.dll.\nNo settings file", GREY, GREY_EDGE,
            size=13, dash=True)
    facts(20, [("Key location", "in the KeySource.dll file"),
               ("Key change", "new dll on each workstation"),
               ("Risk", "the key can be extracted from the dll")])

    # ---- b: the key is in a file
    svg.rect(510, 20, 470, 508, "#ffffff", GREY_EDGE, dash=True)
    svg.text(745, 48, "b) key in a file", size=16, bold=True)
    svg.box(530, 114, 160, 64, "Application,\nclient KeyHolder", GREY, GREY_EDGE, size=13)
    svg.rect(750, 76, 210, 112, YELLOW, YELLOW_EDGE)
    svg.text(855, 102, "KeySource.dll", size=14, bold=True)
    svg.box(764, 118, 182, 56, "function MakeKeys;\nno key in the code", "#ffffff", YELLOW_EDGE, size=13)
    svg.line(690, 134, 762, 134)
    svg.badge(726, 134, 1)
    svg.line(764, 160, 693, 160, key=True)
    svg.badge(726, 160, 4)
    svg.box(750, 218, 210, 56, "KeySource.ini\nKeyFile=E:\\keys\\employee.key", GREY, GREY_EDGE, size=12)
    svg.line(855, 188, 855, 216)
    svg.badge(877, 202, 2)
    svg.rect(736, 304, 238, 122, "#ffffff", RED_EDGE, dash=True)
    svg.text(855, 322, "removable disk or folder", size=12)
    svg.box(750, 334, 210, 80, "E:\\keys\\employee.key\nKey=Red 0xec,…,0x75,\nor Password=Main phrase", RED, RED_EDGE, size=12)
    svg.line(855, 304, 855, 277, key=True)
    svg.badge(877, 290, 3)
    steps(540, 222, ["MakeKeys call", "path to the key file", "read the key file", "key from the file"])
    svg.box(530, 362, 186, 62, "No key on the\nworkstation disk", GREY, GREY_EDGE, size=13, dash=True)
    facts(510, [("Key location", "in a separate file; it can be taken away"),
                ("Key change", "replace the key file"),
                ("Risk", "the key file can be copied")])
    svg.save("variants-ab.svg")


# --------------------------------------------------------------------------- 6. key provider
def seq_provider() -> None:
    sequence("seq-provider.svg", [
        ("Application\nand KeyHolder", "grey"), ("KeySource.dll\nvariant c", "yellow"),
        ("KeyProvider.exe\nin the tray", "green"), ("User", "blue"),
    ], [
        ("gap", "first connection"),
        ("msg", 0, 1, "LoadLibrary, MakeKeys()"),
        ("self", 1, "pipe not found:\nstart KeyProvider.exe"),
        ("msg", 1, 2, "pipe:  GETKEYS 1 <pid> <program>"),
        ("msg", 2, 3, "no key in memory: input window"),
        ("ret", 3, 2, "pass phrase or key 0x..,"),
        ("self", 2, "check the input,\nkeep the key in memory"),
        ("ret", 2, 1, "OK  +  Key=Red 0x..,"),
        ("ret", 1, 0, "key text; FreeLibrary"),
        ("gap", "next connections"),
        ("msg", 0, 1, "LoadLibrary, MakeKeys()"),
        ("msg", 1, 2, "pipe:  GETKEYS 1 <pid> <program>"),
        ("ret", 2, 1, "OK  +  Key=Red 0x..,  (from memory)"),
        ("ret", 1, 0, "key text; FreeLibrary"),
    ], width=1000)


# --------------------------------------------------------------------------- 7. REST
def seq_rest() -> None:
    sequence("seq-rest.svg", [
        ("Application\nand KeyHolder", "grey"), ("KeySource.dll\nvariant d", "yellow"),
        ("Key server\nHTTPS", "green"),
    ], [
        ("gap", "first connection"),
        ("msg", 0, 1, "LoadLibrary, MakeKeys()"),
        ("msg", 1, 2, "GET /keys/Red\nAuthorization: Bearer <token>"),
        ("self", 2, "check the token,\nwrite the request to the log"),
        ("ret", 2, 1, "200  Key=Red 0x..,"),
        ("self", 1, "PinLibrary: dll stays in the process;\nkey is kept in memory"),
        ("ret", 1, 0, "key text"),
        ("gap", "next connections, until CacheSeconds expires"),
        ("msg", 0, 1, "MakeKeys()"),
        ("self", 1, "key from memory,\nno network"),
        ("ret", 1, 0, "key text"),
    ], width=900)


# --------------------------------------------------------------------------- 8. deployment
def deploy() -> None:
    columns = [
        ("Server", "work\\fb<N>\\server · scripts 10 and 20", [
            ("blue", "Full Firebird: firebird.exe,\nengine, tools, examples"),
            ("green", "Server\\*: fbclient.dll, fbcrypt.dll,\nOpenSSL"),
            ("green", "plugins\\dbcrypt.dll\nplugins\\keyholder.dll"),
            ("green", "plugins\\DbCrypt.conf: license"),
            ("grey", "firebird.conf:\nKeyHolderPlugin = KeyHolder"),
            ("grey", "db\\EMPLOYEE.FDB: encrypted\nby script 20"),
            ("none", "No keys: no KeyHolder.conf,\nno KeySource.dll"),
        ]),
        ("Workstation", "work\\fb<N>\\remote · script 40", [
            ("green", "Client\\64bit\\*: fbclient.dll, ICU,\nOpenSSL, isql, gbak"),
            ("green", "plugins\\keyholder.dll"),
            ("yellow", "KeySource.dll: variant a, b, c or d"),
            ("yellow", "EmployeeRemote.exe"),
            ("grey", "firebird.conf: Providers = Remote,\nKeyHolderPlugin = KeyHolder"),
            ("grey", "KeySource.ini, EmployeeApp.ini"),
            ("none", "DbCrypt and license are not necessary"),
        ]),
        ("Embedded folder", "work\\fb<N>\\embedded · script 41", [
            ("green", "Client\\64bit\\*: fbclient.dll, ICU,\nOpenSSL, isql, gbak"),
            ("green", "plugins\\keyholder.dll\nplugins\\dbcrypt.dll"),
            ("green", "plugins\\DbCrypt.conf: license"),
            ("blue", "plugins\\engine13.dll (3.0: engine12.dll),\nintl\\*"),
            ("yellow", "KeySource.dll, EmployeeEmbedded.exe"),
            ("grey", "firebird.conf: Providers = Engine13,\nKeyHolderPlugin = KeyHolder"),
            ("grey", "EMPLOYEE.FDB: its own encrypted\ncopy; KeySource.ini, EmployeeApp.ini"),
        ]),
    ]
    sources = [
        ("Official Firebird", ["github.com/FirebirdSQL/firebird", "script 01"], "blue"),
        ("Plugin archive", ["cc.ib-aid.com, with a trial license", "scripts 02 and 03"], "green"),
        ("Example programs", ["GitHub release or build", "in Lazarus; scripts 05 or 30"], "yellow"),
        ("Made by a script", ["settings files,", "encrypted database"], "grey"),
    ]
    heights = [sum(20 + (text.count("\n") + 1) * STEP for _, text in rows) for _, _, rows in columns]
    svg = Svg(1000, 262 + max(heights) + 14)

    svg.text(20, 34, "From where: four sources of files", size=16, bold=True, anchor="start")
    for i, (title, lines, colour) in enumerate(sources):
        fill, edge = FILLS[colour]
        svg.card(20 + i * 243.3, 48, 230, 76, title, lines, fill, edge, size=12)
    svg.text(20, 160, "To where: three folders. The row colour shows the source of the file", size=16, bold=True, anchor="start")
    for i, (title, path, rows) in enumerate(columns):
        x = 20 + i * 325
        svg.rect(x, 174, 310, 62, "#ffffff", INK, width=1.6)
        svg.text(x + 155, 198, title, size=15, bold=True)
        svg.text(x + 155, 220, path, size=12)
        y = 244
        for colour, text in rows:
            h = 14 + (text.count("\n") + 1) * STEP
            if colour == "none":
                svg.box(x, y, 310, h, text, "#ffffff", GREY_EDGE, size=12, dash=True)
            else:
                fill, edge = FILLS[colour]
                svg.box(x, y, 310, h, text, fill, edge, size=12)
            y += h + 6
    svg.save("deploy.svg")


# --------------------------------------------------------------------------- 9. where the key is
def key_location() -> None:
    columns = ["Workstation\ndisk", "Application\nmemory", "Other program\nor computer", "Network"]
    rows = [
        ("a) key in the library", [("yes: in the dll", RED), ("during the\nconnection", YELLOW), ("no", GREEN), ("no", GREEN)]),
        ("b) key in a file", [("yes: in the key file", RED), ("during the\nconnection", YELLOW), ("no", GREEN),
                              ("if the file is\nin a network folder", YELLOW)]),
        ("c) key provider", [("no", GREEN), ("during the\nconnection", YELLOW),
                             ("memory of\nKeyProvider.exe", YELLOW), ("no", GREEN)]),
        ("d) REST server", [("only the token", YELLOW), ("cache in dll:\nCacheSeconds", YELLOW),
                            ("key server", YELLOW), ("HTTPS to the\nkey server", YELLOW)]),
        ("Prompt (no dll)", [("no", GREEN), ("until the\napplication exits", YELLOW), ("no", GREEN), ("no", GREEN)]),
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
    svg.text(left, y, "In all variants the key goes to the database server in encrypted form", size=13, anchor="start")
    svg.text(left, y + STEP, "and stays in the server memory while the connection is open.", size=13, anchor="start")
    svg.save("key-location.svg")


# --------------------------------------------------------------------------- 10. backup
def backup() -> None:
    svg = Svg(1000, 432)
    svg.card(20, 96, 170, 76, "EMPLOYEE.FDB", ["pages are", "encrypted"], GREY, GREY_EDGE)
    svg.card(232, 96, 200, 76, "Firebird server", ["DbCrypt decrypts", "the pages"], GREEN, GREEN_EDGE)
    svg.card(474, 96, 200, 76, "gbak.exe -b", ["gets decrypted data", "from the server"], BLUE, BLUE_EDGE)
    svg.line(190, 134, 230, 134)
    svg.badge(210, 116, 2)
    svg.line(432, 134, 472, 134)
    svg.badge(452, 116, 3)

    svg.card(716, 20, 264, 94, "employee.fbk is encrypted", ["gbak encrypts the file with DbCrypt", "4.0, 5.0: -KEYHOLDER KeyHolder",
                                                             "3.0: KeyHolderPlugin in firebird.conf"], GREEN, GREEN_EDGE, size=12)
    svg.card(716, 150, 264, 76, "employee.fbk is NOT encrypted", ["Firebird 4.0 and 5.0", "without the -KEYHOLDER switch"],
             RED, RED_EDGE, size=12)
    svg.line(674, 120, 714, 80)
    svg.badge(684, 88, 4)
    svg.line(674, 150, 714, 182, dash=True)

    svg.card(474, 226, 200, 76, "KeySource.dll", ["and plugins\\keyholder.dll", "in the gbak folder"], YELLOW, YELLOW_EDGE)
    svg.line(574, 226, 574, 175, key=True)
    svg.badge(598, 200, 1)

    steps = [
        "gbak gets the key from KeySource.dll and sends it to the server.",
        "The server opens the database and decrypts the pages.",
        "gbak gets decrypted data from the server.",
        "gbak encrypts the backup file with the same key. For this, its folder must contain dbcrypt.dll and the license.",
    ]
    for i, text in enumerate(steps):
        svg.badge(40, 336 + i * 26, i + 1)
        svg.text(60, 341 + i * 26, text, size=14, anchor="start")
    svg.save("backup.svg")


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
    backup()
