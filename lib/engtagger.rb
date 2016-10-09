#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

$LOAD_PATH << File.join(File.dirname(__FILE__), 'engtagger')
require 'rubygems'
require 'kconv'
require 'porter'

# use hpricot for extracting English text from docs with XML like tags
begin
  require 'hpricot'
rescue LoadError
  $no_hpricot = true
end

# File paths
$lexpath   = File.join(File.dirname(__FILE__), 'engtagger')
$word_path = File.join($lexpath, "pos_words.hash")
$tag_path  = File.join($lexpath, "pos_tags.hash")

# for memoization (code snipet from http://eigenclass.org/hiki/bounded-space-memoization)
class Module
  def memoize(method)
    # alias_method is faster than define_method + old.bind(self).call
    alias_method "__memoized__#{method}", method
    module_eval <<-EOF
      def #{method}(*a, &b)
        # assumes the block won't change the result if the args are the same
        (@__memoized_#{method}_cache ||= {})[a] ||= __memoized__#{method}(*a, &b)
      end
    EOF
  end
end

# English part-of-speech tagger class
class EngTagger

  #################
  # Class methods #
  #################

  # Return a class variable that holds probability data
  def self.hmm
    return @@hmm
  end

  # Return a class variable that holds lexical data
  def self.lexicon
    return @@lexicon
  end

  # Return a regexp from a string argument that matches an XML-style pos tag
  def self.get_ext(tag = nil)
    return nil unless tag
    return Regexp.new("<#{tag}>[^<]+</#{tag}>\s*")
  end

  # Regexps to match XML-style part-of-speech tags
  NUM   = get_ext('cd')
  GER   = get_ext('vbg')
  ADJ   = get_ext('jj[rs]*')
  NN    = get_ext('nn[sp]*')
  NNP   = get_ext('nnp')
  PREP  = get_ext('in')
  DET   = get_ext('det')
  PAREN = get_ext('[lr]rb')
  QUOT  = get_ext('ppr')
  SEN   = get_ext('pp')
  WORD  = get_ext('\w+')
  VB    = get_ext('vb')
  VBG   = get_ext('vbg')
  VBD   = get_ext('vbd')
  PART  = get_ext('vbn')
  VBP   = get_ext('vbp')
  VBZ   = get_ext('vbz')
  JJ    = get_ext('jj')
  JJR   = get_ext('jjr')
  JJS   = get_ext('jjs')
  RB    = get_ext('rb')
  RBR   = get_ext('rbr')
  RBS   = get_ext('rbs')
  RP    = get_ext('rp')
  WRB   = get_ext('wrb')
  WDT   = get_ext('wdt')
  WP    = get_ext('wp')
  WPS   = get_ext('wps')
  CC    = get_ext('cc')
  IN    = get_ext('in')

  # Convert a Treebank-style, abbreviated tag into verbose definitions
  def self.explain_tag(tag)
    if TAGS[tag]
      return TAGS[tag]
    else
      return tag
    end
  end

  # The folloging is to make a hash to convert a pos tag to its definition
  # used by the explain_tag method
  tags = [
    "CC",   "Conjunction, coordinating",
    "CD",   "Adjective, cardinal number",
    "DET",  "Determiner",
    "EX",   "Pronoun, existential there",
    "FW",   "Foreign words",
    "IN",   "Preposition / Conjunction",
    "JJ",   "Adjective",
    "JJR",  "Adjective, comparative",
    "JJS",  "Adjective, superlative",
    "LS",   "Symbol, list item",
    "MD",   "Verb, modal",
    "NN",   "Noun",
    "NNP",  "Noun, proper",
    "NNPS", "Noun, proper, plural",
    "NNS",  "Noun, plural",
    "PDT",  "Determiner, prequalifier",
    "POS",  "Possessive",
    "PRP",  "Determiner, possessive second",
    "PRPS", "Determiner, possessive",
    "RB",   "Adverb",
    "RBR",  "Adverb, comparative",
    "RBS",  "Adverb, superlative",
    "RP",   "Adverb, particle",
    "SYM",  "Symbol",
    "TO",   "Preposition",
    "UH",   "Interjection",
    "VB",   "Verb, infinitive",
    "VBD",  "Verb, past tense",
    "VBG",  "Verb, gerund",
    "VBN",  "Verb, past/passive participle",
    "VBP",  "Verb, base present form",
    "VBZ",  "Verb, present 3SG -s form",
    "WDT",  "Determiner, question",
    "WP",   "Pronoun, question",
    "WPS",  "Determiner, possessive & question",
    "WRB",  "Adverb, question",
    "PP",   "Punctuation, sentence ender",
    "PPC",  "Punctuation, comma",
    "PPD",  "Punctuation, dollar sign",
    "PPL",  "Punctuation, quotation mark left",
    "PPR",  "Punctuation, quotation mark right",
    "PPS",  "Punctuation, colon, semicolon, elipsis",
    "LRB",  "Punctuation, left bracket",
    "RRB",  "Punctuation, right bracket"
    ]
  tags = tags.collect{|t| t.downcase.gsub(/[\.\,\'\-\s]+/, '_')}
  tags = tags.collect{|t| t.gsub(/\&/, "and").gsub(/\//, "or")}
  TAGS = Hash[*tags]

  # Hash storing config values:
  #
  # * :unknown_word_tag
  #    => (String) Tag to assign to unknown words
  # * :stem
  #    => (Boolean) Stem single words using Porter module
  # * :weight_noun_phrases
  #    => (Boolean) When returning occurrence counts for a noun phrase, multiply
  #        the valuethe number of words in the NP.
  # * :longest_noun_phrase
  #    => (Integer) Will ignore noun phrases longer than this threshold. This
  #        affects only the get_words() and get_nouns() methods.
  # * :relax
  #    => (Boolean) Relax the Hidden Markov Model: this may improve accuracy for
  #        uncommon words, particularly words used polysemously
  # * :tag_lex
  #    => (String) Name of the YAML file containing a hash of adjacent part of
  #         speech tags and the probability of each
  # * :word_lex
  #    => (String) Name of the YAML file containing a hash of words and corresponding
  #        parts of speech
  # * :unknown_lex
  #    => (String) Name of the YAML file containing a hash of tags for unknown
  #        words and corresponding parts of speech
  # * :tag_path
  #    => (String) Directory path of tag_lex
  # * :word_path
  #    => (String) Directory path of word_lex and unknown_lex
  # * :debug
  #    => (Boolean) Print debug messages
  attr_accessor :conf

  ###############
  # Constructor #
  ###############

  # Take a hash of parameters that override default values.
  # See above for details.
  def initialize(params = {})
    @conf = Hash.new
    @conf[:unknown_word_tag] = ''
    @conf[:stem] = false
    @conf[:weight_noun_phrases] = false
    @conf[:longest_noun_phrase] = 5
    @conf[:relax] = false
    @conf[:tag_lex] = 'tags.yml'
    @conf[:word_lex] = 'words.yml'
    @conf[:unknown_lex] = 'unknown.yml'
    @conf[:word_path] = $word_path
    @conf[:tag_path] = $tag_path
    @conf[:debug] = false
    # assuming that we start analyzing from the beginninga new sentence...
    @conf[:current_tag] = 'pp'
    @conf.merge!(params)
    unless File.exists?(@conf[:word_path]) and File.exists?(@conf[:tag_path])
      print "Couldn't locate POS lexicon, creating a new one" if @conf[:debug]
      @@hmm = Hash.new
      @@lexicon = Hash.new
    else
      lexf = File.open(@conf[:word_path], 'r')
      @@lexicon = Marshal.load(lexf)
      lexf.close
      hmmf = File.open(@conf[:tag_path], 'r')
      @@hmm = Marshal.load(hmmf)
      hmmf.close
    end
    @@mnp = get_max_noun_regex
  end

  ##################
  # Public methods #
  ##################

  # Examine the string provided and return it fully tagged in XML style
  def add_tags(text, verbose = false)
    return nil unless valid_text(text)
    tagged = []
    words = clean_text(text)
    tags = Array.new
    words.each do |word|
      cleaned_word = clean_word(word)
      tag = assign_tag(@conf[:current_tag], cleaned_word)
      @conf[:current_tag] = tag = (tag and tag != "") ? tag : 'nn'
      tag = EngTagger.explain_tag(tag) if verbose
      tagged << '<' + tag + '>' + word + '</' + tag + '>'
    end
    reset
    return tagged.join(' ')
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
    if(@conf[:longest_noun_phrase] <= 1)
      return get_nouns(tagged)
    else
      return get_noun_phrases(tagged)
    end
  end

  # Return an easy-on-the-eyes tagged version of a text string.
  # Applies add_tags and reformats to be easier to read.
  def get_readable(text, verbose = false)
    return nil unless valid_text(text)
    tagged = add_tags(text, verbose)
    tagged = tagged.gsub(/<\w+>([^<]+)<\/(\w+)>/o) do
      $1 + '/' + $2.upcase
    end
    return tagged
  end

  # Return an array of sentences (without POS tags) from a text.
  def get_sentences(text)
    return nil unless valid_text(text)
    tagged = add_tags(text)
    sentences = Array.new
    tagged.split(/<\/pp>/).each do |line|
      sentences << strip_tags(line)
    end
    sentences = sentences.map do |sentence|
      sentence.gsub(Regexp.new(" ('s?) ")){$1 + ' '}
      sentence.gsub(Regexp.new(" (\W+) ")){$1 + ' '}
      sentence.gsub(Regexp.new(" (`+) ")){' ' + $1}
      sentence.gsub(Regexp.new(" (\W+)$")){$1}
      sentence.gsub(Regexp.new("^(`+) ")){$1}
    end
    return sentences
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
    nnp.keys.each do |key|
      words = key.split(/\s/)
      # Let's say this is an organization's name --
      # (and it's got at least three words)
      # is there a corresponding acronym in this hash?
      if words.length > 2
        # Make a (naive) acronym out of this name
        acronym = words.map do |word|
          /\A([a-z])[a-z]*\z/ =~ word
          $1
        end.join ''
        # If that acronym has been seen,
        # remove it and add the values to
        # the full name
        if nnp[acronym]
          nnp[key] += nnp[acronym]
          nnp.delete(acronym)
        end
      end
    end
    return nnp
  end

  # Given a POS-tagged text, this method returns all nouns and their
  # occurrence frequencies.
  def get_nouns(tagged)
    return nil unless valid_text(tagged)
    tags = [NN]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  # Returns all types of verbs and does not descriminate between the various kinds.
  # Is the combination of all other verb methods listed in this class.
  def get_verbs(tagged)
    return nil unless valid_text(tagged)
    tags = [VB, VBD, VBG, PART, VBP, VBZ]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  def get_infinitive_verbs(tagged)
    return nil unless valid_text(tagged)
    tags = [VB]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  def get_past_tense_verbs(tagged)
    return nil unless valid_text(tagged)
    tags = [VBD]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  def get_gerund_verbs(tagged)
    return nil unless valid_text(tagged)
    tags = [VBG]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  def get_passive_verbs(tagged)
    return nil unless valid_text(tagged)
    tags = [PART]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  def get_base_present_verbs(tagged)
    return nil unless valid_text(tagged)
    tags = [VBP]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  def get_present_verbs(tagged)
    return nil unless valid_text(tagged)
    tags = [VBZ]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  def get_adjectives(tagged)
    return nil unless valid_text(tagged)
    tags = [JJ]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  def get_comparative_adjectives(tagged)
    return nil unless valid_text(tagged)
    tags = [JJR]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  def get_superlative_adjectives(tagged)
    return nil unless valid_text(tagged)
    tags = [JJS]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  def get_adverbs(tagged)
    return nil unless valid_text(tagged)
    tags = [RB, RBR, RBS, RP]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  def get_interrogatives(tagged)
    return nil unless valid_text(tagged)
    tags = [WRB, WDT, WP, WPS]
    build_matches_hash(build_trimmed(tagged, tags))
  end
  # To be consistent with documentation's naming of 'interrogative' parts of speech as 'question'
  alias_method :get_question_parts, :get_interrogatives

  # Returns all types of conjunctions and does not discriminate between the various kinds.
  # E.g. coordinating, subordinating, correlative...
  def get_conjunctions(tagged)
    return nil unless valid_text(tagged)
    tags = [CC, IN]
    build_matches_hash(build_trimmed(tagged, tags))
  end

  # Given a POS-tagged text, this method returns only the maximal noun phrases.
  # May be called directly, but is also used by get_noun_phrases
  def get_max_noun_phrases(tagged)
    return nil unless valid_text(tagged)
    tags = [@@mnp]
    mn_phrases = build_trimmed(tagged, tags)
    ret = Hash.new(0)
    mn_phrases.each do |p|
      p = stem(p) unless p =~ /\s/  # stem single words
      ret[p] += 1 unless p =~ /\A\s*\z/
    end
    return ret
  end

  # Similar to get_words, but requires a POS-tagged text as an argument.
  def get_noun_phrases(tagged)
    return nil unless valid_text(tagged)
    found = Hash.new(0)
    phrase_ext = /(?:#{PREP}|#{DET}|#{NUM})+/xo
    scanned = tagged.scan(@@mnp)
    # Find MNPs in the text, one sentence at a time
    # Record and split if the phrase is extended by a (?:PREP|DET|NUM)
    mn_phrases = []
    scanned.each do |m|
      found[m] += 1 if phrase_ext =~ m
      mn_phrases += m.split(phrase_ext)
    end
    mn_phrases.each do |mnp|
     # Split the phrase into an array of words, and create a loop for each word,
     # shortening the phrase by removing the word in the first position.
     # Record the phrase and any single nouns that are found
      words = mnp.split
      words.length.times do |i|
        found[words.join(' ')] += 1 if words.length > 1
        w = words.shift
        found[w] += 1 if w =~ /#{NN}/
      end
    end
    ret = Hash.new(0)
    found.keys.each do |f|
      k = strip_tags(f)
      v = found[f]
      # We weight by the word count to favor long noun phrases
      space_count = k.scan(/\s+/)
      word_count = space_count.length + 1
      # Throttle MNPs if necessary
      next if word_count > @conf[:longest_noun_phrase]
      k = stem(k) unless word_count > 1  # stem single words
      multiplier = 1
      multiplier = word_count if @conf[:weight_noun_phrases]
      ret[k] += multiplier * v
    end
    return ret
  end

  # Reads some included corpus data and saves it in a stored hash on the
  # local file system. This is called automatically if the tagger can't
  # find the stored lexicon.
  def install
    puts "Creating part-of-speech lexicon" if @conf[:debug]
    load_tags(@conf[:tag_lex])
    load_words(@conf[:word_lex])
    load_words(@conf[:unknown_lex])
    File.open(@conf[:word_path], 'w') do |f|
      Marshal.dump(@@lexicon, f)
    end
    File.open(@conf[:tag_path], 'w') do |f|
      Marshal.dump(@@hmm, f)
    end
  end

  ###################
  # Private methods #
  ###################

  :private

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

  # Downcase the first letter of word
  def lcfirst(word)
    word.split(//)[0].downcase + word.split(//)[1..-1].join
  end

  # Upcase the first letter of word
  def ucfirst(word)
    word.split(//)[0].upcase + word.split(//)[1..-1].join
  end

  # Return the word stem as given by Stemmable module. This can be
  # turned off with the class parameter @conf[:stem] => false.
  def stem(word)
    return word unless @conf[:stem]
    return word.stem
  end

  # This method will reset the preceeding tag to a sentence ender (PP).
  # This prepares the first word of a new sentence to be tagged correctly.
  def reset
    @conf[:current_tag] = 'pp'
  end

  # Check whether the text is a valid string
  def valid_text(text)
    if !text
      # there's nothing to parse
      "method call on uninitialized variable" if @conf[:debug]
      return false
    elsif /\A\s*\z/ =~ text
      # text is an empty string, nothing to parse
      return false
    else
      # $text is valid
      return true
    end
  end

  # Return a text string with the part-of-speech tags removed
  def strip_tags(tagged, downcase = false)
    return nil unless valid_text(tagged)
    text = tagged.gsub(/<[^>]+>/m, "")
    text = text.gsub(/\s+/m, " ")
    text = text.gsub(/\A\s*/, "")
    text = text.gsub(/\s*\z/, "")
    if downcase
      return text.downcase
    else
      return text
    end
  end

  # Strip the provided text of HTML-style tags and separate off any punctuation
  # in preparation for tagging
  def clean_text(text)
    return false unless valid_text(text)
    text = text.toutf8
    unless $no_hpricot
      # Strip out any markup and convert entities to their proper form
      cleaned_text = Hpricot(text).inner_text
    else
      cleaned_text = text
    end
    tokenized = []
    # Tokenize the text (splitting on punctuation as you go)
    cleaned_text.split(/\s+/).each do |line|
      tokenized += split_punct(line)
    end
    words = split_sentences(tokenized)
    return words
  end

  # This handles all of the trailing periods, keeping those that
  # belong on abbreviations and removing those that seem to be
  # at the end of sentences. This method makes some assumptions
  # about the use of capitalization in the incoming text
  def split_sentences(array)
    tokenized = array
    people = %w(jr mr ms mrs dr prof esq sr sen sens rep reps gov attys attys
                supt det mssrs rev)
    army   = %w(col gen lt cmdr adm capt sgt cpl maj brig)
    inst   = %w(dept univ assn bros ph.d)
    place  = %w(arc al ave blvd bld cl ct cres exp expy dist mt mtn ft fy fwy
                hwy hway la pde pd plz pl rd st tce)
    comp   = %w(mfg inc ltd co corp)
    state  = %w(ala ariz ark cal calif colo col conn del fed fla ga ida id ill
                ind ia kans kan ken ky la me md is mass mich minn miss mo mont
                neb nebr nev mex okla ok ore penna penn pa dak tenn tex ut vt
                va wash wis wisc wy wyo usafa alta man ont que sask yuk)
    month  = %w(jan feb mar apr may jun jul aug sep sept oct nov dec)
    misc   = %w(vs etc no esp)
    abbr = Hash.new
    [people, army, inst, place, comp, state, month, misc].flatten.each do |i|
      abbr[i] = true
    end
    words = Array.new
    tokenized.each_with_index do |t, i|
      if tokenized[i + 1] and tokenized [i + 1] =~ /[A-Z\W]/ and tokenized[i] =~ /\A(.+)\.\z/
        w = $1
        # Don't separate the period off words that
        # meet any of the following conditions:
        #
        # 1. It is defined in one of the lists above
        # 2. It is only one letter long: Alfred E. Sloan
        # 3. It has a repeating letter-dot: U.S.A. or J.C. Penney
        unless abbr[w.downcase] or w =~ /\A[a-z]\z/i or w =~ /[a-z](?:\.[a-z])+\z/i
          words <<  w
          words << '.'
          next
        end
      end
      words << tokenized[i]
    end
    # If the final word ends in a period..
    if words[-1] and words[-1] =~ /\A(.*\w)\.\z/
      words[-1] = $1
      words.push '.'
    end
    return words
  end

  # Separate punctuation from words, where appropriate. This leaves trailing
  # periods in place to be dealt with later. Called by the clean_text method.
  def split_punct(text)
    # If there's no punctuation, return immediately
    return [text] if /\A\w+\z/ =~ text
    # Sanity checks
    text = text.gsub(/\W{10,}/o, " ")

    # Put quotes into a standard format
    text = text.gsub(/`(?!`)(?=.*\w)/o, "` ") # Shift left quotes off text
    text = text.gsub(/"(?=.*\w)/o, " `` ") # Convert left quotes to ``
    text = text.gsub(/(\W|^)'(?=.*\w)/o){$1 ? $1 + " ` " : " ` "} # Convert left quotes to `
    text = text.gsub(/"/, " '' ") # Convert (remaining) quotes to ''
    text = text.gsub(/(\w)'(?!')(?=\W|$)/o){$1 + " ' "} # Separate right single quotes

    # Handle all other punctuation
    text = text.gsub(/--+/o, " - ") # Convert and separate dashes
    text = text.gsub(/,(?!\d)/o, " , ") # Shift commas off everything but numbers
    text = text.gsub(/:/o, " :") # Shift semicolons off
    text = text.gsub(/(\.\.\.+)/o){" " + $1 + " "} # Shift ellipses off
    text = text.gsub(/([\(\[\{\}\]\)])/o){" " + $1 + " "} # Shift off brackets
    text = text.gsub(/([\!\?#\$%;~|])/o){" " + $1 + " "} # Shift off other ``standard'' punctuation

    # English-specific contractions
    text = text.gsub(/([A-Za-z])'([dms])\b/o){$1 + " '" + $2}  # Separate off 'd 'm 's
    text = text.gsub(/n't\b/o, " n't")                     # Separate off n't
    text = text.gsub(/'(ve|ll|re)\b/o){" '" + $1}         # Separate off 've, 'll, 're
    result = text.split(' ')
    return result
  end

  # Given a preceding tag, assign a tag word. Called by the add_tags method.
  # This method is a modified version of the Viterbi algorithm for part-of-speech tagging
  def assign_tag(prev_tag, word)
    if word == "-unknown-"
      # classify unknown words accordingly
      return @conf[:unknown_word_tag]
    elsif word == "-sym-"
      # If this is a symbol, tag it as a symbol
      return "sym"
    end
    best_so_far = 0
    w = @@lexicon[word]
    t = @@hmm

    # TAG THE TEXT: What follows is a modified version of the Viterbi algorithm
    # which is used in most POS taggers
    best_tag = ""
    t[prev_tag].keys.each do |tag|
      # With @config[:relax] set, this method
      # will also include any `open classes' of POS tags
      pw = 0
      if w[tag]
        pw = w[tag]
      elsif @conf[:relax] and tag =~ /\A(?:jj|nn|rb|vb)/
        pw = 0
      else
        next
      end

      # Bayesian logic:
      # P =  P( tag | prev_tag ) * P( tag | word )
      probability = t[prev_tag][tag] * (pw + 1)
      # Set the tag with maximal probability
      if probability > best_so_far
        best_so_far = probability
        best_tag = tag
      end
    end
    return best_tag
  end

  # This method determines whether a word should be considered in its
  # lower or upper case form. This is useful in considering proper nouns
  # and words that begin sentences. Called by add_tags.
  def clean_word(word)
    lcf = lcfirst(word)
    # seen this word as it appears (lower or upper case)
    if @@lexicon[word]
      return word
    elsif @@lexicon[lcf]
      # seen this word only as lower case
      return lcf
    else
      # never seen this word. guess.
      return classify_unknown_word(word)
    end
  end

  # This changes any word not appearing in the lexicon to identifiable
  # classes of words handled by a simple unknown word classification
  # metric. Called by the clean_word method.
  def classify_unknown_word(word)
    if /[\(\{\[]/ =~ word  # Left brackets
      classified = "*LRB*"
    elsif
      /[\)\}\]]/ =~ word   # Right brackets
      classified = "*RRB*"
    elsif /-?(?:\d+(?:\.\d*)?|\.\d+)\z/ =~ word # Floating point number
      classified = "*NUM*"
    elsif /\A\d+[\d\/:-]+\d\z/ =~ word  # Other number constructs
      classified = "*NUM*"
    elsif /\A-?\d+\w+\z/o =~ word        # Ordinal number
      classified = "*ORD*"
    elsif /\A[A-Z][A-Z\.-]*\z/o =~ word  # Abbreviation (all caps)
      classified = "-abr-"
    elsif /\w-\w/o =~ word             # Hyphenated word
      /-([^-]+)\z/ =~ word
      h_suffix = $1
      if h_suffix and (@@lexicon[h_suffix] and @@lexicon[h_suffix]['jj'])
        # last part of this is defined as an adjective
        classified = "-hyp-adj-"
      else
        # last part of this is not defined as an adjective
        classified = "-hyp-"
      end
    elsif /\A\W+\z/o =~ word
      classified = "-sym-"  # Symbol
    elsif word == ucfirst(word)
      classified = "-cap-"  # Capitalized word
    elsif /ing\z/o =~ word
      classified = "-ing-"  # Ends in 'ing'
    elsif /s\z/o =~ word
      classified = "-s-"    # Ends in 's'
    elsif /tion\z/o =~ word
      classified = "-tion-" # Ends in 'tion'
    elsif /ly\z/o =~ word
      classified = "-ly-"  # Ends in 'ly'
    elsif /ed\z/o =~ word
      classified = "-ed-"  # Ends in 'ed
    else
      classified = "-unknown-" # Completely unknown
    end
    return classified
  end

  # This returns a compiled regexp for extracting maximal noun phrases
  # from a POS-tagged text.
  def get_max_noun_regex
    regex = /
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
    /xo #/
    return regex
  end

  # Load the 2-grams into a hash from YAML data: This is a naive (but fast)
  # YAML data parser. It will load a YAML document with a collection of key:
  # value entries ( {pos tag}: {probability} ) mapped onto single keys ( {tag} ).
  # Each map is expected to be on a single line; i.e., det: { jj: 0.2, nn: 0.5, vb: 0.0002 }
  def load_tags(lexicon)
    path = File.join($lexpath, lexicon)
    fh = File.open(path, 'r')
    while line = fh.gets
      /\A"?([^{"]+)"?: \{ (.*) \}/ =~ line
      next unless $1 and $2
      key, data = $1, $2
      tags = Hash.new
      items = data.split(/,\s+/)
      pairs = {}
      items.each do |i|
        /([^:]+):\s*(.+)/ =~ i
        pairs[$1] = $2.to_f
      end
      @@hmm[key] = pairs
    end
    fh.close
  end

  # Load the 2-grams into a hash from YAML data: This is a naive (but fast)
  # YAML data parser. It will load a YAML document with a collection of key:
  # value entries ( {pos tag}: {count} ) mapped onto single keys ( {a word} ).
  # Each map is expected to be on a single line; i.e., key: { jj: 103, nn: 34, vb: 1 }
  def load_words(lexicon)
    path = File.join($lexpath, lexicon)
    fh = File.open(path, 'r')
    while line = fh.gets
      /\A"?([^{"]+)"?: \{ (.*) \}/ =~ line
      next unless $1 and $2
      key, data = $1, $2
      tags = Hash.new
      items = data.split(/,\s+/)
      pairs = {}
      items.each do |i|
        /([^:]+):\s*(.+)/ =~ i
        pairs[$1] = $2.to_f
      end
      @@lexicon[key] = pairs
    end
    fh.close
  end

  #memoize the stem and assign_tag methods
  memoize("stem")
  memoize("assign_tag")
end
