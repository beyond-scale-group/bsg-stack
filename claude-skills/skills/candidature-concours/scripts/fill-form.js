// Fill + check an online form. DRY RUN by default: never submits.
// Submits only if SUBMIT=1 AND the $GO file exists (written after the human's yes) AND no SUBMITTED marker AND the check passed.
// Usage: OUT=<dir> node fill-form.js <url> <plan.json>
// plan.json: [{"q":"start of the question label","type":"text|choice|checkboxes|multi-select|file","value":"..." | ["..."]}]
const { chromium } = require("playwright-core");
const fs = require("fs");
const [url, planFile] = [process.argv[2], process.argv[3]];
const OUT = process.env.OUT || "."; const plan = JSON.parse(fs.readFileSync(planFile, "utf8"));
const norm = (s) => (s || "").replace(/ /g, " ").replace(/[ \t]+/g, " ").replace(/\s*\n\s*/g, "\n").trim();
(async () => {
  const b = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : { channel: "chrome" });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } }); p.setDefaultTimeout(8000);
  await p.goto(url, { waitUntil: "networkidle", timeout: 60000 }); await p.waitForTimeout(2000);
  for (const re of [/reject all/i, /tout refuser/i, /refuser/i, /decline/i]) {
    const btn = p.getByRole("button", { name: re }).first();
    if (await btn.count() && await btn.isVisible().catch(() => false)) { await btn.click().catch(() => {}); await p.waitForTimeout(800); break; }
  }
  const airtable = (await p.locator('[data-testid="stackedLabel"]').count()) > 0;
  const bloc = (q) => airtable
    ? p.locator('[data-testid="stackedLabel"]').filter({ has: p.locator('[data-testid="page-element-label"]', { hasText: q }) }).first()
    : p.locator("fieldset, div, label").filter({ hasText: q }).last();
  const champ = (q) => airtable ? bloc(q).locator('textarea, input:not([type=hidden]):not([type=file]), [contenteditable]').first() : p.getByLabel(q, { exact: false }).first();
  const opt = (zone, v) => zone.locator('[role="option"], [role="radio"], [role="checkbox"], label').filter({ hasText: new RegExp("^\\s*" + v.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\s*$") }).first();
  const rep = { ok: true, issues: [], fields: [] };
  const fail = (m) => { rep.ok = false; rep.issues.push(m); };
  for (const it of plan) {
    const z = bloc(it.q);
    if (!(await z.count())) { fail(`question not found (hidden, or label changed): ${it.q}`); continue; }
    try {
      if (it.type === "text") { await champ(it.q).fill(it.value); await p.keyboard.press("Tab"); }
      else if (it.type === "choice" || it.type === "checkboxes" || it.type === "multi-select") {
        for (const v of [].concat(it.value)) {
          const dd = z.locator('[data-testid="autocomplete-button"]');
          if (airtable && await dd.count()) { await dd.last().click(); await p.waitForTimeout(500);
            const inp = p.locator('input[type="text"]:focus'); if (await inp.count()) { await inp.fill(v); await p.waitForTimeout(500); }
            await p.locator('ul[id$="-listbox"] [role="option"]').filter({ has: p.locator(`div[title="${v}"]`) }).first().click(); await p.keyboard.press("Escape").catch(() => {}); }
          else if (!airtable && await z.locator("select").count()) await z.locator("select").first().selectOption({ label: v });
          else await opt(z, v).click();
          await p.waitForTimeout(400);
        }
      } else if (it.type === "file") {
        const direct = z.locator('input[type=file]');
        if (await direct.count()) await direct.first().setInputFiles(it.value);
        else { // Airtable: multi-step upload dialog
          await z.locator('[role="button"]', { hasText: /drop files|upload/i }).first().click(); await p.waitForTimeout(2500);
          await p.locator('input.uppy-Dashboard-input:not([webkitdirectory])').first().setInputFiles(it.value); await p.waitForTimeout(2000);
          await p.getByRole("button", { name: /^Upload 1 file/ }).first().click();
          for (let i = 0; i < 60; i++) { await p.waitForTimeout(1000); if (await p.locator(".uppy-Dashboard").filter({ visible: true }).count() === 0) break; }
        }
      }
      await p.waitForTimeout(400);
    } catch (e) { fail(`could not fill: ${it.q} (${e.message.split("\n")[0]})`); }
  }
  await p.waitForTimeout(1500);
  // Read every field back
  for (const it of plan) {
    const z = bloc(it.q); if (!(await z.count())) continue;
    const c = { q: it.q, type: it.type };
    if (it.type === "text") {
      const got = await champ(it.q).evaluate(e => e.value !== undefined ? e.value : e.innerText);
      c.ok = norm(got) === norm(it.value); c.length = (got || "").length; c.expected = it.value.length;
      if (!c.ok) fail(`text read back differs or was cut: ${it.q} (${c.length}/${c.expected} characters)`);
    } else if (it.type === "file") {
      const name = it.value.split("/").pop(); const t = await z.innerHTML();
      c.ok = t.includes(name) || t.includes(name.replace(/ /g, "_")) || /<img/.test(t); if (!c.ok) fail(`attachment missing: ${it.q}`);
    } else {
      const t = norm(await z.innerText()); c.ok = [].concat(it.value).every(v => t.includes(v)); if (!c.ok) fail(`choice not found: ${it.q}`);
    }
    rep.fields.push(c);
  }
  const labels = airtable ? (await p.locator('[data-testid="page-element-label"]').allInnerTexts()).map(norm).filter(Boolean) : [];
  rep.questions_outside_plan = labels.filter(l => !plan.some(it => l.includes(it.q)));
  const requiredMissing = rep.questions_outside_plan.filter(l => /\*\s*$/.test(l));
  if (requiredMissing.length) fail(`required question appeared, not in the plan: ${requiredMissing.join(" / ")}`);
  const page = await p.evaluate(() => document.body.innerText);
  rep.limit_messages = page.match(/[^\n]*(must not exceed|maximum|too long|trop long|dépasse)[^\n]*/gi) || [];
  rep.invalid = await p.$$eval('[aria-invalid="true"]', els => els.map(e => e.getAttribute("aria-label") || e.name || e.id || e.tagName));
  const named = rep.invalid.filter(x => !/^(UL|DIV|SPAN)$/.test(x)), unnamed = rep.invalid.length - named.length;
  if (named.length) fail(`fields rejected by the form: ${named.join(" / ")}`);
  if (unnamed) fail(`${unnamed} choice field(s) empty or rejected (see screenshot)`);
  rep.alerts = ["captcha", "verify you are human"].filter(k => page.toLowerCase().includes(k));
  if (rep.alerts.length) fail("captcha on screen: hand back to the human");
  fs.writeFileSync(OUT + "/check.json", JSON.stringify(rep, null, 1));
  await p.screenshot({ path: OUT + "/filled-form.png", fullPage: true });
  console.log("CHECK", rep.ok ? "OK" : "KO", rep.issues.join(" | "));
  const go = process.env.GO, marker = OUT + "/SUBMITTED";
  if (!rep.ok || process.env.SUBMIT !== "1" || !go || !fs.existsSync(go)) { console.log("STOP without submitting"); await b.close(); return; }
  if (fs.existsSync(marker)) { console.log("ALREADY SUBMITTED - refusing"); await b.close(); return; }
  fs.writeFileSync(marker, new Date().toISOString()); // written BEFORE the click: never a second attempt
  await p.getByRole("button", { name: new RegExp(process.env.BUTTON || "send|submit|envoyer|soumettre|postuler", "i") }).first().click();
  await p.waitForTimeout(8000);
  await p.screenshot({ path: OUT + "/confirmation.png", fullPage: true });
  fs.writeFileSync(OUT + "/after-submit.txt", await p.evaluate(() => document.body.innerText));
  console.log("SUBMITTED, see confirmation.png"); await b.close();
})().catch((e) => { console.error("ERROR", e.message); process.exit(1); });
