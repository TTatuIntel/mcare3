"""Build the visually reviewed mCare Guided Operations design blueprint PDF.

Run from the repository root with Python 3.11:
    python docs/design/admin/build_blueprint_pdf.py

The script intentionally keeps PDF generation deterministic and local. It reads
the Markdown sources in this directory and writes the final artifact to
output/pdf/.
"""

from __future__ import annotations

import html
import re
from pathlib import Path
from typing import Iterable

from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase import pdfmetrics
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    Image,
    KeepTogether,
    ListFlowable,
    ListItem,
    LongTable,
    NextPageTemplate,
    PageBreak,
    PageTemplate,
    Paragraph,
    Preformatted,
    Spacer,
    Table,
    TableStyle,
)


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
OUTPUT_DIR = REPO / "output" / "pdf"
OUTPUT_PDF = OUTPUT_DIR / "mcare-guided-operations-design-blueprint.pdf"

PAGE_W, PAGE_H = A4
LEFT = 17 * mm
RIGHT = 17 * mm
TOP = 19 * mm
BOTTOM = 17 * mm
CONTENT_W = PAGE_W - LEFT - RIGHT

INK = colors.HexColor("#172033")
MUTED = colors.HexColor("#5B667A")
VIOLET = colors.HexColor("#6250E8")
VIOLET_SOFT = colors.HexColor("#EEECFF")
TEAL = colors.HexColor("#078A93")
GREEN = colors.HexColor("#137A4A")
AMBER = colors.HexColor("#B45309")
RED = colors.HexColor("#C62828")
BORDER = colors.HexColor("#DDE3EC")
SURFACE_ALT = colors.HexColor("#F7F9FC")
WHITE = colors.white


def register_fonts() -> tuple[str, str, str]:
    """Use stable local fonts when present, otherwise built-in Helvetica."""
    candidates = [
        (
            Path("C:/Windows/Fonts/arial.ttf"),
            Path("C:/Windows/Fonts/arialbd.ttf"),
            Path("C:/Windows/Fonts/consola.ttf"),
        ),
        (
            Path("C:/Windows/Fonts/segoeui.ttf"),
            Path("C:/Windows/Fonts/segoeuib.ttf"),
            Path("C:/Windows/Fonts/consola.ttf"),
        ),
    ]
    for regular, bold, mono in candidates:
        if regular.exists() and bold.exists() and mono.exists():
            pdfmetrics.registerFont(TTFont("McareSans", str(regular)))
            pdfmetrics.registerFont(TTFont("McareSansBold", str(bold)))
            pdfmetrics.registerFont(TTFont("McareMono", str(mono)))
            return "McareSans", "McareSansBold", "McareMono"
    return "Helvetica", "Helvetica-Bold", "Courier"


FONT, FONT_BOLD, FONT_MONO = register_fonts()


def ascii_safe(value: str) -> str:
    replacements = {
        "\u2010": "-",
        "\u2011": "-",
        "\u2012": "-",
        "\u2013": "-",
        "\u2014": "-",
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2026": "...",
        "\u2192": "->",
        "\u2190": "<-",
        "\u2194": "<->",
        "\u2265": ">=",
        "\u2264": "<=",
        "\u2248": "~",
        "\u00d7": "x",
        "\u00b7": "-",
        "\u251c": "|",
        "\u2514": "|",
        "\u2500": "-",
        "\u2502": "|",
        "\u2610": "[ ]",
        "\u2713": "yes",
        "\ufe0f": "",
    }
    for old, new in replacements.items():
        value = value.replace(old, new)
    return value


SAMPLE = getSampleStyleSheet()
styles = {
    "body": ParagraphStyle(
        "Body",
        parent=SAMPLE["BodyText"],
        fontName=FONT,
        fontSize=9.2,
        leading=13.2,
        textColor=INK,
        spaceAfter=5,
    ),
    "small": ParagraphStyle(
        "Small",
        parent=SAMPLE["BodyText"],
        fontName=FONT,
        fontSize=7.7,
        leading=10.5,
        textColor=MUTED,
    ),
    "bullet": ParagraphStyle(
        "BulletBody",
        parent=SAMPLE["BodyText"],
        fontName=FONT,
        fontSize=9.2,
        leading=13.2,
        textColor=INK,
        leftIndent=11,
        firstLineIndent=-8,
        spaceAfter=2,
    ),
    "title": ParagraphStyle(
        "Title",
        parent=SAMPLE["Title"],
        fontName=FONT_BOLD,
        fontSize=29,
        leading=33,
        textColor=INK,
        alignment=TA_LEFT,
        spaceAfter=9,
    ),
    "subtitle": ParagraphStyle(
        "Subtitle",
        parent=SAMPLE["BodyText"],
        fontName=FONT,
        fontSize=13,
        leading=18,
        textColor=MUTED,
        spaceAfter=12,
    ),
    "h1": ParagraphStyle(
        "Heading1",
        parent=SAMPLE["Heading1"],
        fontName=FONT_BOLD,
        fontSize=20,
        leading=25,
        textColor=INK,
        spaceBefore=2,
        spaceAfter=11,
        keepWithNext=True,
    ),
    "h2": ParagraphStyle(
        "Heading2",
        parent=SAMPLE["Heading2"],
        fontName=FONT_BOLD,
        fontSize=14,
        leading=18,
        textColor=VIOLET,
        spaceBefore=9,
        spaceAfter=6,
        keepWithNext=True,
    ),
    "h3": ParagraphStyle(
        "Heading3",
        parent=SAMPLE["Heading3"],
        fontName=FONT_BOLD,
        fontSize=11.3,
        leading=15,
        textColor=INK,
        spaceBefore=7,
        spaceAfter=4,
        keepWithNext=True,
    ),
    "h4": ParagraphStyle(
        "Heading4",
        parent=SAMPLE["Heading4"],
        fontName=FONT_BOLD,
        fontSize=9.8,
        leading=13,
        textColor=TEAL,
        spaceBefore=6,
        spaceAfter=3,
        keepWithNext=True,
    ),
    "caption": ParagraphStyle(
        "Caption",
        parent=SAMPLE["BodyText"],
        fontName=FONT,
        fontSize=8,
        leading=11,
        textColor=MUTED,
        alignment=TA_CENTER,
        spaceBefore=4,
        spaceAfter=7,
    ),
    "table": ParagraphStyle(
        "TableCell",
        parent=SAMPLE["BodyText"],
        fontName=FONT,
        fontSize=7.25,
        leading=9.4,
        textColor=INK,
    ),
    "table_header": ParagraphStyle(
        "TableHeader",
        parent=SAMPLE["BodyText"],
        fontName=FONT_BOLD,
        fontSize=7.5,
        leading=9.5,
        textColor=WHITE,
    ),
    "code": ParagraphStyle(
        "Code",
        parent=SAMPLE["Code"],
        fontName=FONT_MONO,
        fontSize=7.4,
        leading=9.6,
        textColor=INK,
        backColor=SURFACE_ALT,
        borderColor=BORDER,
        borderWidth=0.5,
        borderPadding=7,
        spaceBefore=4,
        spaceAfter=7,
    ),
    "callout": ParagraphStyle(
        "Callout",
        parent=SAMPLE["BodyText"],
        fontName=FONT,
        fontSize=9.2,
        leading=13.2,
        textColor=INK,
        backColor=VIOLET_SOFT,
        borderColor=VIOLET,
        borderWidth=0.7,
        borderPadding=8,
        spaceBefore=5,
        spaceAfter=8,
    ),
}


def inline_markup(text: str) -> str:
    text = ascii_safe(text.strip())
    text = html.escape(text, quote=False)
    text = re.sub(r"!\[([^]]*)\]\(([^)]+)\)", r"\1", text)
    text = re.sub(r"\[([^]]+)\]\(([^)]+)\)", r'<font color="#6250E8"><u>\1</u></font>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"`([^`]+)`", rf'<font name="{FONT_MONO}" size="8">\1</font>', text)
    return text


def paragraph(text: str, style: str = "body") -> Paragraph:
    return Paragraph(inline_markup(text), styles[style])


def image_flow(path: Path, max_w: float = CONTENT_W, max_h: float = 226 * mm) -> Image:
    with PILImage.open(path) as im:
        width, height = im.size
    scale = min(max_w / width, max_h / height)
    return Image(str(path), width=width * scale, height=height * scale)


def table_col_widths(rows: list[list[str]]) -> list[float]:
    cols = max(len(row) for row in rows)
    weights = []
    for index in range(cols):
        length = max(
            4,
            min(
                45,
                max((len(ascii_safe(row[index])) if index < len(row) else 0) for row in rows),
            ),
        )
        weights.append(float(length))
    total = sum(weights)
    min_width = 21 * mm if cols <= 4 else 15 * mm
    raw = [CONTENT_W * weight / total for weight in weights]
    raw = [max(min_width, width) for width in raw]
    scale = CONTENT_W / sum(raw)
    return [width * scale for width in raw]


def markdown_table(rows: list[list[str]]) -> LongTable:
    widths = table_col_widths(rows)
    formatted = []
    for row_index, row in enumerate(rows):
        style_name = "table_header" if row_index == 0 else "table"
        padded = row + [""] * (len(widths) - len(row))
        formatted.append([paragraph(cell, style_name) for cell in padded])
    table = LongTable(formatted, colWidths=widths, repeatRows=1, hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), VIOLET),
                ("TEXTCOLOR", (0, 0), (-1, 0), WHITE),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("GRID", (0, 0), (-1, -1), 0.4, BORDER),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [WHITE, SURFACE_ALT]),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    return table


def is_table_separator(line: str) -> bool:
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells)


def split_table_row(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def markdown_to_flowables(path: Path, skip_first_h1: bool = True) -> list:
    lines = path.read_text(encoding="utf-8").splitlines()
    flowables: list = []
    index = 0
    first_h1_skipped = False

    while index < len(lines):
        line = lines[index].rstrip()
        stripped = line.strip()
        if not stripped:
            index += 1
            continue

        if stripped.startswith("```"):
            code_lines = []
            index += 1
            while index < len(lines) and not lines[index].strip().startswith("```"):
                code_lines.append(ascii_safe(lines[index]))
                index += 1
            index += 1
            flowables.append(Preformatted("\n".join(code_lines), styles["code"]))
            continue

        image_match = re.fullmatch(r"!\[([^]]*)\]\(([^)]+)\)", stripped)
        if image_match:
            image_path = (path.parent / image_match.group(2)).resolve()
            if image_path.exists():
                flowables.extend(
                    [
                        Spacer(1, 3 * mm),
                        image_flow(image_path),
                        paragraph(image_match.group(1), "caption"),
                    ]
                )
            index += 1
            continue

        heading_match = re.match(r"^(#{1,4})\s+(.+)$", stripped)
        if heading_match:
            level = len(heading_match.group(1))
            title = heading_match.group(2)
            if level == 1 and skip_first_h1 and not first_h1_skipped:
                first_h1_skipped = True
                index += 1
                continue
            flowables.append(paragraph(title, f"h{level}"))
            index += 1
            continue

        if stripped.startswith("> "):
            flowables.append(paragraph(stripped[2:], "callout"))
            index += 1
            continue

        if stripped.startswith("|") and index + 1 < len(lines) and is_table_separator(lines[index + 1]):
            table_rows = [split_table_row(stripped)]
            index += 2
            while index < len(lines) and lines[index].strip().startswith("|"):
                table_rows.append(split_table_row(lines[index]))
                index += 1
            flowables.append(markdown_table(table_rows))
            flowables.append(Spacer(1, 3 * mm))
            continue

        if re.match(r"^[-*]\s+", stripped) or re.match(r"^\d+\.\s+", stripped):
            ordered = bool(re.match(r"^\d+\.\s+", stripped))
            pattern = r"^\d+\.\s+" if ordered else r"^[-*]\s+"
            item_texts = []
            while index < len(lines) and re.match(pattern, lines[index].strip()):
                item_text = re.sub(pattern, "", lines[index].strip())
                if item_text.startswith("[ ] "):
                    item_text = "[ ] " + item_text[4:]
                item_texts.append(item_text)
                index += 1
            if ordered:
                items = [
                    ListItem(paragraph(item_text), leftIndent=9, bulletColor=VIOLET)
                    for item_text in item_texts
                ]
                flowables.append(
                    ListFlowable(
                        items,
                        bulletType="1",
                        start="1",
                        leftIndent=17,
                        bulletFontName=FONT_BOLD,
                        bulletFontSize=8,
                        bulletColor=VIOLET,
                        spaceAfter=5,
                    )
                )
            else:
                flowables.extend(paragraph(f"- {item_text}", "bullet") for item_text in item_texts)
                flowables.append(Spacer(1, 2 * mm))
            continue

        paragraph_lines = [stripped]
        index += 1
        while index < len(lines):
            candidate = lines[index].strip()
            if not candidate:
                break
            if (
                candidate.startswith("#")
                or candidate.startswith("```")
                or candidate.startswith("|")
                or candidate.startswith("> ")
                or re.match(r"^[-*]\s+", candidate)
                or re.match(r"^\d+\.\s+", candidate)
                or re.fullmatch(r"!\[([^]]*)\]\(([^)]+)\)", candidate)
            ):
                break
            paragraph_lines.append(candidate)
            index += 1
        flowables.append(paragraph(" ".join(paragraph_lines)))

    return flowables


class BlueprintDocTemplate(BaseDocTemplate):
    def __init__(self, filename: str):
        super().__init__(
            filename,
            pagesize=A4,
            leftMargin=LEFT,
            rightMargin=RIGHT,
            topMargin=TOP,
            bottomMargin=BOTTOM,
            title="mCare Guided Operations Hub - Design Blueprint",
            author="mCare Product and Engineering",
            subject="Admin and mCare Assistant design, security and implementation blueprint",
            creator="mCare documentation build",
        )
        content_frame = Frame(LEFT, BOTTOM, CONTENT_W, PAGE_H - TOP - BOTTOM, id="content")
        cover_frame = Frame(LEFT, BOTTOM, CONTENT_W, PAGE_H - TOP - BOTTOM, id="cover")
        self.addPageTemplates(
            [
                PageTemplate(id="Cover", frames=[cover_frame], onPage=self._cover_page),
                PageTemplate(id="Body", frames=[content_frame], onPage=self._body_page),
            ]
        )
        self._bookmark_counter = 0

    def _cover_page(self, canvas, doc):
        canvas.saveState()
        canvas.setFillColor(VIOLET)
        canvas.rect(0, PAGE_H - 9 * mm, PAGE_W, 9 * mm, stroke=0, fill=1)
        canvas.setFillColor(MUTED)
        canvas.setFont(FONT, 7.5)
        canvas.drawRightString(PAGE_W - RIGHT, 9 * mm, "Private - design and implementation blueprint")
        canvas.restoreState()

    def _body_page(self, canvas, doc):
        canvas.saveState()
        canvas.setStrokeColor(BORDER)
        canvas.setLineWidth(0.4)
        canvas.line(LEFT, PAGE_H - 12 * mm, PAGE_W - RIGHT, PAGE_H - 12 * mm)
        canvas.setFont(FONT_BOLD, 7.5)
        canvas.setFillColor(VIOLET)
        canvas.drawString(LEFT, PAGE_H - 9 * mm, "mCare Guided Operations Hub")
        canvas.setFont(FONT, 7.3)
        canvas.setFillColor(MUTED)
        canvas.drawRightString(PAGE_W - RIGHT, PAGE_H - 9 * mm, "Design Blueprint v2.0-draft")
        canvas.line(LEFT, 11 * mm, PAGE_W - RIGHT, 11 * mm)
        canvas.drawString(LEFT, 7 * mm, "Private - 2026-08-07")
        canvas.drawRightString(PAGE_W - RIGHT, 7 * mm, f"Page {doc.page}")
        canvas.restoreState()

    def afterFlowable(self, flowable):
        if isinstance(flowable, Paragraph):
            name = flowable.style.name
            if name in {"Heading1", "Heading2", "Heading3"}:
                level = {"Heading1": 0, "Heading2": 1, "Heading3": 2}[name]
                text = flowable.getPlainText()
                self._bookmark_counter += 1
                key = f"heading-{self._bookmark_counter}"
                self.canv.bookmarkPage(key)
                self.canv.addOutlineEntry(text, key, level=level, closed=False)
                self.notify("TOCEntry", (level, text, self.page, key))


def cover_story() -> list:
    key_points = Table(
        [
            [paragraph("4", "h2"), paragraph("stable destinations: Home, Work, People, More")],
            [paragraph("1", "h2"), paragraph("shared Flutter codebase across mobile, tablet, web and desktop")],
            [paragraph("0", "h2"), paragraph("legacy routes removed during the safe rollout")],
        ],
        colWidths=[18 * mm, CONTENT_W - 18 * mm],
    )
    key_points.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), SURFACE_ALT),
                ("BOX", (0, 0), (-1, -1), 0.6, BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.4, BORDER),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    return [
        Spacer(1, 28 * mm),
        Paragraph("mCare", ParagraphStyle("Brand", parent=styles["title"], textColor=VIOLET, fontSize=24)),
        Spacer(1, 8 * mm),
        Paragraph("Guided Operations Hub", styles["title"]),
        Paragraph("Complete design, responsive architecture, backend traceability, security and implementation blueprint", styles["subtitle"]),
        Spacer(1, 8 * mm),
        key_points,
        Spacer(1, 12 * mm),
        paragraph("Status: selected design direction; implementation is gated by security, compatibility and regression requirements.", "callout"),
        Spacer(1, 22 * mm),
        paragraph("Document version: 2.0-draft"),
        paragraph("Date: 2026-08-07"),
        paragraph("Scope: Administrator and permission-filtered mCare Assistant"),
        paragraph("Source: verified against the current Flutter and Laravel repository"),
        NextPageTemplate("Body"),
        PageBreak(),
    ]


def toc_story() -> list:
    entries = [
        "Executive summary and responsive mockups",
        "01 - Product and UX Blueprint",
        "02 - Screen and State Specifications",
        "03 - Responsive Flutter Architecture",
        "04 - Route, API and Permission Traceability",
        "05 - Security, Privacy and Clinical Safety Blueprint",
        "06 - Implementation, Migration and Test Plan",
        "07 - Approval and Release Checklist",
    ]
    flowables = [paragraph("Contents", "h1")]
    for number, entry in enumerate(entries, start=1):
        flowables.append(
            Paragraph(
                f'<font color="#6250E8"><b>{number:02d}</b></font>&nbsp;&nbsp;{html.escape(entry)}',
                ParagraphStyle(
                    name=f"StaticTOC{number}",
                    parent=styles["body"],
                    fontSize=10.5,
                    leading=16,
                    borderColor=BORDER,
                    borderWidth=0,
                    borderPadding=4,
                    spaceAfter=3,
                ),
            )
        )
    flowables.append(PageBreak())
    return flowables


def executive_story() -> list:
    summary = [
        paragraph("Executive summary", "h1"),
        paragraph(
            "The selected Guided Operations design reduces the staff experience to Home, Work, People and More. It preserves every existing route and canonical backend action while consolidating presentation, ranking and responsive layout into shared code."
        ),
        paragraph(
            "Production enablement is feature-flagged independently for Admin and Assistant. Laravel remains authoritative, legacy screens remain available for rollback, and P0 session/privacy/authorization risks must be closed before cutover.",
            "callout",
        ),
        paragraph("Design decisions", "h2"),
        markdown_table(
            [
                ["Decision", "Approved direction"],
                ["Navigation", "Home, Work, People, More"],
                ["Responsive", "Bottom bar <600; compact rail 600-1023; extended rail >=1024"],
                ["Implementation", "One shared Admin/Assistant Flutter implementation"],
                ["Backend", "Existing canonical endpoints plus additive capability/work-summary fields"],
                ["Migration", "Feature flags off by default; no route deletion; role-specific rollback"],
                ["Security", "Server default-deny, typed commands, minimum necessary PHI, immediate revocation"],
            ]
        ),
        PageBreak(),
        paragraph("Approved responsive mockups", "h1"),
    ]
    gallery = [
        ("Guided Home v2 - mobile", "guided-home-v2-mobile.png", 190 * mm),
        ("Unified Work - mobile", "guided-work-mobile.png", 215 * mm),
        ("People directory - mobile", "guided-people-mobile.png", 215 * mm),
        ("Work master/detail - tablet", "guided-work-tablet.png", 155 * mm),
        ("Guided Home - desktop/web", "guided-home-desktop.png", 150 * mm),
    ]
    for index, (caption, filename, max_height) in enumerate(gallery):
        summary.extend(
            [
                paragraph(caption, "h2"),
                image_flow(HERE / filename, max_h=max_height),
                paragraph(
                    "Visual direction only. The written screen, backend, security and accessibility specifications are authoritative.",
                    "caption",
                ),
            ]
        )
        if index < len(gallery) - 1:
            summary.append(PageBreak())
    summary.append(PageBreak())
    return summary


def build() -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    chapters = [
        "01_PRODUCT_UX_BLUEPRINT.md",
        "02_SCREEN_AND_STATE_SPECIFICATIONS.md",
        "03_RESPONSIVE_FLUTTER_ARCHITECTURE.md",
        "04_ROUTE_API_PERMISSION_TRACEABILITY.md",
        "05_SECURITY_PRIVACY_SAFETY.md",
        "06_IMPLEMENTATION_MIGRATION_TEST_PLAN.md",
        "07_APPROVAL_CHECKLIST.md",
    ]

    story = []
    story.extend(cover_story())
    story.extend(toc_story())
    story.extend(executive_story())

    for chapter_index, filename in enumerate(chapters):
        chapter_path = HERE / filename
        chapter_title = chapter_path.read_text(encoding="utf-8").splitlines()[0].lstrip("# ")
        story.append(paragraph(chapter_title, "h1"))
        story.extend(markdown_to_flowables(chapter_path, skip_first_h1=True))
        if chapter_index < len(chapters) - 1:
            story.append(PageBreak())

    while story and isinstance(story[-1], Spacer):
        story.pop()

    doc = BlueprintDocTemplate(str(OUTPUT_PDF))
    doc.build(story)
    return OUTPUT_PDF


if __name__ == "__main__":
    print(build())
