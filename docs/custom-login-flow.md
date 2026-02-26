# Custom login flow for browser testing

The workflow runs a **headless browser script** to log into your app and capture screenshots. The bundled `scripts/browser-login-example.py` is an example for one app’s login (two-step modal). Your app will differ, so you either **adapt** that example or **create your own** script using this guide.

## Script contract (required)

Your script must follow this contract so the workflow can run it and parse results.

### 1. Environment variables

- **`BROWSER_TEST_USER`** — username/email for app login  
- **`BROWSER_TEST_PASSWORD`** — password for app login  

The workflow passes these into the process; your script should read them and use them only for logging into the app (never log them).

### 2. Command-line arguments

Your script must accept:

| Argument        | Meaning |
|----------------|---------|
| `--base-url`   | Base URL of the app (e.g. `http://127.0.0.1:8101`) |
| `--artifacts-dir` | Directory to save screenshot PNGs |
| `--urls`       | Zero or more `path\|description` pairs (e.g. `'/admin/\|Admin home'`) |
| `--login-only` | (Optional) If present, only perform login and exit; do not visit URLs or take screenshots |

### 3. stdout output (JSON only)

Print exactly one JSON object to **stdout** when the script finishes. Everything else (logs, errors) should go to **stderr**.

**Success (with screenshots):**
```json
{"login": "SUCCESS", "results": [{"url": "/admin/", "description": "Admin home", "filename": "admin-home.png", "status": "PASS", "filepath": "/path/to/artifacts/admin-home.png"}], "summary": "ALL_PASS"}
```

**Success (login-only):**
```json
{"login": "SUCCESS", "results": []}
```

**Login failed:**
```json
{"login": "FAILED", "results": []}
```

Each item in `results` must include at least: `url`, `description`, `status` (`"PASS"` or `"FAIL"`). For `PASS`, include `filename` and `filepath` (path where the screenshot was saved).

### 4. Exit codes

| Code | Meaning |
|------|--------|
| 0 | Login succeeded and all requested screenshots passed |
| 1 | Login failed |
| 2 | Login succeeded but one or more screenshots failed (partial) |

---

## Guided process: build your own login script

### Step 1: Inspect your app’s login flow

1. Start your app locally and open the login page in a browser.
2. Note the **sequence**: e.g. “Go to `/` → click ‘Sign in’ → fill email → Next → fill password → Submit”.
3. Open DevTools (F12) and identify **selectors** for:
   - Link or button that opens the login form
   - Email/username input
   - Password input
   - Submit / “Log in” button
4. Note any **wait** you need (e.g. modal animation, redirect after login).

### Step 2: Choose a template

- **Option A — Start from the template**  
  Copy `scripts/browser-login-template.py` into your repo or skill dir. It has the full contract (args, env, JSON, exit codes) and stub functions `do_login()` and `take_screenshots()` for you to implement.

- **Option B — Adapt the example**  
  Use `scripts/browser-login-example.py` as reference. It implements a two-step modal login (hover user icon → Login → email → Proceed → password → Proceed). Replace selectors and steps in `do_login()` to match your app.

### Step 3: Implement login

In your script, implement the equivalent of:

```python
def do_login(page, base_url, username, password, artifacts_dir):
    # 1. Navigate to login page or homepage
    # 2. Click the element that opens the login form (if needed)
    # 3. Fill username/email
    # 4. Submit or click "Next" if it’s a two-step flow
    # 5. Fill password and submit
    # 6. Wait for navigation or a visible “logged in” element
    # Return True if login succeeded, False otherwise.
```

Use **Playwright** (or another automation library your workflow supports). The workflow runs the script with Python and Playwright available. Prefer `page.wait_for_selector()` over fixed `wait_for_timeout()` where possible.

### Step 4: Screenshots (reuse or customize)

The template and example both implement:

- Parsing `--urls` into `path|description` pairs  
- Visiting each URL, checking for login redirect / error text / error title  
- Saving a screenshot to `artifacts_dir` only when status is `PASS`  
- Building the `results` list in the required JSON shape  

You can keep this logic and only change `do_login()`, or replace it if your app needs different pass/fail rules.

### Step 5: Wire the script into the workflow

1. Set credentials in your environment (or `.env`):
   ```bash
   export BROWSER_TEST_USER="your-app-user"
   export BROWSER_TEST_PASSWORD="your-app-password"
   ```
2. Point the workflow at your script:
   ```bash
   export JIRA_BROWSER_LOGIN_SCRIPT="/path/to/your/login-script.py"
   ```
   If unset, the workflow uses `JIRA_SKILL_DIR/scripts/browser-login-example.py`.

### Step 6: Test locally

Run your script manually before using it in the workflow:

```bash
export BROWSER_TEST_USER="test@example.com"
export BROWSER_TEST_PASSWORD="secret"
python3 /path/to/your/login-script.py \
  --base-url http://127.0.0.1:8101 \
  --artifacts-dir ./artifacts-test \
  --urls '/admin/|Admin home'
```

Check: exit code, JSON on stdout, and that screenshots appear in `./artifacts-test` and look correct.

---

## Summary

| Item | What to do |
|------|------------|
| Contract | Args, env, JSON stdout, exit codes as above |
| Template | Use `scripts/browser-login-template.py` and fill in login + optional screenshot logic |
| Example | Use `scripts/browser-login-example.py` as reference (app-specific; adapt selectors and flow) |
| Config | Set `BROWSER_TEST_USER`, `BROWSER_TEST_PASSWORD`, and optionally `JIRA_BROWSER_LOGIN_SCRIPT` |

For more on how the workflow uses the script and uploads screenshots to Jira, see [reference.md](../reference.md) (Browser Testing and Jira Screenshot rules).
