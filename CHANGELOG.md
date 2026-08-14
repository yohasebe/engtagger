# Changelog

## 0.4.5 (2026-08-14)

License metadata correction; no code changes. This library is a port (2009) of
Perl Lingua::EN::Tagger, which has been licensed GPL-3.0-only since its
version 0.14 (2008). As a derivative work EngTagger is therefore GPL-3.0-only:
the bundled LICENSE is now the GPLv3 text and the gemspec declares
`GPL-3.0-only`. Earlier releases carried a GPLv2 license text, and 0.4.4
declared `GPL-2.0-or-later`; both were inaccurate.

## 0.4.4 (2026-08-14)

This is the final planned release of the 0.4 line. Version 2.0 replaces the
HMM engine with an averaged perceptron and does not ship the Penn
Treebank-derived probability tables, so its tagging output differs. Pin
`gem "engtagger", "~> 0.4"` to stay on this line; it will receive critical
fixes only.

- Fix the test suite silently rewriting the bundled lexicon files
  (`lib/engtagger/*.hash`) on every run: a path-join bug in the test setup made
  the existence check always fail, so `install` ran before each test. This was
  also the enabler of the 0600-permission contamination behind #20. Tests are
  ~6x faster as a result.
- `get_sentences` now applies its intended punctuation cleanup. Four of its
  five reattachment rules had discarded their results since the original port
  (only the leading-backquote rule was ever applied), and their regexes were
  corrupted by string escaping (`\W` matched a literal "W"). Sentences returned
  by this method now read naturally (`"Lisa Raines, a lawyer,"`,`"$3"`).
  Known limitation carried over from the tokenizer: contractions other than
  possessives remain space-separated (`"I 'm"`, `"is n't"`).
- Fix the public `WORD` constant, whose regex was corrupted by the same
  escaping problem and matched only `<w>`-style tags.
- Tag regexes produced by `EngTagger.get_ext` (NUM, NN, SEN, etc.) now end with
  a real `\s*`, so they consume trailing whitespace including newlines instead
  of spaces only.
- `assign_tag` no longer raises `NoMethodError` for words absent from the
  lexicon; it returns `""` so callers fall back to `"nn"` as designed.
- `EngTagger::VERSION` is now defined at runtime (`engtagger/version` was not
  required by the library itself).
- Read and write the Marshal lexicon files in binary mode to avoid corruption
  on Windows.
- Remove the stray shebang and executable bit from `lib/engtagger.rb`, and the
  obsolete `require "rubygems"`.
- Clarify licensing: the LICENSE file had a stray MIT license appended after
  the GPLv2 text. The library is licensed as GPL-2.0-or-later; the MIT tail has
  been removed and the gemspec now declares the SPDX identifier.
- Gemspec: use the https homepage URL, add `metadata` URIs, and drop the
  obsolete `test_files`.
- Fix a dead test (`text_get_ext` typo) that had never run and would have
  failed if enabled.
- Note in the README that 0.4.x carries Penn Treebank-derived probability
  tables; 2.x is trained on openly licensed data instead.

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
