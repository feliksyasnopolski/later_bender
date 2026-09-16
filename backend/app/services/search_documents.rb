class SearchDocuments
  def self.all
    Task.includes(:project, :tags, :notes).to_a + Note.includes(:project, :tags).to_a + StoredFile.includes(:project, :tags, :representations).to_a
  end
end
