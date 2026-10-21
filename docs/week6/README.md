# Week 6 implementation evidence

This folder records the integrated LineSight team production and quality workflow delivered in Week 6. The Flutter app, Django collaboration API, deployment configuration, and self-test cases live in the project source tree.

- [Feature design, user flow, and architecture](design/feature-design-v3-customer-flow.md)
- [Self-test matrix](testing/test-matrix.md)
- [Delivery checklist](delivery/checklist.md)
- [Android build metadata](delivery/build-artifact.md)
- [Screenshot index](screenshots/README.md)
- [Portable web experience, navigation diagrams and browser evidence](web-demo/README.md)

The screenshots show the bright Chinese-language app, team sign-in, pre-seeded demonstration workspace and task states, image review, and completed inspection flow. They were captured with empty credential fields where sign-in is shown. APK binaries, private keys, and account/password handoff details are intentionally kept out of this repository.

## Deployment and verification status

The collaboration API and Django Admin were deployed behind HTTPS. Gunicorn is bound to loopback; the public firewall permits SSH, HTTP, and HTTPS, and Fail2ban protects SSH. The installed Android build signed into the prepared demonstration workspace over HTTPS. Internal Flutter analysis and automated test results are recorded in the checklist and build metadata.

Follow-up work recorded at delivery includes backup/restore and rollback drills, SSH source-IP allowlisting, upload retry verification, full English journey review, and external user testing.
