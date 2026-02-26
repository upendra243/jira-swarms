#!/usr/bin/env python3
"""
Example headless browser login + screenshot script for jira-swarms.

This is an app-specific example: a two-step modal login (homepage -> hover user
icon -> click Login -> fill email -> Proceed -> fill password -> Proceed).
Selectors and flow are for one app only; they will not work for yours as-is.

To use browser testing with your own app:
  - See docs/custom-login-flow.md for a guided process to implement your login.
  - Start from scripts/browser-login-template.py (contract + stubs) or adapt
    this example by replacing selectors and steps in do_login().

Contract (same for any script):
  - Accepts: --base-url, --artifacts-dir, --urls (path|description), --login-only
  - Env: BROWSER_TEST_USER, BROWSER_TEST_PASSWORD
  - Stdout: JSON {"login": "SUCCESS"|"FAILED", "results": [...]}
  - Exit: 0 = all pass, 1 = login failed, 2 = partial failures

Usage:
    python3 browser-login-example.py --base-url http://127.0.0.1:8101 \\
        --artifacts-dir artifacts/PROJ-123 \\
        --urls '/admin/|Admin home' '/admin/users/|User list'
"""
import argparse
import json
import os
import re
import sys

from playwright.sync_api import sync_playwright


def sanitize_filename(desc):
    name = desc.lower().strip()
    name = re.sub(r"[^a-z0-9]+", "-", name)
    name = name.strip("-")
    return name[:80] + ".png"


def js_click_button(page, text_match):
    return page.evaluate(f"""() => {{
        const btns = document.querySelectorAll('button');
        for (const btn of btns) {{
            const text = btn.textContent.trim().toLowerCase();
            if (text.includes('{text_match}') && btn.offsetParent !== null) {{
                btn.click();
                return btn.textContent.trim();
            }}
        }}
        return null;
    }}""")


def do_login(page, base_url, username, password, artifacts_dir):
    """App-specific: two-step modal login (.fa-user -> span.lgnBtn -> email -> Proceed -> password -> Proceed). Adapt for your app or use browser-login-template.py; see docs/custom-login-flow.md."""
    print(f"[login] Navigating to {base_url}/", file=sys.stderr)
    page.goto(f"{base_url}/", timeout=30000, wait_until="domcontentloaded")
    page.wait_for_timeout(3000)

    user_icon = page.query_selector(".fa-user")
    if user_icon:
        parent = user_icon.evaluate_handle("el => el.closest('a') || el.parentElement")
        if parent:
            parent.as_element().hover()
            page.wait_for_timeout(1500)

    login_span = page.query_selector("span.lgnBtn")
    if login_span:
        login_span.click()
        page.wait_for_timeout(2000)
    else:
        print("[login] WARNING: span.lgnBtn not found (adapt selector for your app)", file=sys.stderr)
        return False

    email_field = page.query_selector("input#username.login-name") or page.query_selector("input#username")
    if not email_field:
        print("[login] ERROR: input#username not found", file=sys.stderr)
        return False
    email_field.fill(username)
    page.wait_for_timeout(500)

    result = js_click_button(page, "proceed")
    if not result:
        print("[login] ERROR: Proceed button not found", file=sys.stderr)
        return False
    page.wait_for_timeout(3000)

    password_field = page.query_selector("input#password[type='password']") or page.query_selector("input[type='password']:visible")
    if not password_field:
        print("[login] ERROR: Password field not found", file=sys.stderr)
        return False
    password_field.fill(password)
    page.wait_for_timeout(500)
    result = js_click_button(page, "proceed")
    if not result:
        password_field.press("Enter")
    page.wait_for_timeout(5000)

    print(f"[login] Login complete. URL: {page.url}", file=sys.stderr)
    return True


def take_screenshots(page, base_url, urls, artifacts_dir):
    results = []
    for url_spec in urls:
        parts = url_spec.split("|", 1)
        path = parts[0].strip()
        description = parts[1].strip() if len(parts) > 1 else path
        filename = sanitize_filename(description)
        full_url = f"{base_url}{path}"
        print(f"[screenshot] {full_url} ({description})", file=sys.stderr)
        result = {"url": path, "description": description, "filename": filename}
        try:
            page.goto(full_url, timeout=30000, wait_until="domcontentloaded")
            page.wait_for_timeout(3000)
            current_url = page.url
            page_title = page.title()
            page_text = page.evaluate("() => document.body ? document.body.innerText.substring(0, 500) : ''")
            is_error = False
            if "/login" in current_url.lower() and "/login" not in path.lower():
                is_error = True
                result["status"] = "FAIL"
                result["reason"] = "Redirected to login"
            elif any(err in page_text for err in ["Traceback", "OperationalError", "SyntaxError", "DoesNotExist", "Exception Value"]):
                is_error = True
                result["status"] = "FAIL"
                result["reason"] = page_text[:150].replace("\n", " ")
            elif any(err in page_title.lower() for err in ["server error", "500", "404", "not found"]):
                is_error = True
                result["status"] = "FAIL"
                result["reason"] = f"Page error: {page_title}"
            else:
                result["status"] = "PASS"
            if not is_error:
                filepath = os.path.join(artifacts_dir, filename)
                page.screenshot(path=filepath, full_page=False)
                result["filepath"] = filepath
            else:
                print(f"[screenshot] FAIL (not saved): {result.get('reason', '')}", file=sys.stderr)
        except Exception as e:
            result["status"] = "FAIL"
            result["reason"] = str(e)[:200]
        results.append(result)
    return results


def main():
    parser = argparse.ArgumentParser(description="Example browser login + screenshots for jira-swarms")
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--artifacts-dir", required=True)
    parser.add_argument("--urls", nargs="*", default=[], help="'path|description' pairs")
    parser.add_argument("--login-only", action="store_true")
    args = parser.parse_args()

    username = os.environ.get("BROWSER_TEST_USER")
    password = os.environ.get("BROWSER_TEST_PASSWORD")
    if not username or not password:
        print("ERROR: BROWSER_TEST_USER and BROWSER_TEST_PASSWORD must be set", file=sys.stderr)
        sys.exit(1)

    os.makedirs(args.artifacts_dir, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(viewport={"width": 1920, "height": 1080})
        page = context.new_page()
        logged_in = do_login(page, args.base_url, username, password, args.artifacts_dir)
        if not logged_in:
            print("[login] Retrying...", file=sys.stderr)
            page.goto("about:blank")
            page.wait_for_timeout(1000)
            logged_in = do_login(page, args.base_url, username, password, args.artifacts_dir)
        if not logged_in:
            print(json.dumps({"login": "FAILED", "results": []}))
            sys.exit(1)
        if args.login_only:
            print(json.dumps({"login": "SUCCESS", "results": []}))
            sys.exit(0)
        results = take_screenshots(page, args.base_url, args.urls, args.artifacts_dir)
        browser.close()
        all_pass = all(r["status"] == "PASS" for r in results)
        print(json.dumps({"login": "SUCCESS", "results": results, "summary": "ALL_PASS" if all_pass else "SOME_FAILED"}))
        sys.exit(0 if all_pass else 2)


if __name__ == "__main__":
    main()
