class SemanticChunker
  TARGET_WORDS = 650
  OVERLAP_WORDS = 100

  def self.for(record)
    new(record).chunks
  end

  def initialize(record)
    @record = record
  end

  def chunks
    paragraphs = source_text.split(/\n\s*\n|\n/).map(&:strip).reject(&:blank?)
    paragraphs = [ source_text ] if paragraphs.empty?
    words = paragraphs.flat_map(&:split)
    return [] if words.empty?

    chunks = []
    start = 0
    while start < words.length
      finish = [ start + TARGET_WORDS, words.length ].min
      chunks << words[start...finish].join(" ")
      break if finish == words.length
      start = finish - OVERLAP_WORDS
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
end
