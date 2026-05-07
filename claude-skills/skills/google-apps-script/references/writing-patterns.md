# Apps Script writing patterns

Reference for writing Google Apps Script code. Load this file when the
user is authoring `.gs`/`.js` scripts — not needed for pure clasp CLI
operations (push, pull, deploy).

Adapted from [jezweb/claude-skills](https://github.com/jezweb/claude-skills)
(google-apps-script, 956 installs) under MIT license.

## Script structure template

```javascript
/**
 * [Project Name] - [Brief Description]
 *
 * INSTALL: Extensions > Apps Script > paste this > Save > Reload sheet
 */

// --- CONFIGURATION ---
const SOME_SETTING = 'value';

// --- MENU SETUP ---
function onOpen() {
  const ui = SpreadsheetApp.getUi();
  ui.createMenu('My Menu')
    .addItem('Do Something', 'myFunction')
    .addSeparator()
    .addSubMenu(ui.createMenu('More Options')
      .addItem('Option A', 'optionA'))
    .addToUi();
}

// --- FUNCTIONS ---
function myFunction() {
  // Implementation
}
```

## Critical rules

### Public vs private functions

Functions ending with `_` (underscore) are **private** and CANNOT be
called from client-side HTML via `google.script.run`. Silent failure —
the call simply doesn't work with no error.

```javascript
// WRONG — dialog can't call this
function doWork_() { return 'done'; }

// RIGHT — dialog can call this
function doWork() { return 'done'; }
```

### Batch operations (mandatory)

Cell-by-cell `getValue()`/`setValue()` is ~70x slower than bulk.

```javascript
// SLOW (70s on 100x100)
for (let i = 1; i <= 100; i++) {
  const val = sheet.getRange(i, 1).getValue();
}

// FAST (1s)
const allData = sheet.getRange(1, 1, 100, 1).getValues();
for (const row of allData) {
  const val = row[0];
}
```

### Flush before returning

Call `SpreadsheetApp.flush()` before returning from functions that
modify the sheet, especially when called from HTML dialogs.

### V8 runtime — unavailable APIs

| Missing API | Apps Script alternative |
|---|---|
| `setTimeout` / `setInterval` | `Utilities.sleep(ms)` (blocking) |
| `fetch` | `UrlFetchApp.fetch()` |
| `FormData` | Build payload manually |
| `URL` | String manipulation |
| `crypto` | `Utilities.computeDigest()` / `Utilities.getUuid()` |

### Simple vs installable triggers

| Feature | Simple (`onEdit`) | Installable |
|---|---|---|
| Auth required | No | Yes |
| Send email | No | Yes |
| Access other files | No | Yes |
| URL fetch | No | Yes |
| Open dialogs | No | Yes |
| Runs as | Active user | Trigger creator |

### Custom spreadsheet functions

```javascript
/**
 * @param {string} input The input value
 * @return {string} The result
 * @customfunction
 */
function MY_FUNCTION(input) {
  // Can use: basic JS, Utilities, CacheService
  // CANNOT: MailApp, UrlFetchApp, SpreadsheetApp.getUi(), triggers
  return input.toUpperCase();
}
```

30-second limit. Must include `@customfunction` JSDoc tag.

## Common patterns

### Toast / alert / prompt

```javascript
// Toast
SpreadsheetApp.getActiveSpreadsheet().toast('Done!', 'Title', 5);

// Yes/No
const ui = SpreadsheetApp.getUi();
const response = ui.alert('Delete?', 'Cannot undo.', ui.ButtonSet.YES_NO);
if (response === ui.Button.YES) { /* proceed */ }

// Prompt
const result = ui.prompt('Enter name:', ui.ButtonSet.OK_CANCEL);
if (result.getSelectedButton() === ui.Button.OK) {
  const name = result.getResponseText();
}
```

### Modal progress dialog

Block interaction during long operations with a spinner that auto-closes.

```javascript
function showProgress(message, serverFn) {
  const html = HtmlService.createHtmlOutput(`
    <style>
      body { font-family: 'Google Sans', Arial; display: flex;
        flex-direction: column; align-items: center; justify-content: center;
        height: 100%; margin: 0; padding: 20px; box-sizing: border-box; }
      .spinner { width: 36px; height: 36px; border: 4px solid #e0e0e0;
        border-top: 4px solid #1a73e8; border-radius: 50%;
        animation: spin 0.8s linear infinite; margin-bottom: 16px; }
      @keyframes spin { to { transform: rotate(360deg); } }
      .msg { font-size: 14px; color: #333; text-align: center; }
      .done { color: #1e8e3e; font-weight: 500; }
      .err { color: #d93025; font-weight: 500; }
    </style>
    <div class="spinner" id="sp"></div>
    <div class="msg" id="m">${message}</div>
    <script>
      google.script.run
        .withSuccessHandler(r => {
          document.getElementById('sp').style.display='none';
          const m=document.getElementById('m');
          m.className='msg done'; m.innerText='Done! '+(r||'');
          setTimeout(()=>google.script.host.close(),1200);
        })
        .withFailureHandler(e => {
          document.getElementById('sp').style.display='none';
          const m=document.getElementById('m');
          m.className='msg err'; m.innerText='Error: '+e.message;
          setTimeout(()=>google.script.host.close(),3000);
        })
        .${serverFn}();
    </script>
  `).setWidth(320).setHeight(140);
  SpreadsheetApp.getUi().showModalDialog(html, 'Working...');
}
```

### Sidebar apps

```javascript
function showSidebar() {
  const html = HtmlService.createHtmlOutput(`
    <h3>Quick Entry</h3>
    <select id="worker"><option>Alice</option><option>Bob</option></select>
    <input id="suburb" placeholder="Suburb">
    <button onclick="submit()">Add</button>
    <script>
      function submit() {
        google.script.run.withSuccessHandler(() => alert('Added!'))
          .addJob(document.getElementById('worker').value,
                  document.getElementById('suburb').value);
      }
    </script>
  `).setTitle('Entry').setWidth(300);
  SpreadsheetApp.getUi().showSidebar(html);
}

function addJob(worker, suburb) {
  SpreadsheetApp.getActiveSpreadsheet().getActiveSheet()
    .appendRow([new Date(), worker, suburb]);
}
```

### Triggers

```javascript
// onEdit (simple — limited permissions, no auth)
function onEdit(e) {
  const sheet = e.source.getActiveSheet();
  if (sheet.getName() !== 'Data') return;
  if (e.range.getColumn() !== 3) return;
  sheet.getRange(e.range.getRow(), 4).setValue(new Date());
}

// Installable triggers — run setup once manually
function createTriggers() {
  ScriptApp.newTrigger('dailyReport')
    .timeBased().atHour(8).everyDays(1).create();

  ScriptApp.newTrigger('onEditFull')
    .forSpreadsheet(SpreadsheetApp.getActive()).onEdit().create();

  ScriptApp.newTrigger('onFormSubmit')
    .forSpreadsheet(SpreadsheetApp.getActive()).onFormSubmit().create();
}
```

### Email from Sheets

```javascript
function emailReport() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  const data = sheet.getRange('A2:E10').getDisplayValues();
  let body = '<h2>Report</h2><table border="1" cellpadding="8">';
  body += '<tr><th>Job</th><th>Suburb</th><th>Time</th><th>Price</th></tr>';
  for (const row of data) {
    if (row[0]) body += '<tr>' + row.map(c => '<td>' + c + '</td>').join('') + '</tr>';
  }
  body += '</table>';
  MailApp.sendEmail({
    to: 'team@example.com',
    subject: 'Report - ' + sheet.getName(),
    htmlBody: body
  });
}
```

### PDF export

```javascript
function exportSheetAsPdf() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const url = ss.getUrl().replace(/\/edit.*$/, '')
    + '/export?exportFormat=pdf&format=pdf&size=A4&portrait=true'
    + '&fitw=true&sheetnames=false&printtitle=false&gridlines=false'
    + '&gid=' + ss.getActiveSheet().getSheetId();
  const blob = UrlFetchApp.fetch(url, {
    headers: { 'Authorization': 'Bearer ' + ScriptApp.getOAuthToken() }
  }).getBlob().setName('report.pdf');
  MailApp.sendEmail({
    to: 'boss@example.com', subject: 'Report PDF',
    body: 'See attached.', attachments: [blob]
  });
}
```

### External API calls

```javascript
// GET
function fetchData() {
  const r = UrlFetchApp.fetch('https://api.example.com/data', {
    headers: { 'Authorization': 'Bearer ' + getApiKey() }
  });
  return JSON.parse(r.getContentText());
}

// POST
function postData(payload) {
  const r = UrlFetchApp.fetch('https://api.example.com/submit', {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  });
  if (r.getResponseCode() !== 200)
    throw new Error('API error: ' + r.getContentText());
  return JSON.parse(r.getContentText());
}
```

### Data validation dropdowns

```javascript
// From list
const rule = SpreadsheetApp.newDataValidation()
  .requireValueInList(['A', 'B', 'C'], true)
  .setAllowInvalid(false).setHelpText('Pick one').build();
sheet.getRange('C3:C50').setDataValidation(rule);

// From range
const rule2 = SpreadsheetApp.newDataValidation()
  .requireValueInRange(ss.getSheetByName('Lookups').getRange('A1:A100'))
  .build();
sheet.getRange('B3:B50').setDataValidation(rule2);
```

### Properties Service (persistent storage)

Three scopes: `getScriptProperties()` (shared),
`getUserProperties()` (per user), `getDocumentProperties()` (per doc).
All use `.setProperty(key, value)` / `.getProperty(key)`. 500 KB limit.

### Batch email sender with quota check

```javascript
function sendBatchEmails() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet()
    .getSheetByName('Recipients');
  const data = sheet.getRange('A2:C' + sheet.getLastRow()).getValues();
  const remaining = MailApp.getRemainingDailyQuota();
  if (remaining < data.length) {
    SpreadsheetApp.getUi().alert(
      'Only ' + remaining + ' emails left. Need ' + data.length);
    return;
  }
  let sent = 0;
  for (let i = 0; i < data.length; i++) {
    const [email, name, status] = data[i];
    if (!email || status === 'Sent') continue;
    try {
      MailApp.sendEmail({
        to: email, subject: 'Update',
        htmlBody: '<p>Hi ' + name + ',</p><p>Your update...</p>'
      });
      sheet.getRange(i + 2, 3).setValue('Sent');
      sent++;
    } catch (e) {
      sheet.getRange(i + 2, 3).setValue('Error: ' + e.message);
    }
  }
  SpreadsheetApp.flush();
}
```

### Auto-archive completed rows

```javascript
function archiveCompleted() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const source = ss.getSheetByName('Active');
  const archive = ss.getSheetByName('Archive');
  const data = source.getDataRange().getValues();
  const statusCol = 4; // column E (0-indexed)
  // Bottom-up to avoid shifting row indices
  for (let i = data.length - 1; i >= 1; i--) {
    if (data[i][statusCol] === 'Complete') {
      archive.appendRow(data[i]);
      source.deleteRow(i + 1);
    }
  }
  SpreadsheetApp.flush();
}
```

## Error prevention

| Mistake | Fix |
|---|---|
| Dialog can't call function | Remove trailing `_` from function name |
| Script is slow on large data | Use `getValues()`/`setValues()` batch ops |
| Changes not visible after dialog | Add `SpreadsheetApp.flush()` before return |
| `onEdit` can't send email | Use installable trigger via `ScriptApp.newTrigger()` |
| Custom function times out | 30s limit — simplify or move to regular function |
| `setTimeout` not found | Use `Utilities.sleep(ms)` (blocking) |
| Script exceeds 6 min | Break into chunks, chain with time-driven trigger |
| Auth popup doesn't appear | User clicks Advanced > Go to (unsafe) > Allow |

## Deployment checklist

- All functions called from HTML dialogs are public (no `_` suffix)
- `SpreadsheetApp.flush()` called before returning from modifying functions
- try/catch around external API calls and MailApp
- Config constants at top
- Header comment with install instructions
- Tested on a copy of the sheet
- Considered multi-user behavior (permissions, active sheet)
- Long operations use modal progress dialogs
- No hardcoded sheet names
- Checked email quota before batch sends
