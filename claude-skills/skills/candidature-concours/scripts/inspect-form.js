// Blank survey of an online form: questions, real field types, required flag, options, measured limits.
// Never submits. Usage: PROBE=1 node inspect-form.js <url> <out-dir>
const { chromium } = require("playwright-core");
const fs = require("fs");
const [url, out] = [process.argv[2], process.argv[3] || "."];
(async () => {
  const b = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : { channel: "chrome" });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(url, { waitUntil: "networkidle", timeout: 60000 });
  await p.waitForTimeout(2000);
  // cookie banner: reject when possible (role lookup also reaches shadow roots)
  for (const re of [/reject all/i, /tout refuser/i, /refuser/i, /decline/i, /accept all/i, /accepter/i]) {
    const btn = p.getByRole("button", { name: re }).first();
    if (await btn.count() && await btn.isVisible().catch(() => false)) { await btn.click().catch(() => {}); await p.waitForTimeout(800); break; }
  }
  const body = (await p.evaluate(() => document.body.innerText)).toLowerCase();
  const alerts = ["captcha", "recaptcha", "hcaptcha", "verify you are human", "sign in", "se connecter", "log in"].filter(k => body.includes(k));
  const fields = await p.evaluate(() => {
    const vis = (e) => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
    const txt = (e) => (e ? e.innerText || e.textContent || "" : "").replace(/\s+/g, " ").trim();
    const res = [];
    // Airtable: one block per question
    const at = [...document.querySelectorAll('[data-testid="stackedLabel"]')];
    if (at.length) {
      for (const e of at) {
        const l = e.querySelector('[data-testid="page-element-label"]');
        const ce = e.querySelector('[data-testid="cell-editor"]');
        const ta = e.querySelector("textarea, input[type=text], input[type=email], input[type=url], input[type=number]");
        res.push({
          question: txt(l), type: ce ? ce.getAttribute("data-columntype") : "unknown",
          required: /\*\s*$/.test(txt(l)) || !!e.querySelector('[aria-required="true"]'),
          maxlength: ta && ta.maxLength > 0 ? ta.maxLength : null,
          options: [...e.querySelectorAll('[role="option"], [role="radio"], [role="checkbox"]')].map(txt).filter(Boolean),
          attachment: /drop files here|upload/i.test(txt(e)) && !ce,
          dropdown: !!e.querySelector('[data-testid="autocomplete-button"]'),
          help: txt(e.querySelector('[data-testid="page-element-description"]')) || null,
        });
      }
      return { engine: "airtable", fields: res };
    }
    // Plain HTML form
    const seen = new Set();
    for (const el of document.querySelectorAll("input, textarea, select, [contenteditable=true]")) {
      if (!vis(el) || ["hidden", "submit", "button", "reset", "image"].includes(el.type)) continue;
      const key = el.type === "radio" || el.type === "checkbox" ? "g:" + (el.name || el.id) : el;
      if (seen.has(key)) continue; seen.add(key);
      let label = el.labels && el.labels[0] ? txt(el.labels[0]) : "";
      const fs_ = el.closest("fieldset");
      if ((el.type === "radio" || el.type === "checkbox") && fs_ && fs_.querySelector("legend")) label = txt(fs_.querySelector("legend"));
      if (!label) label = el.getAttribute("aria-label") || el.placeholder || el.name || el.id || "";
      const f = { question: label, type: el.tagName === "SELECT" ? "select" : el.isContentEditable ? "rich text" : el.tagName === "TEXTAREA" ? "long text" : el.type,
        required: el.required || el.getAttribute("aria-required") === "true", maxlength: el.maxLength > 0 ? el.maxLength : null, options: [] };
      if (el.tagName === "SELECT") f.options = [...el.options].map(o => txt(o)).filter(Boolean);
      if ((el.type === "radio" || el.type === "checkbox") && el.name)
        f.options = [...document.querySelectorAll(`input[name="${CSS.escape(el.name)}"]`)].map(i => (i.labels && i.labels[0] ? txt(i.labels[0]) : i.value));
      res.push(f);
    }
    return { engine: "html", fields: res };
  });
  // Limit probe (PROBE=1): paste a long text in every text field, read what the field keeps and any new
  // error message on the page, then clear the field. Nothing is submitted.
  if (process.env.PROBE === "1") {
    const long = "lorem ipsum ".repeat(420); // 5,040 characters, 840 words
    const blocs = fields.engine === "airtable" ? p.locator('[data-testid="stackedLabel"]') : null;
    for (const [i, f] of fields.fields.entries()) {
      if (!/text|texte|email|url|richText|multilineText/i.test(f.type || "")) continue;
      let el, zone;
      if (blocs) { zone = blocs.nth(i); el = zone.locator('textarea, input:not([type=hidden]):not([type=file]), [contenteditable]').first(); }
      else { el = p.locator("input:visible, textarea:visible, [contenteditable=true]:visible").filter({ hasNot: p.locator("[type=hidden]") }).nth(i); zone = el.locator("xpath=ancestor::*[self::div or self::fieldset or self::label][1]"); }
      if (!(await el.count())) continue;
      try {
        const before = new Set((await p.evaluate(() => document.body.innerText)).split("\n"));
        await el.fill(long, { timeout: 5000 }); await p.keyboard.press("Tab"); await p.waitForTimeout(700);
        const kept = await el.evaluate(e => (e.value !== undefined ? e.value : e.innerText).length);
        const invalid = (await el.getAttribute("aria-invalid")) === "true";
        const fresh = (await p.evaluate(() => document.body.innerText)).split("\n").map(l => l.trim()).filter(l => l.length >= 12 && !before.has(l) && !/lorem/.test(l));
        const announced = ((await zone.innerText().catch(() => "")).match(/[^\n]*\b(maximum|max\.?|at most|limit|caract\S*|characters|words|mots)\b[^\n]*/i) || [null])[0];
        f.measured_limit = kept < long.length ? `truncated at ${kept} characters while typing`
          : fresh.length || invalid ? `rejected after input: ${fresh.join(" / ") || "field marked invalid"}`
          : `no limit seen at ${long.length} characters`;
        if (announced) f.announced_limit = announced.trim();
        await el.fill("", { timeout: 5000 }); await p.keyboard.press("Tab"); await p.waitForTimeout(200);
      } catch (e) { f.measured_limit = "not measured: " + e.message.split("\n")[0]; }
    }
  }
  const submit = await p.$$eval('button, input[type=submit]', els => els.filter(e => e.offsetParent !== null).map(e => (e.innerText || e.value || "").trim()).filter(t => /send|submit|envoyer|soumettre|apply|postuler|valider/i.test(t)));
  const rep = { url, date: new Date().toISOString(), engine: fields.engine, question_count: fields.fields.length, submit_button: submit, alerts, questions: fields.fields.map((f, i) => ({ n: i + 1, ...f })) };
  fs.writeFileSync(out + "/survey.json", JSON.stringify(rep, null, 1));
  await p.screenshot({ path: out + "/blank-form.png", fullPage: true });
  console.log(JSON.stringify({ engine: rep.engine, question_count: rep.question_count, submit_button: submit, alerts }));
  await b.close();
})().catch((e) => { console.error("ERROR", e.message); process.exit(1); });
