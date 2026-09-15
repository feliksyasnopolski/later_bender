class TagReconciler
  def self.call(record, names)
    normalized_names = Array(names).filter_map { |name| name.to_s.strip.downcase.presence }.uniq
    tags = normalized_names.map do |name|
      Tag.find_or_create_by!({ name: name }) { |tag| tag.slug = name.parameterize }
    end
    record.tags = tags
  end
end
