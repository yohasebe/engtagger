# frozen_string_literal: true

require "strscan"
require "set"

class EngTagger
  # PTB/UD-compatible English word tokenizer.
  #
  # Non-destructive by construction: every token is a
  # contiguous substring of the input, so callers can recover character
  # offsets and detokenize exactly.
  #
  # Conventions follow PTB as adapted by UD: contractions split (do|n't,
  # I|'m), possessive 's split, hyphenated compounds split around HYPH except
  # bound prefixes, URLs/emails/filenames kept whole, multi-dot abbreviations
  # kept with their periods.
  module Tokenizer
    URL = %r{(?:https?://|www\.)[^\s<>"“”]+}
    EMAIL = /[A-Za-z0-9][\w.+-]*@[\w-]+(?:\.[\w-]+)*/

    # filenames: report.doc, 20.doc, .doc
    FILENAME = /[\w-]*\.(?:docx?|pdf|txt|xlsx?|jpe?g|png|gif|html?|php|zip|exe|mp3|wav|pptx?|csv)(?![\p{L}\d])/i

    # U.S., e.g., i.e., a.m., D.C., Ph.D., U.S (final dot swallowed by EOS)
    ACRONYM = /(?:[A-Za-z]{1,2}\.){2,}(?![A-Za-z])/
    ACRONYM_TAIL = /(?:[A-Za-z]\.)+[A-Za-z](?![\p{L}\d.])/

    # bare web domains: amazon.com, galleryfurniture.com
    DOMAIN = /[\w-]+(?:\.[\w-]+)*\.(?:com|net|org|edu|gov|info|biz|io)(?![\p{L}\d])/i

    ABBREVS = %w[
      mr mrs ms dr prof st jr sr rev gen rep sen gov capt sgt col lt maj
      vs etc inc ltd co corp dept univ assn bros vol pp approx est
      jan feb mar apr jun jul aug sep sept oct nov dec
      mon tue tues wed thu thur thurs fri sat sun
      ave blvd rd mt ft fig ref cf al seq
    ].to_set.freeze
    ABBREV = /[A-Za-z]{1,6}\.(?![A-Za-z])/

    # Name initials kept with period: "George W. Bush" ("I" excluded: pronoun)
    INITIAL = /(?!I\.)[A-Z]\.(?![\p{L}\d])/

    # 1,000.50 | 12/25/2010 | 5:30 | 646-8420 | .38 | 20th | 1970s | 32A
    # (ordinal/decade/single-capital suffixes attach; "5pm" splits)
    NUMBER = %r{\d+(?:[.,:/-]\d+)*(?:(?:st|nd|rd|th|s)(?![\p{L}\d])|[A-Z](?![\p{L}\d]))?|\.\d+}

    # AT&T, PG&E, P&L, s/he
    AMP_WORD = %r{\p{L}+(?:&\p{L}+)+|[sS]/he(?![\p{L}\d])}

    # Truncated / stuttered word: "w- well, I..."
    STUTTER = /\p{L}{1,2}-(?=\s|\z)/

    # Word-ish chunk incl. internal hyphens/apostrophes; split decisions
    # happen in post-processing.
    WORDLIKE = /[\p{L}\p{M}\d]+(?:[-'’][\p{L}\p{M}\d]+)*['’]?/

    # Clitic left bare by preceding split/number: the 90 's | `s | 'M
    APOS_CLITIC = /['’`](?:ll|re|ve|em|til|cause|[smd])(?![\p{L}\d])/i

    MULTI_PUNCT = %r{[.!?…]{2,}|--+|``|''|[‘’]{2}|<<|>>|<3|[:=;]-?[()DPp/]|\(:|;-?\)}

    # Decorative symbol runs and ASCII emoticons: ==== ____ *** ^_^
    SYM_RUN = /[=_*~^#+]{2,}/

    # Bound prefixes: keep "pre-owned" etc. as one token (EWT convention).
    HYPHEN_PREFIXES = %w[
      e a non mid pre re anti post co pro multi over ex semi sub neo
      ultra inter intra counter pseudo psycho quasi meta micro macro mini
      uni bi tri cross
    ].to_set.freeze

    # Lexical multiword tokens (surface -> parts, all substrings in order).
    SPECIAL_SPLITS = {
      "cannot" => %w[can not],
      "gonna" => %w[gon na],
      "wanna" => %w[wan na],
      "gotta" => %w[got ta],
      "lemme" => %w[lem me],
      "gimme" => %w[gim me],
      "outta" => %w[out ta],
      "dunno" => %w[du nno],
      "i'ma" => ["i", "'m", "a"],
      "i’ma" => ["i", "’m", "a"],
      # apostrophe-less contractions (typos; UD splits them)
      "dont" => %w[do nt], "wont" => %w[wo nt], "cant" => %w[ca nt],
      "aint" => %w[ai nt], "arent" => %w[are nt], "isnt" => %w[is nt],
      "didnt" => %w[did nt], "doesnt" => %w[does nt], "wasnt" => %w[was nt],
      "couldnt" => %w[could nt], "wouldnt" => %w[would nt],
      "shouldnt" => %w[should nt], "havent" => %w[have nt],
      "hasnt" => %w[has nt],
      "im" => %w[i m], "ive" => %w[i ve], "youre" => %w[you re],
      "youll" => %w[you ll], "thats" => %w[that s], "theres" => %w[there s],
      "hes" => %w[he s], "shes" => %w[she s]
    }.freeze

    CLITICS = /\A(?:ll|re|ve|d|m|s)\z/i

    # A candidate that fails after reading a long stretch would read it again
    # from every later start. Each pattern below is paired with the stretch it
    # reads: once it fails at a position, it fails at every position inside
    # that stretch, so it is not tried there again.
    STRETCHES = {
      EMAIL => /[A-Za-z0-9][\w.+-]*/,
      FILENAME => /[\w-]*\.?/,
      DOMAIN => /[\w-]+(?:\.[\w-]+)*/,
      ACRONYM => /(?:[A-Za-z]{1,2}\.)+/,
      ACRONYM_TAIL => /(?:[A-Za-z]\.)+/
    }.freeze

    module_function

    # => array of token strings
    def tokenize(text)
      tokenize_spans(text).map { |t, _s, _e| t }
    end

    # => array of [token, start_offset, end_offset(exclusive)]
    def tokenize_spans(text)
      scanner = StringScanner.new(text)
      out = []
      byte_pos = start = 0
      failed_until = Hash.new(0)
      until scanner.eos?
        next if scanner.skip(/\s+/)

        # StringScanner#charpos rescans from the beginning of the string on
        # every call, so the character offset is advanced token by token.
        byte_start = scanner.pos
        start += text.byteslice(byte_pos, byte_start - byte_pos).length
        byte_pos = byte_start
        if (tok = scanner.scan(URL) || scan_once(scanner, EMAIL, failed_until))
          # strip trailing sentence punctuation accidentally captured
          tok = strip_trailing_punct(tok)
          scanner.pos = byte_start + tok.bytesize
          out << [tok, start, start + tok.length]
        elsif (tok = scan_name(scanner, failed_until))
          out << [tok, start, start + tok.length]
        elsif (tok = scanner.scan(NUMBER))
          split_number(tok).each do |sub, off|
            out << [sub, start + off, start + off + sub.length]
          end
        elsif (tok = scanner.scan(AMP_WORD) || scanner.scan(STUTTER))
          out << [tok, start, start + tok.length]
        elsif (tok = scanner.scan(WORDLIKE))
          split_wordlike(tok).each do |sub, off|
            out << [sub, start + off, start + off + sub.length]
          end
        elsif (tok = scanner.scan(APOS_CLITIC) || scanner.scan(MULTI_PUNCT) ||
                     scanner.scan(SYM_RUN) || scanner.getch)
          out << [tok, start, start + tok.length]
        end
      end
      out
    end

    # File names, domains, acronyms, initials and abbreviations: tokens that
    # keep their periods.
    def scan_name(scanner, failed_until)
      scan_once(scanner, FILENAME, failed_until) || scan_once(scanner, DOMAIN, failed_until) ||
        scan_once(scanner, ACRONYM, failed_until) || scan_once(scanner, ACRONYM_TAIL, failed_until) ||
        scanner.scan(INITIAL) || check_abbrev(scanner)
    end

    # Scan `pattern` unless it is known to fail here (see STRETCHES).
    def scan_once(scanner, pattern, failed_until)
      return nil if scanner.pos < failed_until[pattern]

      tok = scanner.scan(pattern) and return tok
      stretch = scanner.match?(STRETCHES.fetch(pattern))
      failed_until[pattern] = scanner.pos + stretch if stretch
      nil
    end

    # Drop trailing sentence punctuation, keeping at least one character.
    def strip_trailing_punct(tok)
      kept = tok.reverse.sub(/\A[.,;:!?)]+/, "").reverse
      kept.empty? ? tok[0] : kept
    end

    def check_abbrev(scanner)
      tok = scanner.check(ABBREV) or return nil
      return nil unless ABBREVS.include?(tok[0..-2].downcase)

      scanner.pos += tok.bytesize
      tok
    end

    # Split a word-like chunk into subtokens; returns [[substr, offset], ...]
    def split_wordlike(tok)
      if (parts = SPECIAL_SPLITS[tok.downcase]) && tok != "IM"
        return special_offsets(tok, parts)
      end

      return split_hyphenated(tok) if tok.include?("-")

      split_clitics(tok)
    end

    def special_offsets(tok, parts)
      out = []
      off = 0
      parts.each do |p|
        out << [tok[off, p.length], off]
        off += p.length
      end
      out
    end

    # Hyphenated numbers: keep phone-like (646-8420, x3-9890), split short
    # ranges (3-4) as UD does.
    def split_number(tok)
      has_hyphen = tok.include?("-")
      return [[tok, 0]] unless has_hyphen && (tok.length < 6 || tok.include?(":"))

      out = []
      off = 0
      tok.split(/(-)/).each do |p|
        out << [p, off] unless p.empty?
        off += p.length
      end
      out
    end

    def split_hyphenated(tok)
      pieces = tok.split(/(-)/) # keeps hyphens as separate elements
      words = pieces.reject { |p| p == "-" }

      keep = (words.all? { |w| w =~ /\d/ } && tok.length >= 6) ||   # 646-8420
             (words.size == 2 && words[1] =~ /\A[a-z]\z/) ||        # Naqsh-e
             (words.size == 2 && HYPHEN_PREFIXES.include?(words[0].downcase))

      if keep
        split_clitics_tail_only(tok)
      else
        out = []
        off = 0
        pieces.each do |p|
          if p == "-"
            out << [p, off]
            off += 1
          else
            split_clitics(p).each { |sub, o| out << [sub, off + o] }
            off += p.length
          end
        end
        out
      end
    end

    # For tokens we decided to keep whole except a possible clitic tail
    def split_clitics_tail_only(tok)
      split_clitics(tok, split_internal: false)
    end

    def split_clitics(tok, split_internal: true)
      _ = split_internal
      # n't (don't -> do n't; can't -> ca n't; ain't -> ai n't)
      if tok =~ /\A(.+)(n['’]t)\z/i && Regexp.last_match(1).length >= 1
        base = Regexp.last_match(1)
        return [[base, 0], [Regexp.last_match(2), base.length]]
      end

      # 'll 're 've 'd 'm 's (keeps o'clock, O'Brien intact)
      if tok =~ /\A(.+)(['’])([A-Za-z]{1,2})\z/ && CLITICS.match?(Regexp.last_match(3))
        base = Regexp.last_match(1)
        clitic = Regexp.last_match(2) + Regexp.last_match(3)
        return [[base, 0], [clitic, base.length]]
      end

      # trailing bare apostrophe: plural possessive (boys') or quote
      if tok =~ /\A(.*[\p{L}\d])(['’])\z/
        base = Regexp.last_match(1)
        return [[base, 0], [Regexp.last_match(2), base.length]]
      end

      [[tok, 0]]
    end
  end
end
