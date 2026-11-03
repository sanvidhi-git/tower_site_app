# Sanvidhi Site

Android app for site supervisors and engineers working on tower / EPC projects run in ERPNext with the
[`tower_site_execution`](https://github.com/sanvidhi-git/tower_site_execution) app.

## What site staff can do

* **My Sites**: only the sites where they are on the Tower Site *Project Team* (PMs see all open sites), with status, % progress, TAT milestones and BOQ progress.
* **Daily Report**: date, labour count, milestone achieved, work completed, quantity completed against the site's PO BOQ, material used, expenses (with bill photo), site photos, pending work, remarks. Each report is GPS-tagged.
* **Material Receipt**:
  * *Vendor delivery against PO*: pick the site's open PO, and pending quantities are pre-filled. Record received / damaged qty, challan, vehicle no. and serial numbers.
  * *Indus free-issue material*: tower, SMPS, batteries, solar etc. as per the Indus DC, with serial numbers. This is logged only and is not counted in our stock.
  * *Transfer from our store*: confirm material that arrived from the central store or another site.
* **Works offline**: everything is saved on the phone first and sent when the network is back (on app start, on pull-to-refresh, every 2 minutes, or with *Sync now*). Each report carries a `mobile_ref`, so a retry never creates a duplicate.

## What happens in ERPNext

Reports arrive as **Daily Site Report** / **Site Material Receipt** drafts (*Pending approval*). When the Project Manager submits them:

| Report | Posting |
|---|---|
| Daily Site Report | Material Issue from the site warehouse (falls back to the central store), expense Journal Entry to the site project, BOQ progress and milestone update |
| Vendor delivery | Purchase Receipt into the site warehouse against the PO (draft for stores/accounts, or auto-submit) |
| Store transfer | Stock Entry (Material Transfer) from store to site warehouse |
| Indus material | Logged against the site only |

## Build

GitHub Actions builds the APK on every push to `main` (`.github/workflows/build-apk.yml`):
* each build is published as a GitHub Release, and the latest is kept as `Sanvidhi-Site-latest.apk` on the `builds` branch
* to sign with a permanent key, add the repo secrets `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` and `KEY_PASSWORD` (the same ones as Sanvidhi ESS work)
* to build in a fixed server address, set the repo variable `SITE_SERVER` or use *Run workflow → server_url*. When it is blank, the server address is asked for at login.

Local build:
```bash
bash tool/setup_android.sh com.sanvidhi
flutter build apk --release
```

## Server requirements

ERPNext v16 with `tower_site_execution` installed. Users need the **Site Supervisor** role, an **Employee** record linked to their user, and a place in the Tower Site *Project Team*.
