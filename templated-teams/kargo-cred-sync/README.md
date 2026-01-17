# WTF
This app exists because I can find no way to make global Kargo creds work.

https://akuityio.slack.com/archives/C03UTU5H4H0/p1768664248018279

## What it does

Pulls secrets on cluster created by ESO, and applies htem to the newly created kargo project.

This installs many jobs in the same shared namespace `kargo-sync-jobs` where ESO has already staged the required secrets.