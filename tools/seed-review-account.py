#!/usr/bin/env python3
"""Creates (or refreshes) the demo account Apple's App Review team signs in with.

Run from the project folder:  python3 tools/seed-review-account.py
Passwords are made once and kept in review-account.local.txt, which is never uploaded to GitHub.
Safe to run again: it signs in to the existing accounts and resets their demo events and chats.
"""
import json, re, secrets, uuid, datetime, urllib.request, urllib.error, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
cfg = (ROOT / "config.js").read_text()
URL = re.search(r"supabaseUrl:\s*'([^']+)'", cfg).group(1)
KEY = re.search(r"supabaseKey:\s*'([^']+)'", cfg).group(1)
CREDS = ROOT / "review-account.local.txt"

ACCOUNTS = {  # username: (display name, animal, color)
    "appreview": ("App Review", "fox", "#7c5cff"),
    "maya_demo": ("Maya", "rabbit", "#ec4899"),
    "leo_demo": ("Leo", "wolf", "#3b82f6"),
}

def call(method, path, token=None, body=None, quiet=False):
    headers = {"apikey": KEY, "Content-Type": "application/json", "Prefer": "return=minimal" if quiet else "return=representation"}
    if token: headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(URL + path, method=method, headers=headers,
                                 data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(req) as r:
            text = r.read().decode()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {path}: {e.code} {e.read().decode()[:300]}")

def load_passwords():
    pw = {}
    if CREDS.exists():
        for line in CREDS.read_text().splitlines():
            m = re.match(r"(\w+) password: (\S+)", line)
            if m: pw[m.group(1)] = m.group(2)
    for u in ACCOUNTS:
        pw.setdefault(u, "Bloom-" + secrets.token_urlsafe(12))
    return pw

def session(username, password):
    email = f"{username}@users.daybloom.app"
    try:
        s = call("POST", "/auth/v1/signup", body={"email": email, "password": password})
        if s.get("access_token"): return s["access_token"], s["user"]["id"]
    except RuntimeError as e:
        if "already" not in str(e).lower(): raise
    s = call("POST", "/auth/v1/token?grant_type=password", body={"email": email, "password": password})
    return s["access_token"], s["user"]["id"]

today = datetime.date.today()
def day(offset): return (today + datetime.timedelta(days=offset)).isoformat()
def next_weekday(weekday):  # 0 = Monday
    return day((weekday - today.weekday()) % 7)

EVENTS = {  # title, date, time, repeat, remind, color, private, all_day, notes
    "appreview": [
        ("Math homework", day(0), "18:00", "daily", "15", "#7c5cff", False, False, "Pages 42 to 45"),
        ("Soccer practice", next_weekday(1), "16:30", "weekly", "30", "#22c55e", False, False, "Bring water and cleats"),
        ("Soccer practice", next_weekday(3), "16:30", "weekly", "30", "#22c55e", False, False, "Bring water and cleats"),
        ("Science fair", day(3), "09:00", "none", "1440", "#f59e0b", False, True, ""),
        ("Mom's birthday", day(12), "09:00", "yearly", "1440", "#ec4899", False, True, "Make a card"),
        ("Dentist", day(5), "10:00", "none", "60", "#94a3b8", True, False, "This one is private (Only me)"),
    ],
    "maya_demo": [
        ("Piano lesson", next_weekday(2), "16:00", "weekly", "15", "#ec4899", False, False, ""),
        ("Art club", next_weekday(4), "15:30", "weekly", "15", "#14b8a6", False, False, "Bring sketchbook"),
        ("Movie night", next_weekday(5), "19:00", "weekly", "0", "#f59e0b", False, False, ""),
    ],
    "leo_demo": [
        ("Basketball", next_weekday(0), "17:00", "weekly", "30", "#3b82f6", False, False, ""),
        ("Study group", next_weekday(2), "18:30", "weekly", "15", "#7c5cff", False, False, "Library, room 2"),
    ],
}

def save(pw):
    CREDS.write_text(
        "Daybloom: App Review demo account (keep private, never upload)\n\n"
        f"Sign-in username: appreview\nappreview password: {pw['appreview']}\n\n"
        "Demo friends (only needed to log in as them for testing):\n"
        f"maya_demo password: {pw['maya_demo']}\nleo_demo password: {pw['leo_demo']}\n"
    )

def main():
    pw = load_passwords()
    save(pw)
    users = {}
    for u, (name, animal, color) in ACCOUNTS.items():
        token, uid = session(u, pw[u])
        call("POST", "/rest/v1/rpc/ensure_profile", token, {"p_name": name, "p_shirt": color, "p_style": animal})
        call("PATCH", f"/rest/v1/profiles?id=eq.{uid}&select=id", token, {"name": name, "shirt": color, "style": animal}, quiet=True)
        call("DELETE", f"/rest/v1/events?owner=eq.{uid}", token, quiet=True)
        rows = [{"id": str(uuid.uuid4()), "owner": uid, "title": t, "date": d, "time": tm, "repeat": rp, "remind": rm,
                 "color": c, "private": pv, "all_day": ad, "notes": n} for (t, d, tm, rp, rm, c, pv, ad, n) in EVENTS[u]]
        call("POST", "/rest/v1/events", token, rows, quiet=True)
        users[u] = (token, uid)
        print(f"ready: @{u} ({name})")

    me_t, me = users["appreview"]
    for friend in ("maya_demo", "leo_demo"):
        ft, fid = users[friend]
        code = call("POST", "/rest/v1/rpc/current_code", ft, {})["code"]
        try: call("POST", "/rest/v1/rpc/add_friend", me_t, {"p_code": code})
        except RuntimeError as e:
            if "own code" not in str(e): print("  (already friends)" if "duplicate" in str(e) else f"  note: {e}")
    print("friends: App Review <-> Maya, Leo")

    maya_t, maya = users["maya_demo"]; leo_t, leo = users["leo_demo"]
    dm = call("POST", "/rest/v1/rpc/start_chat", me_t, {"p_friend": maya})
    if not call("GET", f"/rest/v1/messages?conversation_id=eq.{dm}&select=id", me_t):
        first = call("POST", "/rest/v1/messages", maya_t, {"conversation_id": dm, "body": "Hi! Want to study for the science test tomorrow?"})[0]
        call("POST", "/rest/v1/messages", me_t, {"conversation_id": dm, "body": "Yes! Library at 4?"})
        call("POST", "/rest/v1/messages", maya_t, {"conversation_id": dm, "body": "Perfect, see you there"})
        call("POST", "/rest/v1/rpc/set_reaction", me_t, {"p_message": first["id"], "p_kind": "heart"})
    print("chat: App Review <-> Maya")

    groups = call("GET", "/rest/v1/conversations?is_group=eq.true&name=eq.Study%20group&select=id", me_t)
    if groups: grp = groups[0]["id"]
    else:
        grp = call("POST", "/rest/v1/rpc/create_group", me_t, {"p_name": "Study group", "p_members": [maya, leo]})
        call("POST", "/rest/v1/rpc/update_chat", me_t, {"p_conv": grp, "p_name": "Study group", "p_kind": "icon", "p_value": "book", "p_color": "#7c5cff"})
        call("POST", "/rest/v1/messages", leo_t, {"conversation_id": grp, "body": "Who's bringing snacks Wednesday?"})
        m = call("POST", "/rest/v1/messages", maya_t, {"conversation_id": grp, "body": "I can bring cookies"})[0]
        call("POST", "/rest/v1/rpc/set_reaction", leo_t, {"p_message": m["id"], "p_kind": "like"})
    print("group chat: Study group (App Review, Maya, Leo)")

    print(f"sign-in details are in {CREDS.name}")

if __name__ == "__main__":
    main()
