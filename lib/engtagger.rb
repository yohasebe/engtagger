# frozen_string_literal: true

require_relative "engtagger/version"
require_relative "engtagger/porter"
require_relative "engtagger/perceptron"

# English part-of-speech tagger.
#
# Tagging runs an averaged perceptron over a bundled model (see NOTICE for its
# training data). `add_tags` produces XML-style output in the classic tagset,
# and the extraction methods (`get_nouns`, `get_noun_phrases`, ...) read that
# output. Pass `tagset: :ptb` to get standard Penn Treebank tags from
# `tag_pairs` and `get_readable`.
class EngTagger
  #################
  # Class methods #
  #################

  # Return a regexp from a string argument that matches an XML-style pos tag
  def self.get_ext(tag = nil)
    return nil unless tag

    Regexp.new("<#{tag}>[^<]+</#{tag}>\\s*")
  end

  # Regexps to match XML-style part-of-speech tags
  NUM   = get_ext("cd")
  GER   = get_ext("vbg")
  ADJ   = get_ext("jj[rs]*")
  NN    = get_ext("nn[sp]*")
  NNP   = get_ext("nnp")
  PREP  = get_ext("in")
  DET   = get_ext("det")
  PAREN = get_ext("[lr]rb")
  QUOT  = get_ext("ppr")
  SEN   = get_ext("pp")
  WORD  = get_ext("\\w+")
  VB    = get_ext("vb")
  VBG   = get_ext("vbg")
  VBD   = get_ext("vbd")
  PART  = get_ext("vbn")
  VBP   = get_ext("vbp")
  VBZ   = get_ext("vbz")
  JJ    = get_ext("jj")
  JJR   = get_ext("jjr")
  JJS   = get_ext("jjs")
  RB    = get_ext("rb")
  RBR   = get_ext("rbr")
  RBS   = get_ext("rbs")
  RP    = get_ext("rp")
  WRB   = get_ext("wrb")
  WDT   = get_ext("wdt")
  WP    = get_ext("wp")
  WPS   = get_ext("wps")
  CC    = get_ext("cc")
  IN    = get_ext("in")

  # Convert a Treebank-style, abbreviated tag into verbose definitions
  #
  # @param tag [#to_s] the tag in question
  # @return [String] the definition, if available
  #
  def self.explain_tag(tag)
    tag = tag.to_s.downcase
    TAGS[tag] || tag
  end

  # The following is to make a hash to convert a pos tag to its definition
  # used by the explain_tag method
  tags = [
    "CC",   "Conjunction, coordinating",
    "CD",   "Cardinal number",
    "DET",  "Determiner",
    "EX",   "Pronoun, existential there",
    "FW",   "Foreign words",
    "IN",   "Preposition / Subordinating conjunction",
    "JJ",   "Adjective",
    "JJR",  "Adjective, comparative",
    "JJS",  "Adjective, superlative",
    "LS",   "List item marker",
    "MD",   "Verb, modal",
    "NN",   "Noun",
    "NNP",  "Noun, proper",
    "NNPS", "Noun, proper, plural",
    "NNS",  "Noun, plural",
    "PDT",  "Predeterminer",
    "POS",  "Possessive ending",
    "PRP",  "Pronoun, personal",
    "PRPS", "Determiner, possessive",
    "RB",   "Adverb",
    "RBR",  "Adverb, comparative",
    "RBS",  "Adverb, superlative",
    "RP",   "Particle",
    "SYM",  "Symbol",
    "TO",   "Infinitive marker",
    "UH",   "Interjection",
    "VB",   "Verb, base form",
    "VBD",  "Verb, past tense",
    "VBG",  "Verb, gerund or present participle",
    "VBN",  "Verb, past participle",
    "VBP",  "Verb, present, non-3rd-person singular",
    "VBZ",  "Verb, present, 3rd-person singular",
    "WDT",  "Wh-determiner",
    "WP",   "Wh-pronoun",
    "WPS",  "Possessive wh-pronoun",
    "WRB",  "Wh-adverb",
    "PP",   "Punctuation, sentence ender",
    "PPC",  "Punctuation, comma",
    "PPD",  "Punctuation, dollar sign",
    "PPL",  "Punctuation, quotation mark left",
    "PPR",  "Punctuation, quotation mark right",
    "PPS",  "Punctuation, colon, semicolon, ellipsis",
    "LRB",  "Punctuation, left bracket",
    "RRB",  "Punctuation, right bracket"
  ]
  tags = tags.collect { |t| t.downcase.gsub(/[.,'\-\s]+/, "_") }
  tags = tags.collect { |t| t.gsub("&", "and").gsub("/", "or") }
  TAGS = Hash[*tags]

  # Configuration keys of the retired HMM engine. They are accepted (so 0.4-era
  # initializers keep working) but have nothing to configure anymore; passing
  # one triggers a single warning rather than an error.
  RETIRED_CONF_KEYS = %i[
    relax unknown_word_tag tag_lex word_lex unknown_lex word_path tag_path
    current_tag
  ].freeze

  # Hash storing config values:
  #
  # * :stem
  #    => (Boolean) Stem single words using Porter module
  # * :weight_noun_phrases
  #    => (Boolean) When returning occurrence counts for a noun phrase, multiply
  #        the value by the number of words in the NP.
  # * :longest_noun_phrase
  #    => (Integer) Will ignore noun phrases longer than this threshold. This
  #        affects only the get_words() and get_nouns() methods.
  # * :tagset
  #    => (Symbol) :legacy (default) emits the classic XML-safe lowercase tags;
  #        :ptb makes tag_pairs and get_readable emit standard Penn Treebank
  #        tags (DT, PRP$, ".", ...). add_tags always uses the classic tagset,
  #        which is what keeps its output usable as XML and regex-friendly.
  # * :model
  #    => (String) Path to a packed model file; defaults to the bundled model
  # * :debug
  #    => (Boolean) Print debug messages
  attr_accessor :conf

  ###############
  # Constructor #
  ###############

  # Take a hash of parameters that override default values.
  # See above for details.
  def initialize(params = {})
    @conf = {}
    @conf[:stem] = false
    @conf[:weight_noun_phrases] = false
    @conf[:longest_noun_phrase] = 5
    @conf[:tagset] = :legacy
    @conf[:model] = Perceptron::DEFAULT_MODEL
    @conf[:debug] = false
    @conf.merge!(params) if params
    warn_retired_keys(params)
    @tagger = self.class.perceptron_for(@conf[:model])
    @@mnp = get_max_noun_regex
  end

  # One loaded model shared across instances.
  def self.perceptron_for(model_path)
    @@perceptrons ||= {}
    @@perceptrons[model_path] ||= Perceptron.new(model: model_path)
  end

  ##################
  # Public methods #
  ##################

  # Return an array of pairs of the form `["word", :tag]`.
  #
  # @param text [String] the input text
  # @return [Array] the tagged words
  #
  def tag_pairs(text)
    return [] unless valid_text(text)

    @tagger.tag(text).map do |word, tag|
      tag = @tagger.legacy_tag(tag) unless @conf[:tagset] == :ptb
      [word, tag.to_sym]
    end
  end

  # Examine the string provided and return it fully tagged in XML style.
  #
  # @param text [String] the input text
  # @param verbose [false, true] whether to use verbose tags
  # @return [String] the marked-up string
  #
  # Uses the classic tagset regardless of :tagset, so every tag is a valid
  # element name and the output works with the extraction methods below. The
  # text inside the tags is not escaped.
  def add_tags(text, verbose = false)
    return nil unless valid_text(text)

    @tagger.tag(text).map do |word, ptb|
      tag = @tagger.legacy_tag(ptb)
      tag = EngTagger.explain_tag(tag) if verbose
      "<#{tag}>#{word}</#{tag}>"
    end.join(" ")
  end

  # Tag one word from the tag before it, in the classic tagset. The words
  # around it are not seen, so `tag_pairs` and `add_tags` are more accurate.
  #
  # @param prev_tag [String, nil] the classic tag of the preceding word; "pp"
  #   or nil at the start of a sentence
  # @param word [String] a single token
  # @return [String] the classic tag
  #
  def assign_tag(prev_tag, word)
    prev = prev_tag.to_s
    prev = nil if prev.empty? || prev == "pp"
    @tagger.legacy_tag(@tagger.tag_word(word.encode(Encoding::UTF_8), prev && @tagger.ptb_tag(prev)))
  end

  # Given a text string, return as many nouns and noun phrases as possible.
  # Applies add_tags and involves three stages:
  #
  # * Tag the text
  # * Extract all the maximal noun phrases
  # * Recursively extract all noun phrases from the MNPs
  #
  def get_words(text)
    return false unless valid_text(text)

    tagged = add_tags(text)
    if @conf[:longest_noun_phrase] <= 1
      get_nouns(tagged)
    else
      get_noun_phrases(tagged)
    end
  end

  # Return an easy-on-the-eyes tagged version of a text string.
  # Applies add_tags and reformats to be easier to read.
  def get_readable(text, verbose = false)
    return nil unless valid_text(text)

    if @conf[:tagset] == :ptb && !verbose
      @tagger.get_readable(text)
    else
      tagged = add_tags(text, verbose)
      tagged.gsub(%r{<\w+>([^<]+|[<\w>]+)</(\w+)>}o) do
        "#{$1}/#{$2.upcase}"
      end
    end
  end

  # Return an array of sentences (without POS tags) from a text.
  def get_sentences(text)
    return nil unless valid_text(text)

    tagged = add_tags(text)
    sentences = []
    tagged.split(%r{</pp>}).each do |line|
      sentences << strip_tags(line)
    end
    sentences.map do |sentence|
      # Reattach punctuation to the neighboring word: opening quotes/brackets
      # and currency signs join the following word, everything else (commas,
      # closing marks, possessives) joins the preceding word.
      sentence.gsub(/ ('s?) /) { "#{$1} " }
              .gsub(/ ([`(\[{$]+) /) { " #{$1}" }
              .gsub(/ ([^\w\s`(\[{$]+) /) { "#{$1} " }
              .gsub(/ ([^\w\s]+)\z/) { $1 }
              .gsub(/\A([`(\[{$]+) /) { $1 }
    end
  end

  # Given a POS-tagged text, this method returns a hash of all proper nouns
  # and their occurrence frequencies. The method is greedy and will
  # return multi-word phrases, if possible, so it would find ``Linguistic
  # Data Consortium'' as a single unit, rather than as three individual
  # proper nouns. This method does not stem the found words.
  def get_proper_nouns(tagged)
    return nil unless valid_text(tagged)

    tags = [NNP]
    nnp = build_matches_hash(build_trimmed(tagged, tags))
    # Now for some fancy resolution stuff...
    nnp.each_key do |key|
      words = key.split(/\s/)
      # Let's say this is an organization's name --
      # (and it's got at least three words)
      # is there a corresponding acronym in this hash?
      next if words.length <= 2

      # Make a (naive) acronym out of this name
      acronym = words.map do |word|
        /\A([a-z])[a-z]*\z/ =~ word
        $1
      end.join " "
      # If that acronym has been seen,
      # remove it and add the values to
      # the full name
      if nnp[acronym]
        nnp[key] += nnp[acronym]
        nnp.delete(acronym)
      end
    end
    nnp
  end

  # Given a POS-tagged text, this method returns all nouns and their
  # occurrence frequencies.
  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_nouns(tagged)
    return nil unless valid_text(tagged)

    tags = [NN]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  # Returns all types of verbs and does not discriminate between the
  # various kinds. Combines all other verb methods listed in this
  # class.
  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_verbs(tagged)
    return nil unless valid_text(tagged)

    tags = [VB, VBD, VBG, PART, VBP, VBZ]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #

  def get_infinitive_verbs(tagged)
    return nil unless valid_text(tagged)

    tags = [VB]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_past_tense_verbs(tagged)
    return nil unless valid_text(tagged)

    tags = [VBD]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_gerund_verbs(tagged)
    return nil unless valid_text(tagged)

    tags = [VBG]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_passive_verbs(tagged)
    return nil unless valid_text(tagged)

    tags = [PART]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_base_present_verbs(tagged)
    return nil unless valid_text(tagged)

    tags = [VBP]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_present_verbs(tagged)
    return nil unless valid_text(tagged)

    tags = [VBZ]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_adjectives(tagged)
    return nil unless valid_text(tagged)

    tags = [JJ]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_comparative_adjectives(tagged)
    return nil unless valid_text(tagged)

    tags = [JJR]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_superlative_adjectives(tagged)
    return nil unless valid_text(tagged)

    tags = [JJS]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_adverbs(tagged)
    return nil unless valid_text(tagged)

    tags = [RB, RBR, RBS, RP]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_interrogatives(tagged)
    return nil unless valid_text(tagged)

    tags = [WRB, WDT, WP, WPS]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  # To be consistent with documentation's naming of 'interrogative'
  # parts of speech as 'question'
  alias get_question_parts get_interrogatives

  # Returns all types of conjunctions and does not discriminate
  # between the various kinds. E.g. coordinating, subordinating,
  # correlative...
  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_conjunctions(tagged)
    return nil unless valid_text(tagged)

    tags = [CC, IN]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  # Given a POS-tagged text, this method returns only the maximal noun phrases.
  # May be called directly, but is also used by `get_noun_phrases`.
  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_max_noun_phrases(tagged)
    return nil unless valid_text(tagged)

    tags = [@@mnp]
    mn_phrases = build_trimmed(tagged, tags)
    ret = Hash.new(0)
    mn_phrases.each do |p|
      p = stem(p) unless p =~ /\s/ # stem single words
      ret[p] += 1 unless p =~ /\A\s*\z/
    end
    ret
  end

  # Similar to get_words, but requires a POS-tagged text as an argument.
  #
  # @param tagged [String] the tagged text
  # @return [Hash] the hash of matches
  #
  def get_noun_phrases(tagged)
    return nil unless valid_text(tagged)

    found = Hash.new(0)
    phrase_ext = /(?:#{PREP}|#{DET}|#{NUM})+/xo
    noun = /#{NN}/o
    longest = @conf[:longest_noun_phrase]
    scanned = tagged.scan(@@mnp)
    # Find MNPs in the text, one sentence at a time
    # Record and split if the phrase is extended by a (?:PREP|DET|NUM)
    mn_phrases = []
    scanned.each do |m|
      found[m] += 1 if phrase_ext =~ m
      mn_phrases.concat(m.split(phrase_ext))
    end
    mn_phrases.each do |mnp|
      # Split the phrase into an array of words, and create a loop for each word,
      # shortening the phrase by removing the word in the first position.
      # Record the phrase and any single nouns that are found
      words = mnp.split
      words.each_index do |i|
        # Longer phrases would be dropped by the length limit below, so they
        # are not built in the first place.
        length = words.length - i
        found[words[i..].join(" ")] += 1 if length > 1 && length <= longest
        found[words[i]] += 1 if noun.match?(words[i])
      end
    end
    ret = Hash.new(0)
    found.each_key do |f|
      k = strip_tags(f)
      v = found[f]
      # We weight by the word count to favor long noun phrases
      space_count = k.scan(/\s+/)
      word_count = space_count.length + 1
      # Throttle MNPs if necessary
      next if word_count > @conf[:longest_noun_phrase]

      k = stem(k) unless word_count > 1 # stem single words
      multiplier = 1
      multiplier = word_count if @conf[:weight_noun_phrases]
      ret[k] += multiplier * v
    end
    ret
  end

  # Return the word stem as given by Stemmable module. This can be
  # turned off with the class parameter @conf[:stem] => false.
  def stem(word)
    @conf[:stem] ? word.stem : word
  end

  ###################
  # Private methods #
  ###################

  private

  def warn_retired_keys(params)
    return unless params

    retired = params.keys.map(&:to_sym) & RETIRED_CONF_KEYS
    return if retired.empty?

    @@warned_retired ||= {}
    retired.reject { |k| @@warned_retired[k] }.each do |key|
      @@warned_retired[key] = true
      warn "EngTagger: config key :#{key} belonged to the retired HMM engine " \
           "and is ignored as of 2.0 (pin \"~> 0.4\" if you need it)"
    end
  end

  def build_trimmed(tagged, tags)
    tags.map { |tag| tagged.scan(tag) }.flatten.map do |n|
      strip_tags(n)
    end
  end

  def build_matches_hash(trimmed)
    ret = Hash.new(0)
    trimmed.each do |n|
      n = stem(n)
      next unless n.length < 100 # sanity check on word length

      ret[n] += 1 unless n =~ /\A\s*\z/
    end
    ret
  end

  # Check whether the text is a valid string
  def valid_text(text)
    if !text
      # there's nothing to parse
      puts "method call on uninitialized variable" if @conf[:debug]
      false
    elsif /\A\s*\z/ =~ text
      # text is an empty string, nothing to parse
      false
    else
      # $text is valid
      true
    end
  end

  # Return a text string with the part-of-speech tags removed
  def strip_tags(tagged, downcase = false)
    return nil unless valid_text(tagged)

    text = tagged.gsub(/<[^>]+>/m, "")
    text = text.gsub(/\s+/m, " ")
    text = text.gsub(/\A\s*/, "")
    text = text.gsub(/\s*\z/, "")
    downcase ? text.downcase : text
  end

  # This returns a compiled regexp for extracting maximal noun phrases
  # from a POS-tagged text.
  def get_max_noun_regex
    /
    # optional number, gerund - adjective -participle
    (?:#{NUM})?(?:#{GER}|#{ADJ}|#{PART})*
      # Followed by one or more nouns
      (?:#{NN})+
      (?:
       # Optional preposition, determinant, cardinal
       (?:#{PREP})*(?:#{DET})?(?:#{NUM})?
       # Optional gerund-adjective -participle
       (?:#{GER}|#{ADJ}|#{PART})*
       # one or more nouns
       (?:#{NN})+
      )*
      /xo
  end
end
