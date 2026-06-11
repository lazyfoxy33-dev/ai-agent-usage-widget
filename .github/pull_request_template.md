## Summary

- Describe the change.

## Verification

- [ ] `cd usage-widget && python3 -m unittest discover -v`
- [ ] UI changes were checked in Übersicht
- [ ] The diff contains no tokens, session data, caches, or personal paths

## Provider Safety

- [ ] Credentials remain read-only
- [ ] No OAuth refresh or token persistence was added
- [ ] A provider failure does not break the other provider
