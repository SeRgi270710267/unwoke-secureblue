#!/usr/bin/env python3
"""Graphical Unwoke setup. Same stamps as setup.sh. Does not auto-unlock."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

try:
    import gi

    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk, GLib
except (ImportError, ValueError):
    sys.exit(2)

TOGGLES = "/usr/libexec/unwoke/toggles.sh"
ADMIN = "/usr/libexec/unwoke/admin-split.sh"
STAGED = Path("/etc/unwoke/signed-staged")
FLAVOR_FILE = Path("/usr/share/unwoke/flavor")
OFF = Path("/etc/unwoke/admin-split.off")
DONE = Path("/etc/unwoke/admin-split.done")


def flavor() -> str:
    try:
        return FLAVOR_FILE.read_text(encoding="utf-8").strip() or "unknown"
    except OSError:
        return "unknown"


def seen_path() -> Path:
    cfg = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
    return Path(cfg) / "unwoke" / "setup-seen"


def mark_seen() -> None:
    p = seen_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(GLib.DateTime.new_now_utc().format("%Y-%m-%dT%H:%M:%SZ") + "\n", encoding="utf-8")


def run_toggle(*args: str) -> str:
    r = subprocess.run([TOGGLES, *args], capture_output=True, text=True)
    out = (r.stdout or "") + (r.stderr or "")
    return out.strip() or ("ok" if r.returncode == 0 else "that toggle did not finish")


def open_tutorial(slug: str) -> None:
    subprocess.Popen(
        ["/usr/libexec/unwoke/open-tutorial.sh", slug or ""],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _exists(path: str) -> bool:
    return Path(path).exists()


def _flathub_on() -> bool:
    p = Path("/etc/unwoke/flathub")
    if not p.exists():
        return False
    return p.read_text(encoding="utf-8").strip() not in ("", "off")


# Default is locked. These stamps mean the user loosened something.
LOOSENED = (
    ("Bluetooth", lambda: _exists("/etc/unwoke/allow-bluetooth"), ("bluetooth", "off"), "bluetooth"),
    ("Flathub", _flathub_on, ("flathub", "off"), "install-apps"),
    ("Homebrew", lambda: _exists("/etc/unwoke/allow-brew"), ("brew", "off"), "install-apps"),
    ("Toolbox / distrobox", lambda: _exists("/etc/unwoke/allow-toolbox"), ("toolbox", "off"), "toolbox"),
    ("Camera / microphone", lambda: _exists("/etc/unwoke/allow-camera-mic"), ("camera-mic", "off"), "camera-mic"),
    ("Avahi / ModemManager", lambda: _exists("/etc/unwoke/allow-extra-daemons"), ("extra-daemons", "off"), "first-hour"),
    ("Flatpak lockdown off", lambda: _exists("/etc/unwoke/flatpak-lockdown.off"), ("lockdown", "on"), "install-apps"),
    ("Flatpak record allowed", lambda: _exists("/etc/unwoke/flatpak-record.off"), ("flatpak-record", "on"), "camera-mic"),
    ("NFS/CIFS clients allowed", lambda: _exists("/etc/unwoke/allow-network-fs"), ("network-fs", "off"), "network-fs"),
    ("JavaScript JIT allowed", lambda: _exists("/etc/unwoke/brave-jitless.off"), ("jitless", "on"), "sites-broken"),
    ("Browser devices allowed", lambda: _exists("/etc/unwoke/brave-devices.off"), ("devices", "on"), "camera-mic"),
    ("Password / autofill pack off", lambda: _exists("/etc/unwoke/brave-hardening.off"), ("hardening", "on"), "sites-broken"),
    ("Extensions allowed", lambda: _exists("/etc/unwoke/brave-extensions.off"), ("extensions", "block"), "sites-broken"),
    ("WebGL / WebGPU allowed", lambda: _exists("/etc/unwoke/brave-isolation.off"), ("isolation", "on"), "sites-broken"),
    ("Screen capture pack off", lambda: _exists("/etc/unwoke/brave-sandbox.off"), ("sandbox", "on"), "screen-share"),
    ("Origin Bubblejail off", lambda: _exists("/etc/unwoke/brave-bubblejail.off"), ("bubblejail", "on"), "sites-broken"),
    ("Trivalent network sandbox off", lambda: _exists("/etc/unwoke/trivalent-network-sandbox.off"), ("network-sandbox", "on"), "sites-broken"),
    ("Admin split off (wheel on greeter)", lambda: _exists("/etc/unwoke/admin-split.off"), ("admin-split", "on"), "daily-user"),
    ("Host browsers allowed", lambda: _exists("/etc/unwoke/allow-browsers"), ("allow-browsers", "off"), "install-apps"),
)


def pending_daily() -> bool:
    if OFF.exists():
        return False
    if DONE.exists():
        return False
    r = subprocess.run([ADMIN, "status"], capture_output=True, text=True)
    return "pending" in (r.stdout or "")


def info(parent: Gtk.Window, title: str, body: str) -> None:
    dlg = Gtk.MessageDialog(
        transient_for=parent,
        flags=0,
        message_type=Gtk.MessageType.INFO,
        buttons=Gtk.ButtonsType.OK,
        text=title,
    )
    dlg.format_secondary_text(body[:4000] or "(no output)")
    dlg.run()
    dlg.destroy()


def confirm(parent: Gtk.Window, title: str, body: str) -> bool:
    dlg = Gtk.MessageDialog(
        transient_for=parent,
        flags=0,
        message_type=Gtk.MessageType.QUESTION,
        buttons=Gtk.ButtonsType.OK_CANCEL,
        text=title,
    )
    dlg.format_secondary_text(body)
    resp = dlg.run()
    dlg.destroy()
    return resp == Gtk.ResponseType.OK


def row(title: str, blurb: str, on_do, tutorial: str | None, button: str = "Do this") -> Gtk.Box:
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    box.set_margin_top(8)
    box.set_margin_bottom(8)
    lab = Gtk.Label(label=title, xalign=0)
    lab.get_style_context().add_class("unwoke-title")
    sub = Gtk.Label(label=blurb, xalign=0, wrap=True)
    sub.set_max_width_chars(56)
    btns = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    do = Gtk.Button(label=button)
    do.connect("clicked", lambda *_: on_do())
    btns.pack_start(do, False, False, 0)
    if tutorial:
        t = Gtk.Button(label="Tutorial")
        t.connect("clicked", lambda *_a, s=tutorial: open_tutorial(s))
        btns.pack_start(t, False, False, 0)
    box.pack_start(lab, False, False, 0)
    box.pack_start(sub, False, False, 0)
    box.pack_start(btns, False, False, 0)
    return box


class SetupWindow(Gtk.Window):
    def __init__(self, jump: str) -> None:
        super().__init__(title="Unwoke setup")
        self.set_default_size(640, 560)
        self.flav = flavor()
        self.connect("destroy", Gtk.main_quit)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add(outer)

        head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        head.set_margin_top(16)
        head.set_margin_bottom(8)
        head.set_margin_start(16)
        head.set_margin_end(16)
        title = Gtk.Label(label="Unwoke SecureBlue setup", xalign=0)
        title.set_markup("<span size='large' weight='bold'>Unwoke SecureBlue setup</span>")
        sub = Gtk.Label(
            label=f"Locks stay on unless you turn one off. Flavor: {self.flav}",
            xalign=0,
            wrap=True,
        )
        head.pack_start(title, False, False, 0)
        head.pack_start(sub, False, False, 0)
        if STAGED.exists():
            nag = Gtk.Label(
                label="A signed update is staged. Reboot once to lock updates to our key.",
                xalign=0,
                wrap=True,
            )
            nag.set_markup(
                "<b>A signed update is staged.</b> Reboot once to lock updates to our key."
            )
            head.pack_start(nag, False, False, 8)
        if pending_daily():
            d = Gtk.Label(
                label="No daily (non-wheel) user yet. Create one on the Daily user tab. Wheel should not live on the greeter.",
                xalign=0,
                wrap=True,
            )
            head.pack_start(d, False, False, 4)
        outer.pack_start(head, False, False, 0)

        nb = Gtk.Notebook()
        outer.pack_start(nb, True, True, 0)
        self.nb = nb
        nb.append_page(self._scroll(self._page_start()), Gtk.Label(label="Start"))
        nb.append_page(self._scroll(self._page_on()), Gtk.Label(label="Turn on"))
        nb.append_page(self._scroll(self._page_broken()), Gtk.Label(label="Looks broken"))
        nb.append_page(self._scroll(self._page_stock()), Gtk.Label(label="Stock leftover"))
        nb.append_page(self._scroll(self._page_daily()), Gtk.Label(label="Daily user"))
        self.loosened_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._fill_loosened()
        nb.append_page(self._scroll(self.loosened_box), Gtk.Label(label="You loosened"))
        nb.append_page(self._scroll(self._page_proton()), Gtk.Label(label="Proton.me"))
        nb.append_page(self._scroll(self._page_ivpn()), Gtk.Label(label="IVPN"))
        nb.append_page(self._scroll(self._page_vendors()), Gtk.Label(label="Strict apps"))
        nb.append_page(self._scroll(self._page_mullvad()), Gtk.Label(label="Mullvad"))

        jump_map = {
            "broken": 2,
            "stock": 3,
            "hardware": 1,
            "daily": 4,
            "loosened": 5,
            "proton": 6,
            "ivpn": 7,
            "vendors": 8,
            "mullvad": 9,
        }
        if jump in jump_map:
            nb.set_current_page(jump_map[jump])

    def _scroll(self, child: Gtk.Widget) -> Gtk.ScrolledWindow:
        s = Gtk.ScrolledWindow()
        s.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        s.add(child)
        return s

    def _page_start(self) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_margin_top(12)
        box.set_margin_bottom(16)
        box.set_margin_start(16)
        box.set_margin_end(16)
        keep = Gtk.Button(label="Keep all defaults (recommended)")
        keep.connect("clicked", self.on_keep)
        box.pack_start(keep, False, False, 0)
        box.pack_start(
            Gtk.Label(
                label="Nothing turns off. Hide this window on login. Open later from the app grid or ujust setup.",
                xalign=0,
                wrap=True,
            ),
            False,
            False,
            0,
        )
        hide = Gtk.Button(label="Don't show this on login")
        hide.connect("clicked", self.on_hide)
        box.pack_start(hide, False, False, 0)
        st = Gtk.Button(label="Show status")
        st.connect("clicked", self.on_status)
        box.pack_start(st, False, False, 0)
        rb = Gtk.Button(label="Reboot now")
        rb.connect("clicked", self.on_reboot)
        box.pack_start(rb, False, False, 0)
        tut = Gtk.Button(label="Open first-hour tutorial")
        tut.connect("clicked", lambda *_: open_tutorial("first-hour"))
        box.pack_start(tut, False, False, 0)
        fp = Gtk.Button(label="Fingerprinting vs locks (read only)")
        fp.connect("clicked", lambda *_: open_tutorial("fingerprint"))
        box.pack_start(fp, False, False, 0)
        loose = Gtk.Button(label="You turned something off")
        loose.connect("clicked", lambda *_: self.nb.set_current_page(5))
        box.pack_start(loose, False, False, 0)
        pr = Gtk.Button(label="Proton.me apps (no store)")
        pr.connect("clicked", lambda *_: self.nb.set_current_page(6))
        box.pack_start(pr, False, False, 0)
        iv = Gtk.Button(label="IVPN (WireGuard first)")
        iv.connect("clicked", lambda *_: self.nb.set_current_page(7))
        box.pack_start(iv, False, False, 0)
        va = Gtk.Button(label="All strict apps (vendor list)")
        va.connect("clicked", lambda *_: self.nb.set_current_page(8))
        box.pack_start(va, False, False, 0)
        mu = Gtk.Button(label="Mullvad VPN (WireGuard first)")
        mu.connect("clicked", lambda *_: self.nb.set_current_page(9))
        box.pack_start(mu, False, False, 0)
        return box

    def _fill_loosened(self) -> None:
        for child in list(self.loosened_box.get_children()):
            self.loosened_box.remove(child)
        self.loosened_box.set_margin_start(16)
        self.loosened_box.set_margin_end(16)
        self.loosened_box.set_margin_top(12)
        self.loosened_box.pack_start(
            Gtk.Label(
                label="Defaults are locked. This list is only what you turned off. Put it back does not auto-unlock anything else.",
                xalign=0,
                wrap=True,
            ),
            False,
            False,
            8,
        )
        found = 0
        for title, detect, restore, slug in LOOSENED:
            try:
                on = bool(detect())
            except OSError:
                on = False
            if not on:
                continue
            found += 1
            self.loosened_box.pack_start(
                row(
                    title,
                    "This lock is off. Put it back to the secure default.",
                    lambda a=restore: self.do_restore(*a),
                    slug,
                    "Put it back",
                ),
                False,
                False,
                0,
            )
        if found == 0:
            self.loosened_box.pack_start(
                Gtk.Label(
                    label="Nothing loosened. Defaults are on. That is the healthy state.",
                    xalign=0,
                    wrap=True,
                ),
                False,
                False,
                8,
            )
        self.loosened_box.show_all()

    def do_restore(self, *args: str) -> None:
        if not confirm(self, "Put this lock back?", " ".join(args) + "\nThis restores the secure default."):
            return
        body = run_toggle(*args)
        info(self, "Restored", body)
        self._fill_loosened()

    def _page_on(self) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_margin_start(16)
        box.set_margin_end(16)
        box.pack_start(
            Gtk.Label(
                label="Each line is optional. Defaults stay locked.",
                xalign=0,
                wrap=True,
            ),
            False,
            False,
            8,
        )
        items = [
            ("Flathub: verified apps", "Still no GUI store.", ("flathub", "verified"), "install-apps"),
            ("Bluetooth on", "Wi-Fi is already on.", ("bluetooth", "on"), "bluetooth"),
            ("Camera / microphone on", "Speakers stay. Browser sites are a second door.", ("camera-mic", "on"), "camera-mic"),
            ("NFS/CIFS clients on", "Stock only masks the NFS server. We also blacklist clients.", ("network-fs", "on"), "network-fs"),
            ("Toolbox / distrobox on", "Prefer Flatpak. This is a pet container.", ("toolbox", "on"), "toolbox"),
            ("Homebrew on", "Stock ships brew; we leave it off.", ("brew", "on"), "install-apps"),
            ("Avahi / ModemManager on", ".local names and mobile broadband.", ("extra-daemons", "on"), "first-hour"),
        ]
        if self.flav == "browserless":
            items.append(
                (
                    "Allow host browsers",
                    "You must type ALLOW. A random Firefox is worse than Trivalent.",
                    ("allow-browsers",),
                    "install-apps",
                )
            )
        for title, blurb, args, slug in items:
            box.pack_start(row(title, blurb, lambda a=args: self.do_toggle(*a), slug), False, False, 0)
        return box

    def _page_broken(self) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_margin_start(16)
        box.set_margin_end(16)
        box.pack_start(
            Gtk.Label(
                label="These look like bugs. They are default locks. Nothing turns off until you pick it.",
                xalign=0,
                wrap=True,
            ),
            False,
            False,
            8,
        )
        items = [
            ("Websites broken (JavaScript JIT)", "Restart the house browser after.", ("jitless", "off"), "sites-broken"),
            ("Need camera / mic / USB in the browser", "Wide hole. Prefer a Flatpak client.", ("devices", "off"), "camera-mic"),
            ("Need passwords / autofill", "Hardening pack off. Restart the browser.", ("hardening", "off"), "sites-broken"),
            ("Need extensions", "Leave blocked if you can.", ("extensions", "allow"), "sites-broken"),
            ("WebGL / WebGPU / 3D sites", "Isolation pack off. Restart the browser.", ("isolation", "off"), "sites-broken"),
            ("Flatpaks do nothing", "Grant in Flatseal first when you can.", ("lockdown", "off"), "install-apps"),
            ("Flatpak cannot record / use a mic", "Pulse + PipeWire capture. Speakers in native apps stay.", ("flatpak-record", "off"), "camera-mic"),
            ("Cannot mount a NAS (NFS/CIFS)", "Client modules are blacklisted. Stock only masks the server.", ("network-fs", "on"), "network-fs"),
            ("Screen capture / JS optimizer", "Sandbox pack off. Not Xwayland.", ("sandbox", "off"), "screen-share"),
            ("Wheel cannot log into GNOME/KDE", "Turns admin-split off. TTY always worked.", ("admin-split", "off"), "daily-user"),
        ]
        if self.flav == "brave-origin":
            items.append(
                ("Origin window / GPU / audio dead (Bubblejail)", "Restart Brave Origin.", ("bubblejail", "off"), "sites-broken")
            )
        elif self.flav == "trivalent":
            items.append(
                (
                    "Trivalent clears cookies on exit",
                    "Network Service Sandbox off. Restart Trivalent.",
                    ("network-sandbox", "off"),
                    "sites-broken",
                )
            )
        elif self.flav == "browserless":
            items.append(
                ("Cannot install a browser", "Type ALLOW at the next prompt.", ("allow-browsers",), "install-apps")
            )
        for title, blurb, args, slug in items:
            box.pack_start(row(title, blurb, lambda a=args: self.do_toggle(*a), slug), False, False, 0)

        def store(_=None) -> None:
            info(
                self,
                "No software store",
                "Bazaar, GNOME Software, and Discover are gone on purpose. Flathub is off until you turn it on (Turn on tab). That is not a crash.",
            )
            open_tutorial("install-apps")

        box.pack_start(
            row("No software store (by design)", "Not a crash. Flathub is off.", store, "install-apps"),
            False,
            False,
            0,
        )
        return box

    def _page_stock(self) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_margin_start(16)
        box.set_margin_end(16)
        box.pack_start(
            Gtk.Label(
                label="Their post-install, not ours. Overlay locks are unchanged. A terminal opens because these recipes ask questions.",
                xalign=0,
                wrap=True,
            ),
            False,
            False,
            8,
        )
        stock = [
            ("Enroll their Secure Boot key", "BIOS prompt password: secureblue", "enroll-secureblue-secure-boot-key", "first-hour"),
            ("Apply hardening kernel arguments", "Needed if you rebased instead of their ISO.", "set-kargs-hardening", "first-hour"),
            ("USBGuard from current devices", "Allow what is plugged in now. Block the rest.", "setup-usbguard", "usb"),
            ("audit-secureblue", "Stock audit. Overlay audit is ujust audit-unwoke.", "audit-secureblue", "check-health"),
            ("Open BIOS/UEFI", "ujust bios", "bios", "first-hour"),
        ]
        for title, blurb, recipe, slug in stock:
            box.pack_start(
                row(title, blurb, lambda r=recipe: self.run_stock(r), slug),
                False,
                False,
                0,
            )
        return box

    def _page_daily(self) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_start(16)
        box.set_margin_end(16)
        box.set_margin_top(12)
        box.pack_start(
            Gtk.Label(
                label="Graphical session as a non-wheel user. Wheel stays for TTY and run0. After this, wheel cannot use the greeter.",
                xalign=0,
                wrap=True,
            ),
            False,
            False,
            0,
        )
        self.daily_name = Gtk.Entry()
        self.daily_name.set_placeholder_text("daily username (lowercase)")
        self.daily_pass = Gtk.Entry()
        self.daily_pass.set_visibility(False)
        self.daily_pass.set_placeholder_text("password")
        self.daily_pass2 = Gtk.Entry()
        self.daily_pass2.set_visibility(False)
        self.daily_pass2.set_placeholder_text("password again")
        box.pack_start(self.daily_name, False, False, 0)
        box.pack_start(self.daily_pass, False, False, 0)
        box.pack_start(self.daily_pass2, False, False, 0)
        go = Gtk.Button(label="Create daily user")
        go.connect("clicked", self.on_daily)
        box.pack_start(go, False, False, 0)
        tut = Gtk.Button(label="Tutorial")
        tut.connect("clicked", lambda *_: open_tutorial("daily-user"))
        box.pack_start(tut, False, False, 0)
        return box

    def do_toggle(self, *args: str) -> None:
        if args == ("allow-browsers",):
            if not self._allow_browsers():
                return
            body = run_toggle("allow-browsers", "on", "ALLOW")
        else:
            body = run_toggle(*args)
        info(self, "Toggle", body)
        self._fill_loosened()

    def _allow_browsers(self) -> bool:
        dlg = Gtk.Dialog(title="Type ALLOW", transient_for=self, flags=0)
        dlg.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "OK", Gtk.ResponseType.OK)
        box = dlg.get_content_area()
        box.set_spacing(8)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.pack_start(
            Gtk.Label(
                label="This unlocks easy host browser installs. Type ALLOW to continue.",
                wrap=True,
            ),
            False,
            False,
            0,
        )
        entry = Gtk.Entry()
        box.pack_start(entry, False, False, 0)
        dlg.show_all()
        resp = dlg.run()
        val = entry.get_text().strip()
        dlg.destroy()
        return resp == Gtk.ResponseType.OK and val == "ALLOW"

    def _page_proton(self) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_margin_start(16)
        box.set_margin_end(16)
        box.set_margin_top(12)
        box.pack_start(
            Gtk.Label(
                label="Like stock ujust install-steam, but Proton.me. Strictest: Trivalent. No unverified Flathub. Desktop RPM only after SHA512 and you accept userns.",
                xalign=0,
                wrap=True,
            ),
            False,
            False,
            8,
        )
        items = [
            ("Open Mail / Pass / Calendar / Drive in Trivalent", "Recommended. Zero extra software, zero extra locks.", "--web"),
            ("VPN: WireGuard import", "Official Proton config in Network Settings. No GUI app, no extra repo.", "--vpn"),
            ("Desktop Mail (official RPM + SHA512)", "Named downgrade. Asks before unconfined userns. Reboot after layer.", "--mail-rpm"),
            ("Desktop Pass (official RPM + SHA512)", "Same as Mail. Flathub wrapper is not used.", "--pass-rpm"),
            ("Desktop VPN GUI (stock helper)", "Last. WireGuard is stricter. Extra RPM origin.", "--vpn-gui"),
        ]
        for title, blurb, flag in items:
            box.pack_start(
                row(title, blurb, lambda f=flag: self.run_proton(f), "proton"),
                False,
                False,
                0,
            )
        return box

    def run_proton(self, flag: str) -> None:
        cmd = (
            f"bash /usr/libexec/unwoke/install-proton.sh {flag}; echo; "
            "read -r -p 'Enter to close... ' _ || true"
        )
        for term in (
            ["ptyxis", "--", "bash", "-lc", cmd],
            ["kgx", "-e", "bash", "-lc", cmd],
            ["gnome-terminal", "--", "bash", "-lc", cmd],
            ["konsole", "-e", "bash", "-lc", cmd],
        ):
            if subprocess.call(["bash", "-lc", f"command -v {term[0]}"], stdout=subprocess.DEVNULL) == 0:
                subprocess.Popen(term)
                return
        info(self, "No terminal", f"Run: ujust install-proton   or   bash /usr/libexec/unwoke/install-proton.sh {flag}")

    def _page_ivpn(self) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_margin_start(16)
        box.set_margin_end(16)
        box.set_margin_top(12)
        box.pack_start(
            Gtk.Label(
                label="IVPN is a VPN (AntiTracker is in their official app). Strictest: WireGuard import. No Snap. Official Fedora repo only after you accept an extra RPM origin.",
                xalign=0,
                wrap=True,
            ),
            False,
            False,
            8,
        )
        items = [
            ("WireGuard import (recommended)", "No daemon, no extra repo. DNS stays on the tunnel.", "--wg"),
            ("Open IVPN account in Trivalent", "Download a short-named .conf (GNOME: 15 chars max).", "--account"),
            ("Official CLI + optional UI (signed Fedora repo)", "Their Silverblue path. Weaker than WireGuard; needed for in-app AntiTracker.", "--repo"),
            ("Stock ujust install-vpn", "If present. You still confirm their prompts.", "--stock"),
        ]
        for title, blurb, flag in items:
            box.pack_start(
                row(title, blurb, lambda f=flag: self.run_ivpn(f), "ivpn"),
                False,
                False,
                0,
            )
        return box

    def run_ivpn(self, flag: str) -> None:
        cmd = (
            f"bash /usr/libexec/unwoke/install-ivpn.sh {flag}; echo; "
            "read -r -p 'Enter to close... ' _ || true"
        )
        for term in (
            ["ptyxis", "--", "bash", "-lc", cmd],
            ["kgx", "-e", "bash", "-lc", cmd],
            ["gnome-terminal", "--", "bash", "-lc", cmd],
            ["konsole", "-e", "bash", "-lc", cmd],
        ):
            if subprocess.call(["bash", "-lc", f"command -v {term[0]}"], stdout=subprocess.DEVNULL) == 0:
                subprocess.Popen(term)
                return
        info(self, "No terminal", f"Run: ujust install-ivpn   or   bash /usr/libexec/unwoke/install-ivpn.sh {flag}")

    def _page_vendors(self) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_margin_start(16)
        box.set_margin_end(16)
        box.set_margin_top(12)
        box.pack_start(
            Gtk.Label(
                label="Every vendors{} key. Add a stanza to vendor-installers.json — CI watch/heal and this tab pick it up. Nothing auto-unlocks.",
                xalign=0,
                wrap=True,
            ),
            False,
            False,
            8,
        )
        path = Path("/usr/share/unwoke/vendor-installers.json")
        vendors = {}
        if path.is_file():
            vendors = json.loads(path.read_text(encoding="utf-8")).get("vendors") or {}
        for name, spec in vendors.items():
            title = spec.get("title") or name
            kind = spec.get("kind") or ""
            tut = spec.get("tutorial")
            rec = "Recommended. " if spec.get("strictest") else "Asked downgrade. "
            blurb = rec + kind
            box.pack_start(
                row(title, blurb, lambda n=name: self.run_vendor(n), tut),
                False,
                False,
                0,
            )
        if not vendors:
            box.pack_start(Gtk.Label(label="No vendor-installers.json on this image.", xalign=0), False, False, 0)
        return box

    def run_vendor(self, name: str) -> None:
        cmd = (
            f"bash /usr/libexec/unwoke/install-vendor.sh {name}; echo; "
            "read -r -p 'Enter to close... ' _ || true"
        )
        for term in (
            ["ptyxis", "--", "bash", "-lc", cmd],
            ["kgx", "-e", "bash", "-lc", cmd],
            ["gnome-terminal", "--", "bash", "-lc", cmd],
            ["konsole", "-e", "bash", "-lc", cmd],
        ):
            if subprocess.call(["bash", "-lc", f"command -v {term[0]}"], stdout=subprocess.DEVNULL) == 0:
                subprocess.Popen(term)
                return
        info(self, "No terminal", f"Run: ujust install-vendor {name}")

    def _page_mullvad(self) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_margin_start(16)
        box.set_margin_end(16)
        box.set_margin_top(12)
        box.pack_start(
            Gtk.Label(
                label="Mullvad VPN only (not Mullvad Browser). Strictest: WireGuard import. Official Fedora repo is an extra RPM origin — asked.",
                xalign=0,
                wrap=True,
            ),
            False,
            False,
            8,
        )
        items = [
            ("WireGuard import (recommended)", "No daemon, no extra repo. DNS stays on the tunnel.", "--wg"),
            ("Open WireGuard config page in Trivalent", "Account number, no email. Short .conf name on GNOME.", "--account"),
            ("Official app (signed Fedora repo)", "Layers mullvad-vpn. Weaker than WireGuard.", "--repo"),
            ("Stock ujust install-vpn", "If present. You still confirm their prompts.", "--stock"),
        ]
        for title, blurb, flag in items:
            box.pack_start(
                row(title, blurb, lambda f=flag: self.run_mullvad(f), "mullvad"),
                False,
                False,
                0,
            )
        return box

    def run_mullvad(self, flag: str) -> None:
        cmd = (
            f"bash /usr/libexec/unwoke/install-mullvad.sh {flag}; echo; "
            "read -r -p 'Enter to close... ' _ || true"
        )
        for term in (
            ["ptyxis", "--", "bash", "-lc", cmd],
            ["kgx", "-e", "bash", "-lc", cmd],
            ["gnome-terminal", "--", "bash", "-lc", cmd],
            ["konsole", "-e", "bash", "-lc", cmd],
        ):
            if subprocess.call(["bash", "-lc", f"command -v {term[0]}"], stdout=subprocess.DEVNULL) == 0:
                subprocess.Popen(term)
                return
        info(self, "No terminal", f"Run: ujust install-mullvad")

    def run_stock(self, recipe: str) -> None:
        cmd = f"ujust {recipe}; echo; read -r -p 'Enter to close... ' _ || true"
        if not confirm(self, "Run stock command?", f"ujust {recipe}\nOverlay locks are unchanged."):
            return
        for term in (
            ["ptyxis", "--", "bash", "-lc", cmd],
            ["kgx", "-e", "bash", "-lc", cmd],
            ["gnome-terminal", "--", "bash", "-lc", cmd],
            ["konsole", "-e", "bash", "-lc", cmd],
        ):
            if subprocess.call(["bash", "-lc", f"command -v {term[0]}"], stdout=subprocess.DEVNULL) == 0:
                subprocess.Popen(term)
                return
        info(self, "No terminal", f"Run in a terminal:\nujust {recipe}")

    def on_keep(self, *_: object) -> None:
        mark_seen()
        info(self, "Defaults kept", "Later: app grid → Unwoke setup, or ujust setup / ujust why")
        Gtk.main_quit()

    def on_hide(self, *_: object) -> None:
        mark_seen()
        info(self, "Hidden on login", "The reboot nag still appears until the signed image is booted.")
        Gtk.main_quit()

    def on_status(self, *_: object) -> None:
        body = run_toggle("status")
        info(self, "Status", body)

    def on_reboot(self, *_: object) -> None:
        if not confirm(self, "Reboot now?", "The machine will reboot."):
            return
        subprocess.Popen(["systemctl", "reboot"])

    def on_daily(self, *_: object) -> None:
        name = self.daily_name.get_text().strip().lower()
        p1 = self.daily_pass.get_text()
        p2 = self.daily_pass2.get_text()
        if not name:
            info(self, "Need a name", "Empty username cancels. Same as the first-boot skip.")
            return
        if not p1 or p1 != p2:
            info(self, "Password", "Empty or mismatch. Not created.")
            return
        if not confirm(
            self,
            "Create daily user?",
            f"{name} will not be in wheel. After this, log in as {name} on the greeter. Admin: Ctrl+Alt+F3 and run0.",
        ):
            return
        r = subprocess.run(
            ["run0", "/usr/libexec/unwoke/admin-split.sh", "add-stdin", name],
            input=p1 + "\n",
            capture_output=True,
            text=True,
        )
        self.daily_pass.set_text("")
        self.daily_pass2.set_text("")
        body = ((r.stdout or "") + (r.stderr or "")).strip() or (
            "created" if r.returncode == 0 else "failed"
        )
        info(self, "Daily user", body)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--broken", action="store_true")
    p.add_argument("--stock", action="store_true")
    p.add_argument("--hardware", action="store_true")
    p.add_argument("--daily", action="store_true")
    p.add_argument("--loosened", action="store_true")
    p.add_argument("--proton", action="store_true")
    p.add_argument("--ivpn", action="store_true")
    p.add_argument("--vendors", action="store_true")
    p.add_argument("--mullvad", action="store_true")
    args = p.parse_args()
    jump = ""
    if args.broken:
        jump = "broken"
    elif args.stock:
        jump = "stock"
    elif args.hardware:
        jump = "hardware"
    elif args.daily:
        jump = "daily"
    elif args.loosened:
        jump = "loosened"
    elif args.proton:
        jump = "proton"
    elif args.ivpn:
        jump = "ivpn"
    elif args.vendors:
        jump = "vendors"
    elif args.mullvad:
        jump = "mullvad"
    if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        return 2
    win = SetupWindow(jump)
    win.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
