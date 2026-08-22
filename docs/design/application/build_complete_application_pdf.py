"""Build the complete mCare application UI/UX approval blueprint.

Run from the repository root on the current workstation:
    py -3.11 docs/design/application/build_complete_application_pdf.py

The build is deterministic and local. Markdown is the authoritative written
source; the route atlas is generated from RouteNames so it cannot silently
omit an existing Flutter route.
"""

from __future__ import annotations

import html
import importlib.util
import re
from pathlib import Path

from reportlab.graphics.shapes import Drawing, Line, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    Image as PlatypusImage,
    KeepTogether,
    NextPageTemplate,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
ADMIN_BUILDER_PATH = REPO / "docs" / "design" / "admin" / "build_blueprint_pdf.py"
OUTPUT_DIR = REPO / "output" / "pdf"
OUTPUT_PDF = OUTPUT_DIR / "mcare-complete-application-design-blueprint.pdf"
ASSET_DIR = HERE / "assets" / "mockups"
ROUTE_FILE = REPO / "frontend" / "lib" / "shared" / "constants" / "route_names.dart"


def _load_admin_builder():
    spec = importlib.util.spec_from_file_location("mcare_admin_pdf_base", ADMIN_BUILDER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load PDF helpers from {ADMIN_BUILDER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = _load_admin_builder()

PAGE_W, PAGE_H = A4
LEFT, RIGHT, TOP, BOTTOM = base.LEFT, base.RIGHT, base.TOP, base.BOTTOM
CONTENT_W = base.CONTENT_W
FONT, FONT_BOLD, FONT_MONO = base.FONT, base.FONT_BOLD, base.FONT_MONO
INK, MUTED, BORDER, WHITE = base.INK, base.MUTED, base.BORDER, base.WHITE
VIOLET, VIOLET_SOFT, SURFACE_ALT = base.VIOLET, base.VIOLET_SOFT, base.SURFACE_ALT

ROLE_COLORS = {
    "Shared": colors.HexColor("#475569"),
    "Patient": colors.HexColor("#6366F1"),
    "Doctor": colors.HexColor("#057A55"),
    "Administrator": colors.HexColor("#7E3AF2"),
    "mCare Assistant": colors.HexColor("#C47F00"),
    "External": colors.HexColor("#3B82F6"),
}

ROLE_SOFT = {
    "Shared": colors.HexColor("#F1F5F9"),
    "Patient": colors.HexColor("#EEF2FF"),
    "Doctor": colors.HexColor("#ECFDF5"),
    "Administrator": colors.HexColor("#F5F3FF"),
    "mCare Assistant": colors.HexColor("#FFFBEB"),
    "External": colors.HexColor("#EFF6FF"),
}


class ApplicationDocTemplate(BaseDocTemplate):
    def __init__(self, filename: str):
        super().__init__(
            filename,
            pagesize=A4,
            leftMargin=LEFT,
            rightMargin=RIGHT,
            topMargin=TOP,
            bottomMargin=BOTTOM,
            title="mCare Complete Application UI/UX Design and Safe Implementation Blueprint",
            author="mCare Product, Design, Security and Engineering",
            subject="All-role design system, screen catalogue, backend traceability and implementation plan",
            creator="mCare complete blueprint documentation build",
        )
        body = Frame(LEFT, BOTTOM, CONTENT_W, PAGE_H - TOP - BOTTOM, id="body")
        cover = Frame(LEFT, BOTTOM, CONTENT_W, PAGE_H - TOP - BOTTOM, id="cover")
        self.addPageTemplates(
            [
                PageTemplate(id="Cover", frames=[cover], onPage=self._cover_page),
                PageTemplate(id="Body", frames=[body], onPage=self._body_page),
            ]
        )
        self._bookmark_counter = 0

    def beforeDocument(self):
        """Keep outline/TOC bookmark keys stable across multiBuild passes."""
        self._bookmark_counter = 0
        super().beforeDocument()

    def _cover_page(self, canvas, doc):
        canvas.saveState()
        band_w = PAGE_W / 5
        bands = [
            colors.HexColor("#7E3AF2"),
            colors.HexColor("#E3A008"),
            colors.HexColor("#6366F1"),
            colors.HexColor("#057A55"),
            colors.HexColor("#3B82F6"),
        ]
        for index, color in enumerate(bands):
            canvas.setFillColor(color)
            canvas.rect(index * band_w, PAGE_H - 9 * mm, band_w + 0.5, 9 * mm, stroke=0, fill=1)
        canvas.setFont(FONT, 7.3)
        canvas.setFillColor(MUTED)
        canvas.drawRightString(PAGE_W - RIGHT, 8 * mm, "Private - stakeholder approval blueprint")
        canvas.restoreState()

    def _body_page(self, canvas, doc):
        canvas.saveState()
        canvas.setStrokeColor(BORDER)
        canvas.setLineWidth(0.4)
        canvas.line(LEFT, PAGE_H - 12 * mm, PAGE_W - RIGHT, PAGE_H - 12 * mm)
        canvas.setFont(FONT_BOLD, 7.4)
        canvas.setFillColor(VIOLET)
        canvas.drawString(LEFT, PAGE_H - 9 * mm, "mCare Complete Application Design Blueprint")
        canvas.setFont(FONT, 7.2)
        canvas.setFillColor(MUTED)
        canvas.drawRightString(PAGE_W - RIGHT, PAGE_H - 9 * mm, "v3.0 - approval draft")
        canvas.line(LEFT, 11 * mm, PAGE_W - RIGHT, 11 * mm)
        canvas.drawString(LEFT, 7 * mm, "Private - 2026-08-07")
        canvas.drawRightString(PAGE_W - RIGHT, 7 * mm, f"Page {doc.page}")
        canvas.restoreState()

    def afterFlowable(self, flowable):
        if not isinstance(flowable, Paragraph):
            return
        name = flowable.style.name
        if name not in {"Heading1", "Heading2", "Heading3"}:
            return
        level = {"Heading1": 0, "Heading2": 1, "Heading3": 2}[name]
        text = flowable.getPlainText()
        self._bookmark_counter += 1
        key = f"section-{self._bookmark_counter}"
        self.canv.bookmarkPage(key)
        self.canv.addOutlineEntry(text, key, level=level, closed=level > 0)
        if level == 0:
            self.notify("TOCEntry", (level, text, self.page, key))


def _role_chip(label: str, color) -> Table:
    table = Table([[base.paragraph(label, "small")]], colWidths=[31 * mm])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), colors.white),
                ("BOX", (0, 0), (-1, -1), 0.8, color),
                ("TEXTCOLOR", (0, 0), (-1, -1), color),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    return table


def cover_story() -> list:
    chips = Table(
        [[
            _role_chip("Admin", ROLE_COLORS["Administrator"]),
            _role_chip("Assistant", ROLE_COLORS["mCare Assistant"]),
            _role_chip("Patient", ROLE_COLORS["Patient"]),
            _role_chip("Doctor", ROLE_COLORS["Doctor"]),
            _role_chip("External", ROLE_COLORS["External"]),
        ]],
        colWidths=[CONTENT_W / 5] * 5,
    )
    chips.setStyle(TableStyle([("ALIGN", (0, 0), (-1, -1), "CENTER"), ("VALIGN", (0, 0), (-1, -1), "MIDDLE")]))

    facts = base.markdown_table(
        [
            ["Verified scope", "Design commitment"],
            ["99 Flutter routes", "Every route appears in the generated screen atlas"],
            ["171 Laravel API routes", "Existing contracts remain canonical during migration"],
            ["One Flutter codebase", "Responsive composition changes; business logic does not"],
            ["Five experiences", "One design system with role-aware content and authority"],
            ["Administrator first", "Flagged pilot after baseline and P0 security gates"],
        ]
    )

    return [
        Spacer(1, 21 * mm),
        Paragraph("mCare", ParagraphStyle("CoverBrand", parent=base.styles["title"], fontSize=24, textColor=VIOLET)),
        Spacer(1, 6 * mm),
        Paragraph("Complete Application UI/UX Design Documentation", base.styles["title"]),
        Paragraph("Design system, all-role screen catalogue, responsive architecture, backend traceability, security and safe implementation blueprint", base.styles["subtitle"]),
        Spacer(1, 5 * mm),
        chips,
        Spacer(1, 9 * mm),
        facts,
        Spacer(1, 8 * mm),
        base.paragraph(
            "Approval baseline only. Existing UI remains authoritative until each role passes compatibility, security, accessibility and UAT release gates.",
            "callout",
        ),
        Spacer(1, 13 * mm),
        base.paragraph("Version: 3.0 - stakeholder approval draft"),
        base.paragraph("Audit date: 2026-08-07"),
        base.paragraph("First pilot: Administrator, disabled by default"),
        NextPageTemplate("Body"),
        PageBreak(),
    ]


def toc_story() -> list:
    toc = TableOfContents()
    toc.levelStyles = [
        ParagraphStyle(
            "TOCLevel1",
            fontName=FONT,
            fontSize=9.6,
            leading=14,
            leftIndent=0,
            firstLineIndent=0,
            textColor=INK,
            spaceBefore=2,
        )
    ]
    return [
        base.paragraph("Contents", "h1"),
        base.paragraph("Page numbers and PDF bookmarks are generated from the approved source chapters."),
        Spacer(1, 4 * mm),
        toc,
        PageBreak(),
    ]


def executive_story() -> list:
    return [
        base.paragraph("Executive design decision", "h1"),
        base.paragraph(
            "mCare will use one adaptive component language across Administrator, mCare Assistant, Patient, Doctor and External Clinical Access. Each authenticated role receives four task-based destinations; external access remains a contained one-patient session. Existing named routes and backend contracts stay intact throughout the migration."
        ),
        base.paragraph(
            "The current mCare Assistant is delegated human staff, not an AI assistant. The external clinician is a token guest, not a registered account. Laboratory, imaging, billing, payments, insurance, pharmacy inventory, referral, embedded video and AI remain future backend products.",
            "callout",
        ),
        base.markdown_table(
            [
                ["Experience", "Target navigation", "Primary safety boundary"],
                ["Administrator", "Home | Work | People | More", "Server authority, target hierarchy and typed commands"],
                ["mCare Assistant", "Home | Work | People | More", "Live capability filters plus server permission middleware"],
                ["Patient", "Home | Health | Care | More", "Own-record ownership and always-visible SOS"],
                ["Doctor", "Home | Work | Patients | More", "Active assigned caseload"],
                ["External", "Access -> Review -> Add finding -> End", "One patient, expiry, revoke and target scopes"],
            ]
        ),
        PageBreak(),
    ]


GALLERY = [
    ("Shared entry and patient onboarding - responsive", "shared-auth-responsive.png", "Existing - redesign", "One form language across phone, tablet and desktop; staff invitation remains separate from patient self-registration."),
    ("Shared Design System v2 specimen", "shared-design-system-board.png", "Target component system", "Written token values are authoritative; the board demonstrates density, state, navigation and dark-mode direction."),
    ("Administrator Home - compact", "admin-home-mobile-v2.png", "Existing - redesign", "Privacy-minimized next actions, truthful freshness and four stable destinations."),
    ("Administrator Home - expanded", "admin-home-desktop-v2.png", "Existing - redesign", "Same information architecture with useful max-width composition and operational context."),
    ("Administrator Work - compact", "admin-work-mobile.png", "Existing - redesign", "One ranked work queue; typed details retain canonical workflow actions."),
    ("Administrator Work - medium/master-detail", "admin-work-tablet.png", "Existing - redesign", "List-detail pattern appears only when local content width supports it."),
    ("Administrator People - compact", "admin-people-mobile.png", "Existing - redesign", "Patient and staff directories consolidate account and assignment context."),
    ("mCare Assistant Home - expanded", "assistant-home-desktop.png", "Existing - redesign", "Human delegated staff see only permitted work and a clear summary of their access."),
    ("mCare Assistant Work - compact", "assistant-work-mobile.png", "Existing - redesign", "Permission-filtered tasks use the same staff work components as Admin."),
    ("Patient Home - compact", "patient-home-mobile-v2.png", "Existing - redesign", "Daily care tasks, vital/dose/visit actions and always-visible SOS in plain language."),
    ("Patient Vitals - expanded", "patient-vitals-desktop.png", "Existing - redesign", "Accessible trend presentation, assigned measurements and direct recording actions."),
    ("Doctor Home - compact", "doctor-home-mobile-v2.png", "Existing - redesign", "Assigned caseload priorities and four clinician destinations."),
    ("Doctor patient workspace - expanded", "doctor-patient-workspace-desktop.png", "Existing - redesign", "A rich assigned-patient workspace grouped without inventing a formal EHR encounter."),
    ("External Clinical Access gate - compact", "external-access-mobile.png", "Target after security hardening", "Secure link/code entry for one record, not account login."),
    ("External one-patient workspace - expanded", "external-workspace-desktop.png", "Target after scope hardening", "No global dashboard; review and typed findings remain constrained to the shared patient."),
]


def visual_gallery_story() -> list:
    story = [
        base.paragraph("High-fidelity visual direction", "h1"),
        base.paragraph(
            "These images establish hierarchy, density, component language and responsive composition. The written route, backend, validation, accessibility and security specifications remain authoritative if illustrative copy differs."
        ),
        base.markdown_table(
            [
                ["Coverage", "Frames", "Approval focus"],
                ["Shared", "Auth/onboarding + Design System", "One component language, form behavior, states and dark mode"],
                ["Administrator", "Home mobile/desktop, Work mobile/tablet, People mobile", "Priority, progressive disclosure and responsive operations"],
                ["mCare Assistant", "Home desktop + Work mobile", "Same staff system with permission-filtered content"],
                ["Patient", "Home mobile + Vitals desktop", "Plain-language daily care and accessible monitoring"],
                ["Doctor", "Home mobile + patient workspace desktop", "Caseload priority and contextual clinical work"],
                ["External", "Access mobile + workspace desktop", "One-patient scope, expiry and typed findings"],
            ]
        ),
        base.paragraph(
            "The gallery is the single high-fidelity image location in this PDF. Role chapters cross-reference it instead of repeating the same mockups.",
            "callout",
        ),
        PageBreak(),
    ]
    for index, (title, filename, status, note) in enumerate(GALLERY):
        path = ASSET_DIR / filename
        if not path.exists():
            raise FileNotFoundError(path)
        story.extend(
            [
                base.paragraph(title, "h1"),
                base.markdown_table([["Status", "Design note"], [status, note]]),
                Spacer(1, 4 * mm),
                base.image_flow(path, max_h=205 * mm),
                base.paragraph(
                    "Illustrative approval mockup. Fictional sample data only. Written contracts and current repository truth take precedence.",
                    "caption",
                ),
            ]
        )
        if index < len(GALLERY) - 1:
            story.append(PageBreak())
    story.append(PageBreak())
    return story


def _split_camel(value: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z0-9])", " ", value).replace(" 7 Day", " 7-day").strip()


TITLE_OVERRIDES = {
    "home": "Public entry",
    "landing": "Landing",
    "verifyEmail": "Verify email",
    "forgotPassword": "Forgot password",
    "resetPassword": "Reset password",
    "pendingApproval": "Pending approval",
    "acceptInvite": "Accept staff invite",
    "externalDoctor": "External Clinical Access",
    "patientDashboard": "Patient Home",
    "patientVital7Day": "Seven-day vitals",
    "patientSos": "Patient SOS",
    "doctorDashboard": "Doctor Home",
    "doctorInbox": "Doctor action inbox",
    "doctorPatientChart": "Patient workspace",
    "doctorSos": "Doctor SOS",
    "adminDashboard": "Administrator Home",
    "adminSos": "Administrator SOS",
    "assistantDashboard": "Assistant Home",
    "assistantSos": "Assistant SOS",
}


def _role_for(name: str) -> str:
    if name == "externalDoctor":
        return "External"
    if name.startswith("patient"):
        return "Patient"
    if name.startswith("doctor"):
        return "Doctor"
    if name.startswith("admin"):
        return "Administrator"
    if name.startswith("assistant"):
        return "mCare Assistant"
    return "Shared"


def _title_for(name: str, role: str) -> str:
    if name in TITLE_OVERRIDES:
        return TITLE_OVERRIDES[name]
    prefix = {
        "Patient": "patient",
        "Doctor": "doctor",
        "Administrator": "admin",
        "mCare Assistant": "assistant",
    }.get(role, "")
    core = name[len(prefix):] if prefix and name.startswith(prefix) else name
    return _split_camel(core).capitalize()


def _parent_for(name: str, role: str, route: str) -> str:
    if role == "Shared":
        return "Public / auth"
    if role == "External":
        return "Scoped session"
    if any(token in name for token in ("CompleteProfile", "ForcePassword", "Onboarding")):
        return "Guard flow"
    if role in {"Administrator", "mCare Assistant"}:
        if name.endswith("Dashboard"):
            return "Home"
        if any(token in name for token in ("Sos", "Alert", "Approval", "CareRequest", "Assignment", "Support", "Message", "ChatThread")):
            return "Work"
        if any(token in name for token in ("Patient", "User", "Permission")):
            return "People"
        if "Notification" in name:
            return "Header bell"
        return "More"
    if role == "Patient":
        if name.endswith("Dashboard"):
            return "Home"
        if any(token in name for token in ("Vital", "Medication", "Document")):
            return "Health"
        if any(token in name for token in ("Appointment", "CareTeam", "Message", "ChatThread")):
            return "Care"
        if "Sos" in name:
            return "Global SOS"
        if "Notification" in name:
            return "Header bell"
        return "More"
    if role == "Doctor":
        if name.endswith("Dashboard"):
            return "Home"
        if any(token in name for token in ("Inbox", "Alert", "Visit", "Appointment", "Message", "ChatThread", "Sos")):
            return "Work"
        if "Patient" in name:
            return "Patients"
        if "Notification" in name:
            return "Header bell"
        return "More"
    return "Other"


def _layout_for(name: str, route: str) -> str:
    if any(token in name for token in ("Login", "Register", "Password", "Invite", "Onboarding", "CompleteProfile", "VerifyEmail")):
        return "Form / stepper"
    if "Dashboard" in name or name in {"home", "landing"}:
        return "Home / landing"
    if any(token in name for token in ("Detail", "Editor", "Thread", "Chart")):
        return "Context detail"
    if "Sos" in name:
        return "Emergency state"
    if any(token in name for token in ("Settings", "Profile", "System", "Permission")):
        return "Settings / form"
    if any(token in name for token in ("Message", "Notification", "Inbox", "Alert")):
        return "Queue / inbox"
    return "List / workspace"


def _access_for(name: str, role: str) -> str:
    if role == "Shared":
        if name in {"home", "landing", "login", "register", "verifyEmail", "forgotPassword", "resetPassword", "acceptInvite"}:
            return "Public flow"
        return "Account-state flow"
    if role == "External":
        return "Valid, unexpired patient token/code"
    if role == "Patient":
        return "Patient + own record"
    if role == "Doctor":
        return "Doctor; caseload for patient data"
    if role == "Administrator":
        if name == "adminSos":
            return "Admin only; fix current frontend guard"
        return "Administrator"

    grants = [
        (("Approvals",), "can_approve_healthworkers"),
        (("CareRequests",), "can_manage_care_requests"),
        (("Assignments",), "can_assign_patients"),
        (("Patients", "Users", "UserDetail"), "can_create_users (target split)"),
        (("Audit", "Analytics"), "can_view_activity_logs"),
        (("Sos",), "can_access_emergency_location"),
        (("VitalCatalog",), "can_manage_vital_catalog"),
        (("Announcements",), "can_manage_advertising"),
        (("Security",), "can_view_security_incidents"),
    ]
    for tokens, grant in grants:
        if any(token in name for token in tokens):
            return grant
    if any(token in name for token in ("Alert", "Support", "Message", "Notification")):
        return "Current baseline; target explicit capability"
    return "Assistant account / guard"


def _data_for(name: str, role: str, route: str) -> str:
    if role == "Shared":
        return "/auth/* or local landing"
    if role == "External":
        return "/external/*"
    pieces = [piece for piece in route.split("/") if piece]
    segment = pieces[1] if len(pieces) > 1 else "session"
    if role == "Patient":
        return f"/patient/session + /patient/{segment}*"
    if role == "Doctor":
        return f"/doctor/session + /doctor/{segment}*"
    return f"/admin/session + /admin/{segment}*"


def _purpose_for(title: str, layout: str, parent: str) -> str:
    if layout == "Home / landing":
        return "Orient the user and surface the next safe, authorized action."
    if layout == "Form / stepper":
        return f"Complete the {title.lower()} flow with explicit validation and recovery."
    if layout == "Context detail":
        return f"Review selected {title.lower()} context and use existing scoped actions."
    if layout == "Emergency state":
        return "Present emergency state and route only to the canonical SOS workflow."
    if layout == "Settings / form":
        return f"Review or update authorized {title.lower()} settings with confirmation."
    if layout == "Queue / inbox":
        return f"Browse and open {title.lower()} items; details own typed actions."
    return f"Browse and manage {title.lower()} within the {parent} section."


def route_manifest() -> list[dict[str, str]]:
    source = ROUTE_FILE.read_text(encoding="utf-8")
    matches = re.findall(r"^\s*static const\s+(\w+)\s*=\s*'([^']+)'\s*;", source, re.MULTILINE)
    if len(matches) != 99:
        raise RuntimeError(f"Expected 99 RouteNames entries; found {len(matches)}")
    entries = []
    for index, (name, route) in enumerate(matches, start=1):
        role = _role_for(name)
        title = _title_for(name, role)
        parent = _parent_for(name, role, route)
        layout = _layout_for(name, route)
        entries.append(
            {
                "number": f"{index:02d}",
                "name": name,
                "route": route,
                "role": role,
                "title": title,
                "parent": parent,
                "layout": layout,
                "access": _access_for(name, role),
                "data": _data_for(name, role, route),
                "purpose": _purpose_for(title, layout, parent),
            }
        )
    return entries


def _wireframe(layout: str, accent) -> Drawing:
    width, height = 29 * mm, 23 * mm
    d = Drawing(width, height)
    d.add(Rect(0, 0, width, height, rx=3, ry=3, fillColor=colors.white, strokeColor=BORDER, strokeWidth=0.6))
    if layout in {"Home / landing", "List / workspace", "Queue / inbox", "Settings / form", "Context detail"}:
        d.add(Rect(2, 2, 5, height - 4, fillColor=ROLE_SOFT.get("Shared"), strokeColor=None))
    d.add(Rect(9, height - 5, width - 11, 2.2, fillColor=accent, strokeColor=None))
    if layout == "Form / stepper":
        for y in (height - 10, height - 14, height - 18):
            d.add(Rect(9, y, width - 12, 2.3, fillColor=colors.HexColor("#F1F5F9"), strokeColor=BORDER, strokeWidth=0.3))
    elif layout == "Context detail":
        d.add(Rect(9, 3, 11, height - 11, fillColor=colors.HexColor("#F8FAFC"), strokeColor=BORDER, strokeWidth=0.3))
        d.add(Rect(21, 3, width - 23, height - 11, fillColor=ROLE_SOFT.get("Shared"), strokeColor=BORDER, strokeWidth=0.3))
    elif layout == "Emergency state":
        d.add(Rect(10, 5, width - 13, height - 13, rx=2, ry=2, fillColor=colors.HexColor("#FEE2E2"), strokeColor=colors.HexColor("#EF4444"), strokeWidth=0.6))
        d.add(String(12, 8, "SOS", fontName=FONT_BOLD, fontSize=6, fillColor=colors.HexColor("#B91C1C")))
    else:
        for y in (height - 10, height - 14, height - 18):
            d.add(Line(9, y, width - 3, y, strokeColor=BORDER, strokeWidth=1.2))
    return d


def _screen_card(entry: dict[str, str], width: float) -> Table:
    accent = ROLE_COLORS[entry["role"]]
    soft = ROLE_SOFT[entry["role"]]
    title_style = ParagraphStyle(
        f"CardTitle{entry['number']}",
        parent=base.styles["table"],
        fontName=FONT_BOLD,
        fontSize=8.4,
        leading=10.5,
        textColor=INK,
    )
    route_style = ParagraphStyle(
        f"CardRoute{entry['number']}",
        parent=base.styles["table"],
        fontName=FONT_MONO,
        fontSize=6.2,
        leading=7.5,
        textColor=MUTED,
    )
    detail_style = ParagraphStyle(
        f"CardDetail{entry['number']}",
        parent=base.styles["table"],
        fontName=FONT,
        fontSize=6.4,
        leading=8.1,
        textColor=INK,
    )
    header = Table(
        [[
            Paragraph(f"<font color='{accent.hexval()}'><b>{entry['number']}</b></font>&nbsp; {html.escape(entry['title'])}", title_style),
            Paragraph(f"<font color='{accent.hexval()}'><b>{html.escape(entry['role'])}</b></font>", detail_style),
        ]],
        colWidths=[width * 0.63, width * 0.29],
    )
    header.setStyle(TableStyle([("ALIGN", (1, 0), (1, 0), "RIGHT"), ("VALIGN", (0, 0), (-1, -1), "TOP")]))

    details = Paragraph(
        "<b>Parent:</b> {parent}<br/><b>Layout:</b> {layout}<br/><b>Access:</b> {access}<br/><b>Data:</b> {data}".format(
            **{key: html.escape(entry[key]) for key in ("parent", "layout", "access", "data")}
        ),
        detail_style,
    )
    body = Table(
        [[_wireframe(entry["layout"], accent), details]],
        colWidths=[31 * mm, width - 35 * mm],
    )
    body.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0)]))

    card = Table(
        [
            [header],
            [Paragraph(html.escape(entry["route"]), route_style)],
            [body],
            [Paragraph(html.escape(entry["purpose"]), detail_style)],
        ],
        colWidths=[width],
    )
    card.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), soft),
                ("BOX", (0, 0), (-1, -1), 0.65, accent),
                ("LINEBELOW", (0, 0), (-1, 0), 0.35, accent),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return card


def screen_atlas_story() -> list:
    entries = route_manifest()
    story = [
        base.paragraph("Complete Existing Screen Atlas - 99 of 99 Routes", "h1"),
        base.paragraph(
            "Each card is generated from `route_names.dart`. It identifies the target parent, layout family, authorization boundary and backend family. Detailed page-family behavior lives in the role chapters. Detail and gate variants intentionally reuse the same component language instead of creating 99 unrelated designs."
        ),
        base.paragraph(
            "All atlas routes are existing. New aggregation hubs are additive and remain behind role flags. Future-not-backed modules are excluded from the current route atlas and documented in the future backlog.",
            "callout",
        ),
        base.markdown_table(
            [
                ["Role group", "Routes", "Atlas accent", "Primary authority"],
                ["Shared", "9", "Slate", "Public/account-state flow"],
                ["External", "1", "Blue", "Valid patient token/code"],
                ["Patient", "21", "Indigo", "Patient + own record"],
                ["Doctor", "22", "Green", "Doctor + active caseload"],
                ["Administrator", "24", "Violet", "Administrator"],
                ["mCare Assistant", "22", "Amber", "Assistant + live grant/capability"],
            ]
        ),
        base.paragraph(
            "Card anatomy: exact route, target parent, responsive layout family, access boundary, backend family and one-sentence purpose. The miniature wireframe is a page-family signature, not a pixel specification.",
            "small",
        ),
        PageBreak(),
    ]

    order = ["Shared", "External", "Patient", "Doctor", "Administrator", "mCare Assistant"]
    card_gap = 4 * mm
    card_w = (CONTENT_W - card_gap) / 2
    for role_index, role in enumerate(order):
        group = [entry for entry in entries if entry["role"] == role]
        story.append(base.paragraph(f"Screen atlas - {role}", "h1"))
        story.append(base.paragraph(f"{len(group)} current route(s). Accent is contextual; semantic status colors remain universal."))
        story.append(Spacer(1, 3 * mm))
        rows = []
        for index in range(0, len(group), 2):
            left = _screen_card(group[index], card_w)
            right = _screen_card(group[index + 1], card_w) if index + 1 < len(group) else ""
            rows.append([left, right])
            if len(rows) == 3 or index + 2 >= len(group):
                table = Table(rows, colWidths=[card_w, card_w], rowHeights=[67 * mm] * len(rows), hAlign="LEFT")
                table.setStyle(
                    TableStyle(
                        [
                            ("VALIGN", (0, 0), (-1, -1), "TOP"),
                            ("LEFTPADDING", (0, 0), (-1, -1), 0),
                            ("RIGHTPADDING", (0, 0), (-1, -1), card_gap),
                            ("TOPPADDING", (0, 0), (-1, -1), 0),
                            ("BOTTOMPADDING", (0, 0), (-1, -1), 3 * mm),
                        ]
                    )
                )
                story.append(table)
                rows = []
                if index + 2 < len(group):
                    story.append(PageBreak())
                    story.append(base.paragraph(f"Screen atlas - {role} (continued)", "h1"))
        if role == "External":
            story.extend(
                [
                    Spacer(1, 3 * mm),
                    base.paragraph("External states represented inside the single route", "h2"),
                    base.markdown_table(
                        [
                            ["State", "Target presentation"],
                            ["Link present", "Exchange/confirm the supplied link without exposing another record"],
                            ["Code entry", "Eight-character entry with throttled error and retry guidance"],
                            ["Valid session", "One-patient review and only scoped Add finding actions"],
                            ["Invalid/expired/revoked", "Terminal explanation with no patient identity or record data"],
                            ["Submission receipt", "Durable result, correlation context and safe next action"],
                            ["End session", "Clear only guest state and return to a neutral access screen"],
                        ]
                    ),
                ]
            )
        if role_index < len(order) - 1:
            story.append(PageBreak())
    story.append(PageBreak())
    return story


CHAPTERS_BEFORE_ATLAS = [
    "00_EXECUTIVE_AND_PRODUCT_TRUTH.md",
    "01_UNIFIED_DESIGN_SYSTEM.md",
    "02_INFORMATION_ARCHITECTURE_AND_RESPONSIVE_SHELLS.md",
    "03_SHARED_AUTH_AND_ACCOUNT.md",
    "04_ADMINISTRATOR_PORTAL.md",
    "05_MCARE_ASSISTANT_PORTAL.md",
    "06_PATIENT_PORTAL.md",
    "07_DOCTOR_PORTAL.md",
    "08_EXTERNAL_CLINICAL_ACCESS.md",
    "09_CROSS_ROLE_WORKFLOWS_AND_STATES.md",
]

CHAPTERS_AFTER_ATLAS = [
    "10_ROUTE_API_PERMISSION_TRACEABILITY.md",
    "11_SECURITY_PRIVACY_CLINICAL_SAFETY.md",
    "12_SAFE_IMPLEMENTATION_ROADMAP.md",
    "13_TESTING_UAT_ROLLBACK.md",
    "14_APPROVAL_AND_FUTURE_BACKLOG.md",
]


def _chapter_story(filename: str) -> list:
    path = HERE / filename
    if not path.exists():
        raise FileNotFoundError(path)
    heading = path.read_text(encoding="utf-8").splitlines()[0].lstrip("# ")
    source = base.markdown_to_flowables(path, skip_first_h1=True)
    flowables = []
    skipped_image = False
    for flowable in source:
        if isinstance(flowable, PlatypusImage):
            if flowables and isinstance(flowables[-1], Spacer):
                flowables.pop()
            skipped_image = True
            continue
        if skipped_image and isinstance(flowable, Paragraph) and flowable.style.name == "Caption":
            label = flowable.getPlainText()
            flowables.append(base.paragraph(f"See high-fidelity gallery: {label}.", "small"))
            skipped_image = False
            continue
        skipped_image = False
        flowables.append(flowable)
    return [base.paragraph(heading, "h1"), *flowables]


def build() -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    story: list = []
    story.extend(cover_story())
    story.extend(toc_story())
    story.extend(executive_story())
    story.extend(visual_gallery_story())

    for filename in CHAPTERS_BEFORE_ATLAS:
        story.extend(_chapter_story(filename))
        story.append(PageBreak())

    story.extend(screen_atlas_story())

    for index, filename in enumerate(CHAPTERS_AFTER_ATLAS):
        story.extend(_chapter_story(filename))
        if index < len(CHAPTERS_AFTER_ATLAS) - 1:
            story.append(PageBreak())

    while story and isinstance(story[-1], Spacer):
        story.pop()

    doc = ApplicationDocTemplate(str(OUTPUT_PDF))
    doc.multiBuild(story)
    return OUTPUT_PDF


if __name__ == "__main__":
    print(build())
