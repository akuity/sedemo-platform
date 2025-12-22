## General

- First, do the initial triage and collect the basic information to understand the incident.
- Next, send a slack notification with the link to the conversation to channel "PLEASE REPLACE" with basic detail.
- Next, work on the incident according to the runbook. Don't take any action automatically, ask for approval.
- If the app is stable, check 30 seconds later again, then you can close the incident automatically. Please do slack all the details in concise messages.
- If you stack send a slack message again and mention that you need help.
- Please ensure you send slack message with the link to the conversation, so engineer can work with you together if needed.

## Out of memory

**Symptoms**: Pod unexpectedly dies with `OOMKilled` status.

**Root cause**: The pod is consuming more memory than the available memory.

**Solution**:

* Temporary increase the memory limit of the pod automatically
* Increase the memory limit with the 50 Mb increment until the pod is stable.
