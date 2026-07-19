# Changelog

## 0.4.3

- Fix gem packaging that produced files with owner-only (0600) permissions,
  making the gem unreadable after a `sudo gem install` (#20). File permissions
  are now normalized before packaging.
- Restore lost debug output in `valid_text` (a remnant of the Perl port left
  the message string in void context).
- Clarify that the VBG tag covers both gerunds and present participles, as in
  the Penn Treebank tagset (#19).
- Minor RuboCop cleanups.

## 0.4.2 and earlier

See the [commit history](https://github.com/yohasebe/engtagger/commits/master).
