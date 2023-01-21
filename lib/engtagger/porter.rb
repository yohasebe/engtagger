# frozen_string_literal: true

module Stemmable
  STEP_2_LIST = {
    "ational" => "ate", "tional" => "tion", "enci" => "ence", "anci" => "ance",
    "izer" => "ize", "bli" => "ble",
    "alli" => "al", "entli" => "ent", "eli" => "e", "ousli" => "ous",
    "ization" => "ize", "ation" => "ate",
    "ator" => "ate", "alism" => "al", "iveness" => "ive", "fulness" => "ful",
    "ousness" => "ous", "aliti" => "al",
    "iviti" => "ive", "biliti" => "ble", "logi" => "log"
  }.freeze

  STEP_3_LIST = {
    "icate" => "ic", "ative" => "", "alize" => "al", "iciti" => "ic",
    "ical" => "ic", "ful" => "", "ness" => ""
  }.freeze

  SUFFIX_1_REGEXP = /(
                    ational  |
                    tional   |
                    enci     |
                    anci     |
                    izer     |
                    bli      |
                    alli     |
                    entli    |
                    eli      |
                    ousli    |
                    ization  |
                    ation    |
                    ator     |
                    alism    |
                    iveness  |
                    fulness  |
                    ousness  |
                    aliti    |
                    iviti    |
                    biliti   |
                    logi)$/x.freeze


  SUFFIX_2_REGEXP = /(
                      al       |
                      ance     |
                      ence     |
                      er       |
                      ic       |
                      able     |
                      ible     |
                      ant      |
                      ement    |
                      ment     |
                      ent      |
                      ou       |
                      ism      |
                      ate      |
                      iti      |
                      ous      |
                      ive      |
                      ize)$/x.freeze

  C = "[^aeiou]" # consonant
  V = "[aeiouy]" # vowel
  CC = "#{C}(?>[^aeiouy]*)" # consonant sequence
  VV = "#{V}(?>[aeiou]*)"   # vowel sequence

  MGR0 = /^(#{CC})?#{VV}#{CC}/o.freeze # [cc]vvcc... is m>0
  MEQ1 = /^(#{CC})?#{VV}#{CC}(#{VV})?$/o.freeze # [cc]vvcc[vv] is m=1
  MGR1 = /^(#{CC})?#{VV}#{CC}#{VV}#{CC}/o.freeze # [cc]vvccvvcc... is m>1
  VOWEL_IN_STEM = /^(#{CC})?#{V}/o.freeze # vowel in stem

  # Porter stemmer in Ruby.
  #
  # This is the Porter stemming algorithm, ported to Ruby from the
  # version coded up in Perl.  It's easy to follow against the rules
  # in the original paper in:
  #
  #   Porter, 1980, An algorithm for suffix stripping, Program, Vol. 14,
  #   no. 3, pp 130-137,
  #
  # See also http://www.tartarus.org/~martin/PorterStemmer
  #
  # Send comments to raypereda@hotmail.com
  #

  def stem_porter
    # make a copy of the given object and convert it to a string.
    w = dup.to_str

    return w if w.length < 3

    # now map initial y to Y so that the patterns never treat it as vowel
    w[0] = "Y" if w[0] == "y"

    # Step 1a
    case w
    when /(ss|i)es$/
      w = $` + $1
    when /([^s])s$/
      w = $` + $1
    end

    # Step 1b
    case w
    when /eed$/
      w.chop! if $` =~ MGR0
    when /(ed|ing)$/
      stem = $`
      if stem =~ VOWEL_IN_STEM
        w = stem
        case w
        when /(at|bl|iz)$/             then w << "e"
        when /([^aeiouylsz])\1$/       then w.chop!
        when /^#{CC}#{V}[^aeiouwxy]$/o then w << "e"
        end
      end
    end

    if w =~ /y$/
      stem = $`
      w = stem + "i" if stem =~ VOWEL_IN_STEM
    end

    # Step 2
    if w =~ SUFFIX_1_REGEXP
      stem = $`
      suffix = $1
      # print "stem= " + stem + "\n" + "suffix=" + suffix + "\n"
      w = stem + STEP_2_LIST[suffix] if stem =~ MGR0
    end

    # Step 3
    if w =~ /(icate|ative|alize|iciti|ical|ful|ness)$/
      stem = $`
      suffix = $1
      w = stem + STEP_3_LIST[suffix] if stem =~ MGR0
    end

    # Step 4
    if w =~ SUFFIX_2_REGEXP
      stem = $`
      w = stem if stem =~ MGR1
    elsif w =~ /(s|t)(ion)$/
      stem = $` + $1
      w = stem if stem =~ MGR1
    end

    #  Step 5
    if w =~ /e$/
      stem = $`
      w = stem if (stem =~ MGR1) || (stem =~ MEQ1 && stem !~ /^#{CC}#{V}[^aeiouwxy]$/o)
    end

    w.chop! if w =~ /ll$/ && w =~ MGR1

    # and turn initial Y back to y
    w[0] = "y" if w[0] == "Y"
    w
  end

  # make the stem_porter the default stem method, just in case we
  # feel like having multiple stemmers available later.
  alias stem stem_porter
end

# Add stem method to all Strings
class String
  include Stemmable
end
