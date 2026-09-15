class SemanticChunker
  TARGET_TOKENS = 320
  OVERLAP_TOKENS = 50

  def self.for(record)
    new(record).chunks
  end

  def initialize(record)
    @record = record
  end

  def chunks
    units = source_text.lines.presence || [ source_text ]
    units = units.flat_map { |unit| split_oversized_unit(unit) }
    return [] if units.empty?

    chunks = []
    start = 0
    while start < units.length
      finish = start
      token_count = 0

      while finish < units.length
        unit_tokens = approximate_tokens(units[finish])
        break if finish > start && token_count + unit_tokens > TARGET_TOKENS

        token_count += unit_tokens
        finish += 1
        break if token_count >= TARGET_TOKENS
      end

      text = units[start...finish].join.strip
      text = "#{@record.title}\n\n#{text}" if start.positive? && !text.start_with?("#{@record.title}\n")
      chunks << text
      break if finish == units.length

      overlap = finish
      overlap_tokens = 0
      while overlap > start
        candidate_tokens = approximate_tokens(units[overlap - 1])
        break if overlap_tokens.positive? && overlap_tokens + candidate_tokens > OVERLAP_TOKENS

        overlap -= 1
        overlap_tokens += candidate_tokens
      end
      start = [ overlap, start + 1 ].max
    end
    chunks
  end

  private

  def source_text
    if @record.is_a?(Note)
      [ @record.title, @record.body ].compact.join("\n\n")
    else
      [ @record.title, @record.context, @record.intended_direction ].compact.join("\n\n")
    end
  end

  # This deliberately stays dependency-free. It is a stable sizing heuristic,
  # not an attempt to reproduce the embedding model's tokenizer exactly.
  def approximate_tokens(text)
    text.scan(/\w+|[^\w\s]/).length
  end

  def split_oversized_unit(unit)
    return [ unit ] if approximate_tokens(unit) <= TARGET_TOKENS

    words = unit.split
    step = TARGET_TOKENS - OVERLAP_TOKENS
    chunks = []
    start = 0
    while start < words.length
      chunks << words[start, TARGET_TOKENS].join(" ")
      break if start + TARGET_TOKENS >= words.length

      start += step
    end
    chunks
  end
end
