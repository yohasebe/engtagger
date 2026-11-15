# EngTagger

English part-of-speech tagger library in pure Ruby

## Description

EngTagger assigns Penn Treebank-style part-of-speech tags to English text and
extracts nouns and noun phrases from the tagged result. Since version 2.0 the
tagger is an **averaged perceptron** with a bundled model — no external
dependencies, no Python, no network: `gem install engtagger` and everything
runs anywhere Ruby (>= 3.0) runs.

The tagging and extraction methods of the 0.4 line are kept, with considerably
more accurate tags. See [Upgrading from 0.4.x](#upgrading-from-04x) for what
was removed.

## Features

* Part-of-speech tagging with a corpus-trained averaged perceptron
* PTB/Universal Dependencies-compatible word tokenizer (non-destructive:
  every token is a substring of the input)
* Noun and noun-phrase extraction from tagged text
* Classic XML-style tagged output, or standard Penn Treebank tags via
  `tagset: :ptb`
* Pure Ruby, zero runtime dependencies, 2.4 MB bundled model
* One tagger object can be shared between threads

## Accuracy

![Token accuracy of EngTagger and other POS taggers](https://raw.githubusercontent.com/yohasebe/engtagger/master/docs/accuracy.svg)

Token accuracy (%) on the test splits of two Universal Dependencies English
treebanks — [EWT](https://universaldependencies.org/treebanks/en_ewt/) (web
media: reviews, emails, forums) and
[GUM](https://universaldependencies.org/treebanks/en_gum/) (multi-genre) —
using Penn Treebank tags, gold tokenization and gold sentence boundaries
(Universal Dependencies release 2.18):

| System | Algorithm | EWT test | GUM test |
|---|---|---|---|
| EngTagger 0.4 (previous) | HMM (bigram) | 84.9 | 88.4 |
| NLTK 3 | averaged perceptron, WSJ-trained | 85.1 | 90.4 |
| **EngTagger 2.0 (this gem)** | **averaged perceptron** | **94.2** | **95.7** |
| Stanza | neural, EWT-trained | 96.2 | 97.7 |

For a fair reading of the numbers:

* **EngTagger 2.0** is measured with the model file shipped in this gem. It
  is trained on the EWT training split and on automatically tagged text from
  Wikipedia, Wikinews and Stack Exchange. No GUM annotations were used in
  training, so GUM is a held-out treebank for it.
* The figures are for text that is already split into sentences and tokens.
  Tagging raw text also depends on the tokenizer.
* **NLTK 3** uses the same algorithm family as EngTagger 2.0 but its bundled
  model is trained on Wall Street Journal text, so it runs out-of-domain on
  these test sets.
* **Stanza** is a neural pipeline (Python/PyTorch, large models) trained on
  EWT itself; it serves as the accuracy reference point, at the cost of
  dependencies and compute.

## Synopsis

```ruby
require 'engtagger'

# Create a tagger object
tgr = EngTagger.new

# Sample text
text = "Alice chased the big black cat."

# Add part-of-speech tags to text
tagged = tgr.add_tags(text)

#=> "<nnp>Alice</nnp> <vbd>chased</vbd> <det>the</det> <jj>big</jj> <jj>black</jj> <nn>cat</nn> <pp>.</pp>"

# Get a list of all nouns and noun phrases with occurrence counts
word_list = tgr.get_words(text)

#=> {"Alice" => 1, "big black cat" => 1, "black cat" => 1, "cat" => 1}

# Get a readable version of the tagged text
readable = tgr.get_readable(text)

#=> "Alice/NNP chased/VBD the/DET big/JJ black/JJ cat/NN ./PP"

# Get all nouns from a tagged output
nouns = tgr.get_nouns(tagged)

#=> {"Alice" => 1, "cat" => 1}

# Get all proper nouns
proper = tgr.get_proper_nouns(tagged)

#=> {"Alice" => 1}

# Get all past tense verbs
pt_verbs = tgr.get_past_tense_verbs(tagged)

#=> {"chased" => 1}

# Get all the adjectives
adj = tgr.get_adjectives(tagged)

#=> {"big" => 1, "black" => 1}

# Get all noun phrases of any syntactic level
# (same as word_list but takes a tagged input)
nps = tgr.get_noun_phrases(tagged)

#=> {"Alice" => 1, "big black cat" => 1, "black cat" => 1, "cat" => 1}

# Standard Penn Treebank tags, if you prefer them over the classic tagset
ptb = EngTagger.new(tagset: :ptb)
ptb.get_readable(text)

#=> "Alice/NNP chased/VBD the/DT big/JJ black/JJ cat/NN ./."

ptb.tag_pairs("Alice chased the cat.")

#=> [["Alice", :NNP], ["chased", :VBD], ["the", :DT], ["cat", :NN], [".", :"."]]
```

## Tag Set

`add_tags`, `tag_pairs` and `get_readable` use the classic EngTagger tagset by
default: a modified Penn Treebank tagset in which tags with non-letter
characters are renamed to work in XML-style markup and regular expressions
(`DET` for `DT`, `PRPS` for `PRP$`, and named punctuation classes such as `PP`
for `.`). With `EngTagger.new(tagset: :ptb)`, `tag_pairs` and `get_readable`
emit standard Penn Treebank tags instead; `add_tags` always uses the classic
tagset, whose tags are valid element names. The text inside the tags is not
escaped.

    CC      Conjunction, coordinating               and, or
    CD      Adjective, cardinal number              3, fifteen
    DET     Determiner                              this, each, some
    EX      Pronoun, existential there              there
    FW      Foreign words
    IN      Preposition / Conjunction               for, of, although, that
    JJ      Adjective                               happy, bad
    JJR     Adjective, comparative                  happier, worse
    JJS     Adjective, superlative                  happiest, worst
    LS      Symbol, list item                       A, A.
    MD      Verb, modal                             can, could, 'll
    NN      Noun                                    aircraft, data
    NNP     Noun, proper                            London, Michael
    NNPS    Noun, proper, plural                    Australians, Methodists
    NNS     Noun, plural                            women, books
    PDT     Determiner, prequalifier                quite, all, half
    POS     Possessive                              's, '
    PRP     Determiner, possessive second           mine, yours
    PRPS    Determiner, possessive                  their, your
    RB      Adverb                                  often, not, very, here
    RBR     Adverb, comparative                     faster
    RBS     Adverb, superlative                     fastest
    RP      Adverb, particle                        up, off, out
    SYM     Symbol                                  *
    TO      Preposition                             to
    UH      Interjection                            oh, yes, mmm
    VB      Verb, infinitive                        take, live
    VBD     Verb, past tense                        took, lived
    VBG     Verb, gerund or present participle      taking, living
    VBN     Verb, past/passive participle           taken, lived
    VBP     Verb, base present form                 take, live
    VBZ     Verb, present 3SG -s form               takes, lives
    WDT     Determiner, question                    which, whatever
    WP      Pronoun, question                       who, whoever
    WPS     Determiner, possessive & question       whose
    WRB     Adverb, question                        when, how, however

    PP      Punctuation, sentence ender             ., !, ?
    PPC     Punctuation, comma                      ,
    PPD     Punctuation, dollar sign                $
    PPL     Punctuation, quotation mark left        ``
    PPR     Punctuation, quotation mark right       ''
    PPS     Punctuation, colon, semicolon, elipsis  :, ..., -
    LRB     Punctuation, left bracket               (, {, [
    RRB     Punctuation, right bracket              ), }, ]

## The bundled model

The tagger ships with an averaged-perceptron model
(`lib/engtagger/model.etm.gz`, distributed under CC BY-SA 4.0) trained on:

* the [Universal Dependencies English Web Treebank](https://github.com/UniversalDependencies/UD_English-EWT),
  whose annotations are licensed CC BY-SA 4.0;
* about 32,000 sentences from Wikipedia, Wikinews and Stack Exchange, tagged
  automatically with a large language model. Every article and post is listed
  with its licence in [`sources/`](https://github.com/yohasebe/engtagger/tree/master/sources).

Unlike the 0.4.x line, no Penn Treebank-derived data is included. Provenance
and attribution details are in the NOTICE file; the packed model format is
documented in the repository (`docs/model-format.md`).

## Installation

```bash
gem install engtagger
```

Requires Ruby >= 3.0 and nothing else. Pre-release versions are installed with
`gem install engtagger --pre`.

## Upgrading from 0.4.x

The tagging and extraction methods keep their names and arguments, but the
tags themselves are produced by a different, considerably more accurate
engine, so tagged output is not byte-identical to 0.4.x. Tokenization also
follows PTB/UD conventions more closely (e.g. `don't` splits as `do|n't`).
Configuration keys of the retired HMM engine
(`:relax`, `:unknown_word_tag`, lexicon paths) are accepted and ignored with
a warning; `install`, `assign_tag`, `EngTagger.hmm`, `EngTagger.lexicon` and
the `DEFAULT_LEXPATH`, `DEFAULT_WORDPATH` and `DEFAULT_TAGPATH` constants were
removed.

If you need the old engine's exact output, pin the previous line:

```ruby
gem "engtagger", "~> 0.4"
```

## Author

Yoichiro Hasebe

EngTagger began in 2009 as a Ruby port of Lingua::EN::Tagger by Aaron Coburn.
Version 2.0 replaces its HMM tagger and probability tables with a new
averaged-perceptron tagger, tokenizer and trained model. The extraction of
nouns and noun phrases and the formatting of tagged output retain routines
ported and adapted from Lingua::EN::Tagger.

## License

This library is distributed under the GNU General Public License version 3
(GPL-3.0-only), the same license as the 0.4 line.
See the LICENSE file, and the NOTICE file for the licensing of the bundled
model and its training data.
