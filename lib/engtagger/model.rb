# frozen_string_literal: true

require "stringio"
require "zlib"

class EngTagger
  # Packed, read-only container for a trained averaged-perceptron model.
  #
  # The trainer produces string-keyed weights ("i-1 tag+i word nn the" =>
  # {"nn" => 1.25, ...}), one small Hash per feature. This format keeps the
  # feature strings -- a feature absent from the model can then never be
  # mistaken for one that is present -- but replaces the per-feature Hashes
  # with one packed buffer of postings, so a loaded model is a single
  # String => Integer index plus a flat byte string.
  #
  # Weights are quantized to int16 with a fixed scale. Since every weight
  # shares one scale, tag scores can be accumulated as integers and compared
  # directly -- the scale never enters the argmax.
  #
  # ETM2 layout (little-endian; see docs/model-format.md):
  #   magic "ETM2" | u16 version | u16 flags | u16 scale | u16 n_classes
  #   u32 n_features | u32 n_postings | u32 n_tagdict | u32 keys_bytes
  #   classes:  n_classes  x [u8 len, bytes]           (tag_id order)
  #   tagdict:  n_tagdict  x [u8 len, bytes, u8 tag_id] (bytewise ascending)
  #   keys:     n_features x [bytes, 0x00]              (bytewise ascending)
  #   counts:   n_features x u8                         (postings per feature)
  #   postings: n_postings x [u8 tag_id, i16 weight]
  class Model
    MAGIC = "ETM2"
    FORMAT_VERSION = 2
    FLAG_QUANTIZED = 0x1
    HEADER_SIZE = 28
    POSTING_SIZE = 3
    KEY_TERMINATOR = "\0"

    # Upper bound on the inflated size of a gzipped model file.
    MAX_PACKED_BYTES = 256 * 1024 * 1024

    attr_reader :classes, :tagdict, :weight_scale

    class Error < StandardError; end

    # Read a model file, gzipped or not.
    def self.read(path)
      blob = File.binread(path)
      blob = inflate(blob) if blob.start_with?("\x1f\x8b".b)
      new(blob)
    end

    def self.inflate(blob)
      gz = Zlib::GzipReader.new(StringIO.new(blob))
      packed = gz.read(MAX_PACKED_BYTES + 1).to_s.b
      raise Error, "model file inflates to more than #{MAX_PACKED_BYTES} bytes" if packed.bytesize > MAX_PACKED_BYTES

      gz.read(1) # reaching the end of the stream is what verifies the gzip checksum
      packed
    rescue Zlib::Error => e
      raise Error, "corrupt gzip container: #{e.message}"
    end
    private_class_method :inflate

    def initialize(blob)
      parse_header(blob)
      parse_sections(blob)
    end

    # Number of distinct features carried by this model.
    def size
      @index.size
    end

    # Yield [tag_id, quantized_weight] for each posting of `feature`, or
    # nothing when the feature is absent. Written as an each-style method so
    # scoring allocates no intermediate array per lookup.
    def each_posting(feature)
      slot = @index[key_of(feature)]
      return unless slot

      pos = (slot >> 8) * POSTING_SIZE
      (slot & 0xff).times do
        yield @postings.getbyte(pos), unpack_i16(pos + 1)
        pos += POSTING_SIZE
      end
    end

    # Yield each feature string.
    def each_feature(&block)
      @index.each_key(&block)
    end

    # Human-readable weight, mainly for inspection and tests.
    def weight(feature, tag)
      tag_id = @classes.index(tag) or return 0.0
      each_posting(feature) { |t, w| return w.fdiv(@weight_scale) if t == tag_id }
      0.0
    end

    private

    # Keys are compared as UTF-8 byte strings, whatever encoding the tagged
    # text arrived in.
    def key_of(feature)
      feature.encoding == Encoding::UTF_8 ? feature : feature.b.force_encoding(Encoding::UTF_8)
    end

    def unpack_i16(pos)
      v = @postings.getbyte(pos) | (@postings.getbyte(pos + 1) << 8)
      v >= 0x8000 ? v - 0x10000 : v
    end

    def parse_header(blob)
      raise Error, "not an EngTagger model file" unless blob.byteslice(0, 4) == MAGIC && blob.bytesize >= HEADER_SIZE

      version, flags, @weight_scale, @n_classes = blob.byteslice(4, 8).unpack("v4")
      raise Error, "unsupported model format version #{version}" unless version == FORMAT_VERSION
      raise Error, "model is not quantized" unless flags.anybits?(FLAG_QUANTIZED)
      raise Error, "model has a zero weight scale" if @weight_scale.zero?

      @n_features, @n_postings, @n_tagdict, @keys_bytes = blob.byteslice(12, 16).unpack("V4")
    end

    def parse_sections(blob)
      pos = parse_classes(blob, HEADER_SIZE)
      pos = parse_tagdict(blob, pos)
      expected = pos + @keys_bytes + @n_features + (@n_postings * POSTING_SIZE)
      raise Error, "model file is truncated or has trailing data" unless blob.bytesize == expected

      build_index(blob, pos)
    end

    def parse_classes(blob, pos)
      @classes = Array.new(@n_classes) do
        tag, pos = read_string(blob, pos)
        tag
      end
      pos
    end

    def parse_tagdict(blob, pos)
      @tagdict = {}
      @n_tagdict.times do
        word, pos = read_string(blob, pos)
        @tagdict[word] = @classes.fetch(blob.getbyte(pos) || @n_classes) do
          raise Error, "tag dictionary refers to an unknown tag"
        end
        pos += 1
      end
      pos
    end

    # => [string, position after it]
    def read_string(blob, pos)
      len = blob.getbyte(pos) or raise Error, "model file is truncated"
      bytes = blob.byteslice(pos + 1, len)
      raise Error, "model file is truncated" unless bytes && bytes.bytesize == len

      [bytes.force_encoding(Encoding::UTF_8).freeze, pos + 1 + len]
    end

    # One String => Integer Hash for the whole model: feature => posting
    # offset in the high bits, posting count in the low byte. The postings
    # themselves stay in one packed buffer.
    def build_index(blob, pos)
      keys = blob.byteslice(pos, @keys_bytes).force_encoding(Encoding::UTF_8).split(KEY_TERMINATOR)
      counts = blob.byteslice(pos + @keys_bytes, @n_features).unpack("C*")
      raise Error, "model index does not match its header" unless keys.size == @n_features && counts.sum == @n_postings

      @postings = blob.byteslice(pos + @keys_bytes + @n_features, @n_postings * POSTING_SIZE)
      @index = {}
      offset = 0
      keys.each_with_index do |key, i|
        @index[key.freeze] = (offset << 8) | counts[i]
        offset += counts[i]
      end
      raise Error, "model index has duplicate features" unless @index.size == @n_features
    end
  end
end
