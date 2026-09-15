class RrfFuser
  K = 60

  def self.call(lexical, semantic, limit:, k: K)
    ranks = Hash.new { |hash, key| hash[key] = { score: 0.0, lexical: nil, semantic: nil } }
    lexical.each_with_index { |id, index| ranks[id].update(score: ranks[id][:score] + 1.0 / (k + index + 1), lexical: index) }
    semantic.each_with_index { |id, index| ranks[id].update(score: ranks[id][:score] + 1.0 / (k + index + 1), semantic: index) }
    ranks.sort_by { |id, data| [ -data[:score], data[:lexical] || Float::INFINITY, data[:semantic] || Float::INFINITY, id ] }.first(limit).map(&:first)
  end
end
