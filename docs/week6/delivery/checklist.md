# Delivery checklist

- [x] Feature 2 integrated with the LineSight quality workflow: team workspaces, task tracking, image evidence, inspection, and exception handling
- [x] Team registration/sign-in, workspace membership, task state, and exception closure exercised on Android
- [x] Image upload and original/edge reference preview exercised
- [x] Legacy inspection-record import preview checked
- [x] Bright visual style retained across the reviewed journey
- [x] Flutter analysis and automated test results recorded
- [x] Android self-test completed before external user testing
- [x] Refreshed screenshots indexed for the report
- [x] Final debug APK copied and indexed with SHA-256
- [x] Chinese role labels, inspection time, and photo action reviewed on the Android journey
- [x] Django admin route added for collaboration data management and locally checked
- [x] Team access and production security handoff documented
- [x] Fail2ban SSH jail installed on the supplied Linux host
- [x] HTTPS API and remote Django Admin deployed and reachable
- [x] Android app connected to the live HTTPS service and created a workspace successfully
- [x] Pre-created a ready-to-use demonstration workspace with owner, operator, inspector, and read-only accounts
- [x] Seeded task states, an exception, a passing inspection, and photo/edge-reference evidence for direct demonstration
- [x] Host firewall limits public ingress to SSH, HTTP, and HTTPS
- [ ] Full English journey reviewed
- [ ] Network interruption and upload retry verified
- [ ] Backup/restore drill and rollback rehearsal verified
- [ ] External user testing and iteration
- [x] Production deployment

SSH source-IP allowlisting, database backups/restore drills, rollback rehearsal, network retry verification, and external user testing remain follow-up work.

The current deliverable is an internally tested Android build connected to the deployed HTTPS collaboration service. External user testing has not started.
