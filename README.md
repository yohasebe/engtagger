# EngTagger

English Part-of-Speech Tagger Library; a Ruby port of Lingua::EN::Tagger

## Description

A Ruby port of Perl Lingua::EN::Tagger, a probability based, corpus-trained
tagger that assigns POS tags to English text based on a lookup dictionary and
a set of probability values. The tagger assigns appropriate tags based on
conditional probabilities--it examines the preceding tag to determine the
appropriate tag for the current word. Unknown words are classified according to
word morphology or can be set to be treated as nouns or other parts of speech.
The tagger also extracts as many nouns and noun phrases as it can, using a set
of regular expressions.

## Features

* Assigns POS tags to English text
* Extract noun phrases from tagged text
* etc.

## Synopsis

```ruby
require 'engtagger'

# Create a parser object
tgr = EngTagger.new

# Sample text
text = "Alice chased the big fat cat."

# Add part-of-speech tags to text
tagged = tgr.add_tags(text)

#=> "<nnp>Alice</nnp> <vbd>chased</vbd> <det>the</det> <jj>big</jj> <jj>fat</jj><nn>cat</nn> <pp>.</pp>"

# Get a list of all nouns and noun phrases with occurrence counts
word_list = tgr.get_words(text)

#=> {"Alice"=>1, "cat"=>1, "fat cat"=>1, "big fat cat"=>1}

# Get a readable version of the tagged text
readable = tgr.get_readable(text)

#=> "Alice/NNP chased/VBD the/DET big/JJ fat/JJ cat/NN ./PP"

# Get all nouns from a tagged output
nouns = tgr.get_nouns(tagged)

#=> {"cat"=>1, "Alice"=>1}

# Get all proper nouns
proper = tgr.get_proper_nouns(tagged)

#=> {"Alice"=>1}

# Get all past tense verbs
pt_verbs = tgr.get_past_tense_verbs(tagged)

#=> {"chased"=>1}

# Get all the adjectives
adj = tgr.get_adjectives(tagged)

#=> {"big"=>1, "fat"=>1}

# Get all noun phrases of any syntactic level
# (same as word_list but take a tagged input)
nps = tgr.get_noun_phrases(tagged)

#=> {"Alice"=>1, "cat"=>1, "fat cat"=>1, "big fat cat"=>1}
```

## Tag Set

The set of POS tags used here is a modified version of the Penn Treebank tagset. Tags with non-letter characters have been redefined to work better in our data structures. Also, the "Determiner" tag (DET) has been changed from 'DT', in order to avoid confusion with the HTML tag, `<DT>`.

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
    VBG     Verb, gerund                            taking, living
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

## Installation

**Recommended Approach (without sudo):**

It is recommended to install the `engtagger` gem within your user environment without root privileges. This ensures proper file permissions and avoids potential issues. You can achieve this by using Ruby version managers like `rbenv` or `rvm` to manage your Ruby versions and gemsets.

To install without `sudo`, simply run:

```bash
gem install engtagger
```

**Alternative Approach (with sudo):**

If you must use `sudo` for installation, you'll need to adjust file permissions afterward to ensure accessibility.

1. Install the gem with `sudo`:

```bash
sudo gem install engtagger
```

2. Grant necessary permissions to your user:

```bash
sudo chown -R $(whoami) /Library/Ruby/Gems/2.6.0/gems/engtagger-0.4.1
```

**Note:** The path above assumes you are using Ruby version 2.6.0.  If you are using a different version, you will need to modify the path accordingly.  You can find your Ruby version by running `ruby -v`. 

## Troubleshooting

**Permission Issues:**

If you encounter "cannot load such file" errors after installation, it might be due to incorrect file permissions. Ensure you've followed the instructions for adjusting permissions if you used `sudo` during installation.

## Author

Yoichiro Hasebe (yohasebe [at] gmail.com)

## Contributors

Many thanks to the collaborators listed in the right column of this GitHub page.

## Acknowledgement

This Ruby library is a direct port of Lingua::EN::Tagger available at CPAN.
The credit for the crucial part of its algorithm/design therefore goes to
Aaron Coburn, the author of the original Perl version.

## License

This library is distributed under the GPL.  Please see the LICENSE file.
