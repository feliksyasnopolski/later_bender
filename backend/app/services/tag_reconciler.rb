class TagReconciler
  def self.call(task, names)
    normalized_names = Array(names).filter_map { |name| name.to_s.strip.downcase.presence }.uniq
    tags = normalized_names.map do |name|
      Tag.create_or_find_by!({ name: name }) { |tag| tag.slug = name.parameterize }
    end
    task.tags = tags
  end
end
