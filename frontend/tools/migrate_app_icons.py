#!/usr/bin/env python3
"""Replace raw Icons.* with AppIcons.* in frontend/lib (excluding app_icons.dart)."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"
SKIP = {"app_icons.dart"}
IMPORT = "import '../../shared/widgets/app_icons.dart';"
IMPORT_DEPTH = {
    0: "import 'shared/widgets/app_icons.dart';",
}

REPLACEMENTS = [
    ("Icons.arrow_back_ios_new_rounded", "AppIcons.backIos"),
    ("Icons.arrow_back_rounded", "AppIcons.back"),
    ("Icons.settings_rounded", "AppIcons.settings"),
    ("Icons.notifications_rounded", "AppIcons.bell"),
    ("Icons.notifications_active_rounded", "AppIcons.notificationsActive"),
    ("Icons.person_rounded", "AppIcons.profile"),
    ("Icons.person_outline_rounded", "AppIcons.user"),
    ("Icons.add_rounded", "AppIcons.add"),
    ("Icons.edit_rounded", "AppIcons.edit"),
    ("Icons.delete_outline_rounded", "AppIcons.delete"),
    ("Icons.close_rounded", "AppIcons.close"),
    ("Icons.check_circle_rounded", "AppIcons.check"),
    ("Icons.warning_amber_rounded", "AppIcons.alert"),
    ("Icons.info_outline_rounded", "AppIcons.info"),
    ("Icons.search_rounded", "AppIcons.search"),
    ("Icons.chevron_right_rounded", "AppIcons.chevronRight"),
    ("Icons.chevron_left_rounded", "AppIcons.chevronLeft"),
    ("Icons.expand_more_rounded", "AppIcons.expandMore"),
    ("Icons.expand_less_rounded", "AppIcons.expandLess"),
    ("Icons.refresh_rounded", "AppIcons.refresh"),
    ("Icons.more_horiz_rounded", "AppIcons.more"),
    ("Icons.lock_outline_rounded", "AppIcons.lock"),
    ("Icons.mail_outline_rounded", "AppIcons.email"),
    ("Icons.phone_rounded", "AppIcons.phone"),
    ("Icons.logout_rounded", "AppIcons.logout"),
    ("Icons.visibility_rounded", "AppIcons.visibility"),
    ("Icons.visibility_off_rounded", "AppIcons.visibilityOff"),
    ("Icons.upload_rounded", "AppIcons.upload"),
    ("Icons.download_rounded", "AppIcons.download"),
    ("Icons.send_rounded", "AppIcons.send"),
    ("Icons.link_rounded", "AppIcons.link"),
    ("Icons.calendar_today_rounded", "AppIcons.calendar"),
    ("Icons.schedule_rounded", "AppIcons.time"),
    ("Icons.location_on_rounded", "AppIcons.location"),
    ("Icons.chat_bubble_rounded", "AppIcons.chat"),
    ("Icons.description_rounded", "AppIcons.document"),
    ("Icons.assignment_rounded", "AppIcons.report"),
    ("Icons.event_available_rounded", "AppIcons.appointment"),
    ("Icons.medication_rounded", "AppIcons.medication"),
    ("Icons.emergency_rounded", "AppIcons.sos"),
    ("Icons.monitor_heart_rounded", "AppIcons.vitals"),
    ("Icons.favorite_rounded", "AppIcons.heartRate"),
    ("Icons.dashboard_rounded", "AppIcons.home"),
    ("Icons.groups_2_rounded", "AppIcons.patients"),
    ("Icons.people_alt_rounded", "AppIcons.users"),
    ("Icons.insights_rounded", "AppIcons.analytics"),
    ("Icons.history_rounded", "AppIcons.audit"),
    ("Icons.security_rounded", "AppIcons.security"),
    ("Icons.campaign_rounded", "AppIcons.announcements"),
    ("Icons.support_agent_rounded", "AppIcons.support"),
    ("Icons.error_outline_rounded", "AppIcons.error"),
    ("Icons.error_outline", "AppIcons.error"),
    ("Icons.apple_rounded", "AppIcons.apple"),
    ("Icons.tune_rounded", "AppIcons.filter"),
    ("Icons.shield_rounded", "AppIcons.permissions"),
    ("Icons.storage_rounded", "AppIcons.storage"),
    ("Icons.science_rounded", "AppIcons.lab"),
    ("Icons.image_rounded", "AppIcons.image"),
    ("Icons.picture_as_pdf_rounded", "AppIcons.pdf"),
    ("Icons.insert_drive_file_rounded", "AppIcons.file"),
    ("Icons.local_hospital_rounded", "AppIcons.nurse"),
    ("Icons.map_rounded", "AppIcons.map"),
    ("Icons.home_rounded", "AppIcons.homeAddress"),
    ("Icons.folder_open_rounded", "AppIcons.folder"),
    ("Icons.content_copy_rounded", "AppIcons.copy"),
    ("Icons.share_rounded", "AppIcons.share"),
    ("Icons.star_rounded", "AppIcons.star"),
    ("Icons.videocam_rounded", "AppIcons.videocam"),
    ("Icons.photo_camera_rounded", "AppIcons.photo"),
    ("Icons.mic_rounded", "AppIcons.mic"),
    ("Icons.attach_file_rounded", "AppIcons.attach"),
    ("Icons.show_chart_rounded", "AppIcons.trend"),
    ("Icons.restaurant_rounded", "AppIcons.meals"),
    ("Icons.water_drop_rounded", "AppIcons.bloodPressure"),
    ("Icons.bubble_chart_rounded", "AppIcons.spo2"),
    ("Icons.thermostat_rounded", "AppIcons.temperature"),
    ("Icons.bloodtype_rounded", "AppIcons.glucose"),
    ("Icons.air_rounded", "AppIcons.respiratory"),
    ("Icons.monitor_weight_rounded", "AppIcons.weight"),
    ("Icons.receipt_long_rounded", "AppIcons.prescription"),
    ("Icons.assignment_ind_rounded", "AppIcons.chart"),
    ("Icons.assignment_turned_in_rounded", "AppIcons.assignments"),
    ("Icons.verified_user_rounded", "AppIcons.approval"),
    ("Icons.handshake_rounded", "AppIcons.careRequest"),
    ("Icons.checklist_rounded", "AppIcons.catalog"),
    ("Icons.local_pharmacy_rounded", "AppIcons.pharmacy"),
    ("Icons.medical_services_rounded", "AppIcons.careTeam"),
    ("Icons.translate_rounded", "AppIcons.language"),
]

def import_line_for(path: Path) -> str:
    rel = path.relative_to(ROOT)
    depth = len(rel.parts) - 1
    prefix = "/".join([".."] * depth)
    return f"import '{prefix}/shared/widgets/app_icons.dart';"

def ensure_import(text: str, path: Path) -> str:
    if "app_icons.dart" in text or "AppIcons." not in text:
        return text
    line = import_line_for(path)
    if line in text:
        return text
    m = re.search(r"^(import .+;\n)+", text)
    if m:
        return text[: m.end()] + line + "\n" + text[m.end() :]
    return line + "\n" + text

def migrate_file(path: Path) -> bool:
    if path.name in SKIP:
        return False
    original = path.read_text(encoding="utf-8")
    text = original
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    if text == original:
        return False
    text = ensure_import(text, path)
    path.write_text(text, encoding="utf-8")
    return True

def main() -> None:
    changed = 0
    for path in ROOT.rglob("*.dart"):
        if migrate_file(path):
            changed += 1
            print(f"updated {path.relative_to(ROOT)}")
    print(f"Done — {changed} files updated.")

if __name__ == "__main__":
    main()
