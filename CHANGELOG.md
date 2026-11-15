# Changelog

## 2.0.0 (unreleased)

A rewrite of the tagging engine. Tagging and tokenization output differ from 0.4.x; pin `gem "engtagger", "~> 0.4"` to keep the old engine.

- Replace the HMM tagger with an averaged perceptron and a bundled model trained on UD English-EWT and automatically tagged Wikipedia, Wikinews and Stack Exchange text (see NOTICE).
- Add a PTB/UD-compatible tokenizer whose tokens are substrings of the input.
- Add the `tagset: :ptb` option, which makes `tag_pairs` and `get_readable` emit standard Penn Treebank tags.
- Remove the HMM probability tables derived from the Penn Treebank, `install`, `assign_tag`, `EngTagger.hmm`, `EngTagger.lexicon` and the `DEFAULT_*PATH` constants.
- Ignore the configuration keys of the HMM engine (`:relax`, `:unknown_word_tag`, lexicon paths) with a warning.
- Remove the `sin_lru_redux` dependency; the gem has no runtime dependencies.
- Require Ruby >= 3.0.
- Ship only `lib/` and the user-facing documents in the gem package.

## 0.4.6 (2026-11-14)

- Fix `get_noun_phrases`, `get_words` and `add_tags` taking time quadratic in the input length; output is unchanged. Upgrade if you tag text from untrusted sources.

## 0.4.5 (2026-08-14)

- Correct the license to GPL-3.0-only, the license of Lingua::EN::Tagger, which this library is a port of; the LICENSE file is now the GPLv3 text.

## 0.4.4 (2026-08-14)

- Fix `get_sentences` so that punctuation is reattached to the neighboring word.
- Fix the `WORD` constant, which matched only `<w>` tags.
- Fix the tag regexes of `EngTagger.get_ext` so that they consume trailing whitespace, including newlines.
- Fix `assign_tag` raising `NoMethodError` for words absent from the lexicon.
- Fix the lexicon files being read and written in text mode, which corrupted them on Windows.
- Fix the test suite rewriting the bundled lexicon files on every run.
- Define `EngTagger::VERSION` when the library is required.
- Remove a stray MIT license text from the LICENSE file and declare the license in the gemspec.
- Remove the shebang and executable bit from `lib/engtagger.rb`.

## 0.4.3

- Fix gem files being packaged with owner-only permissions, which made the gem unreadable after `sudo gem install` (#20).
- Fix the debug message of `valid_text` not being printed.
- Document that the VBG tag covers both gerunds and present participles (#19).

## 0.4.2 and earlier

See the [commit history](https://github.com/yohasebe/engtagger/commits/master).
