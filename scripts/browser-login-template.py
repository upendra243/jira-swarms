#!/usr/bin/env python3
"""
Template for a jira-swarms browser login + screenshot script.

Copy this file and implement do_login() for your app. The script contract
(args, env vars, JSON stdout, exit codes) is already in place. See
docs/custom-login-flow.md for the full guided process.

Contract:
  - Args: --base-url, --artifacts-dir, --urls (path|description), --login-only
  - Env: BROWSER_TEST_USER, BROWSER_TEST_PASSWORD
  - Stdout: single JSON object with "login" and "results"
  - Exit: 0 = all pass, 1 = login failed, 2 = partial failures
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


def do_login(page, base_url, username, password, artifacts_dir):
    """
    Implement your app's login flow here.

    - Navigate to the login page (or homepage and open login UI).
    - Fill username and password using your app's selectors.
    - Submit and wait for successful login (e.g. URL change or visible element).
    - Return True if login succeeded, False otherwise.

    Use page.query_selector(), page.fill(), page.click(), page.wait_for_selector(), etc.
    Log to stderr with print(..., file=sys.stderr).
    """
    # TODO: Replace with your app's login steps. Example skeleton:
    # page.goto(f"{base_url}/login", timeout=30000, wait_until="domcontentloaded")
    # page.wait_for_selector("input[name='email']", timeout=10000)
    # page.fill("input[name='email']", username)
    # page.fill("input[name='password']", password)
    # page.click("button[type='submit']")
    # page.wait_for_url("**/dashboard**", timeout=15000)  # or wait_for_selector for a post-login element
    # return True
    print("[login] TODO: Implement do_login() for your app. See docs/custom-login-flow.md", file=sys.stderr)
    return False


def take_screenshots(page, base_url, urls, artifacts_dir):
    """Visit each URL, detect errors, save screenshot if PASS. You can customize error detection."""
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
    parser = argparse.ArgumentParser(description="Browser login + screenshots for jira-swarms (template)")
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
