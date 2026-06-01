# Account checklist (manual)

This checklist is intentionally **printed for a human**. The skill
does not automate account provisioning — credentials and invitation
links go through IT / the manager, not through Claude.

Tick items in your forked copy of this file.

## Identity (gate everything else)

- [ ] **Work email** activated, MFA enabled
  - URL: depends on the org (Google Workspace, Microsoft 365, …)
  - Test: receive a real email + log into the admin app
- [ ] **Password manager** vault joined, master password stored
      in a safe place (hardware token, paper in a safe — *not* in
      another browser)

## Communication

- [ ] **Slack** workspace joined, profile photo + role set
- [ ] **Calendar** shared with the team
- [ ] **Video conferencing** account active (Zoom / Meet / Teams)

## Code / engineering

- [ ] **GitHub** account joined the org
  - URL: https://github.com/join
  - Invitation: ask manager
  - MFA: required
  - SSH key uploaded
  - Commit signing configured (optional but recommended)
- [ ] **CI / cloud console** SSO works (AWS / GCP / Azure / …)
- [ ] **Internal CLI** (if any) authenticated
- [ ] **Container registry** authenticated (if applicable)

## SaaS by role

### Designers
- [ ] Figma team
- [ ] Adobe Creative Cloud
- [ ] Zeplin / inVision / Loom

### Sales / GTM
- [ ] CRM (HubSpot / Salesforce / Pipedrive)
- [ ] LinkedIn Sales Navigator
- [ ] Calendar booking (Calendly / Cal.com)
- [ ] Notion / Confluence

### Product / PM
- [ ] Linear / Jira
- [ ] Notion / Confluence
- [ ] Analytics (Mixpanel / Amplitude / Posthog)

### Ops / IT
- [ ] MDM enrollment confirmed
- [ ] Status page admin
- [ ] On-call rotation tool (PagerDuty / Incident.io)

## VPN / network

- [ ] VPN client installed and authenticated (if required)
- [ ] Wi-Fi profiles for office locations installed
- [ ] Internal DNS reachable

## Off-boarding hooks (do this on day one, not on day 90)

- [ ] All work-related accounts listed somewhere IT can revoke
- [ ] No personal-email recovery on company accounts
- [ ] Browser sync uses *work* profile only

---

Once everything is ticked, commit this file to your team's onboarding
repo so the next new hire starts from a real checklist, not a wish
list.
