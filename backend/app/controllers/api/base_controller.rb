module Api
  class BaseController < ActionController::API
    include CursorPagination

    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: { code: "not_found", message: "Resource not found" } }, status: :not_found
    end

    rescue_from ActiveRecord::RecordInvalid do |error|
      render_validation_errors(error.record)
    end

    rescue_from CursorPagination::InvalidCursor do |error|
      render json: { error: { code: "validation_failed", message: error.message } }, status: :unprocessable_content
    end

    before_action :authenticate_user!

    attr_reader :current_user, :current_api_token, :current_oauth_token

    private

    def authenticate_user!
      authorization = request.headers["Authorization"].to_s
      raw_token = authorization.match?(/\ABearer\s+\S+\z/) ? authorization.split.last : nil
      @current_api_token = ApiToken.authenticate(raw_token)
      @current_user = @current_api_token&.user
      if @current_user.nil? && raw_token.present?
        @current_oauth_token = Doorkeeper::AccessToken.by_token(raw_token)
        @current_user = User.find_by(id: @current_oauth_token&.resource_owner_id) if @current_oauth_token&.accessible?
      end
      render json: { error: "Authentication required" }, status: :unauthorized unless @current_user
    end

    def request_payload
      return JSON.parse(request.raw_post) if request.content_mime_type == Mime[:json]

      params.to_unsafe_h
    end

    def render_errors(record)
      render json: { error: { code: "validation_failed", message: "Validation failed", details: record.errors.to_hash } }, status: :unprocessable_entity
    end

    def render_validation_errors(record)
      render json: { error: { code: "validation_failed", message: "Validation failed", details: record.errors.to_hash.transform_values(&:to_a) } }, status: :unprocessable_content
    end

    def render_not_found
      render json: { error: "Not found" }, status: :not_found
    end

    def project_json(project)
      {
        id: project.id,
        name: project.name,
        slug: project.slug,
        shorthand: project.shorthand,
        description: project.description,
        archived_at: project.archived_at,
        task_count: project.tasks.count,
        created_at: project.created_at,
        updated_at: project.updated_at
      }
    end

    def task_json(task)
      {
        id: task.id,
        ref: task.ref,
        number: task.number,
        title: task.title,
        status: task.status,
        position: task.position,
        priority: task.priority,
        context: task.context,
        intended_direction: task.intended_direction,
        tags: task.tags.order(:name).pluck(:name),
        related_note_ids: task.notes.order(:id).pluck(:id),
        related_notes: task.notes.order(:id).map { |note| note_summary(note) },
        related_files: task.stored_files.order(:id).map { |file| file_summary(file) },
        citations: task.citations.order(:id).map { |citation| citation_json(citation) },
        project: {
          id: task.project.id,
          name: task.project.name,
          slug: task.project.slug,
          shorthand: task.project.shorthand
        },
        created_at: task.created_at,
        updated_at: task.updated_at
      }
    end

    def note_json(note)
      {
        id: note.id,
        title: note.title,
        body: note.body,
        tags: note.tags.order(:name).pluck(:name),
        project: note.project && { id: note.project.id, name: note.project.name, slug: note.project.slug, shorthand: note.project.shorthand },
        related_task_ids: note.tasks.order(:id).pluck(:id),
        related_tasks: note.tasks.order(:id).map { |task| task_summary(task) },
        related_files: note.stored_files.order(:id).map { |file| file_summary(file) },
        citations: note.citations.order(:id).map { |citation| citation_json(citation) },
        created_at: note.created_at,
        updated_at: note.updated_at
      }
    end

    def task_summary(task)
      { id: task.id, ref: task.ref, number: task.number, title: task.title, status: task.status, priority: task.priority, project: { id: task.project.id, name: task.project.name, slug: task.project.slug, shorthand: task.project.shorthand } }
    end

    def note_summary(note)
      { id: note.id, title: note.title, project: note.project && { id: note.project.id, name: note.project.name, slug: note.project.slug, shorthand: note.project.shorthand } }
    end

    def file_summary(file)
      { ref: file.ref, filename: file.filename, media_type: file.media_type }
    end

    def file_list_json(file)
      { ref: file.ref, number: file.number, filename: file.filename, media_type: file.media_type, byte_size: file.byte_size, sha256: file.sha256, tags: file.tags.order(:name).pluck(:name), project: { slug: file.project.slug, shorthand: file.project.shorthand, name: file.project.name }, created_at: file.created_at, updated_at: file.updated_at }
    end

    def file_json(file)
      provenance = file.archive_source && { archive_ref: file.archive_source.ref, entry_path: file.archive_entry_path }
      provenance = (provenance || {}).merge(origin: file.origin) if file.origin.present?
      file_list_json(file).merge(related_task_refs: file.tasks.order(:id).map(&:ref), related_note_ids: file.notes.order(:id).pluck(:id), representations: file.representations.where(status: "ready").order(:kind).map { |representation| { kind: representation.kind, media_type: representation.media_type, coordinate: representation.metadata["coordinate"] } }, provenance: provenance)
    end

    def citation_json(citation)
      { file: citation.stored_file.ref, representation: citation.representation_kind, locator: citation.locator }
    end

    def replace_citations(record, values)
      citations = Array(values).map do |value|
        value = value.to_h.stringify_keys
        shorthand, number = value.fetch("file").to_s.split("-F", 2)
        file = current_user.projects.where(shorthand: shorthand.to_s.upcase).joins(:stored_files).merge(StoredFile.where(number: number)).first!.stored_files.find_by!(number: number)
        record.citations.build(stored_file: file, representation_kind: value.fetch("representation", "auto") == "auto" ? file.searchable_representation&.kind : value.fetch("representation"), locator: value.fetch("locator"))
      end
      record.citations.destroy_all
      citations.each(&:save!)
    end

    def task_list_json(task)
      { id: task.id, ref: task.ref, number: task.number, title: task.title, status: task.status, position: task.position, priority: task.priority, tags: task.tags.order(:name).pluck(:name), related_note_ids: task.notes.order(:id).pluck(:id), project: { id: task.project.id, name: task.project.name, slug: task.project.slug, shorthand: task.project.shorthand }, created_at: task.created_at, updated_at: task.updated_at }
    end

    def note_list_json(note)
      { id: note.id, title: note.title, excerpt: note.body.to_s.tr("\n", " ").strip[0, 240], tags: note.tags.order(:name).pluck(:name), project: note.project && { id: note.project.id, name: note.project.name, slug: note.project.slug, shorthand: note.project.shorthand }, created_at: note.created_at, updated_at: note.updated_at }
    end

    def normalized_tags
      (params[:tags] || params[:tag]).to_s.split(",").reject(&:blank?).map(&:parameterize).sort
    end

    def task_scope(scope, apply_limit: true)
      scope = scope.where({ status: params[:status] }) if params[:status].present?
      scope = scope.where({ priority: params[:priority] }) if params[:priority].present?
      tag_values = (params[:tags] || params[:tag]).to_s.split(",").reject(&:blank?)
      if tag_values.present?
        matching_task_ids = TaskTag.joins(:tag).where(tags: { slug: tag_values.map(&:parameterize) }).group(:task_id).having("COUNT(DISTINCT tags.id) = ?", tag_values.length).select(:task_id)
        scope = scope.where(id: matching_task_ids)
      end
      if params[:q].present?
        query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s)}%"
        scope = scope.where("tasks.title ILIKE :query OR tasks.context ILIKE :query OR tasks.intended_direction ILIKE :query", { query: query })
      end
      scope = scope.limit(params[:limit].to_i.clamp(1, 100)) if apply_limit && params[:limit].present?
      scope.order({ position: :asc, id: :asc })
    end
  end
end
