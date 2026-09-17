module Api
  class FilesController < BaseController
    before_action :set_project, only: %i[index create]
    before_action :set_file_by_ref, only: %i[show update destroy read read_batch egress download archive_list archive_entry archive_extract]

    def index
      scope = @project.stored_files.includes(:project, :tags)
      tag_values = (params[:tags] || params[:tag]).to_s.split(",").reject(&:blank?)
      if tag_values.present?
        matching_ids = FileTag.joins(:tag).where(tags: { slug: tag_values.map(&:parameterize) }).group(:stored_file_id).having("COUNT(DISTINCT tags.id) = ?", tag_values.length).select(:stored_file_id)
        scope = scope.where(id: matching_ids)
      end
      if params[:paginated].to_s == "true"
        sort = { "created_at" => :created_at, "updated_at" => :updated_at, "filename" => :filename, "size" => :byte_size }.fetch(params[:sort].presence || "created_at", :created_at)
        order = %w[asc desc].include?(params[:order]) ? params[:order] : "desc"
        context = pagination_context("files", current_user.id, @project.slug, normalized_tags, sort, order)
        files, next_cursor = paginate_relation(scope, primary: sort, direction: order, context:, limit: params[:limit])
        render json: { files: files.map { |file| file_list_json(file) }, next_cursor: }
      else
        scope = scope.order(created_at: :desc)
        scope = scope.limit(params[:limit].to_i.clamp(1, 100)) if params[:limit].present?
        render json: scope.map { |file| file_list_json(file) }
      end
    end

    def create
      payload = request_payload
      file = StoredFileIngestor.call(project: @project, payload: payload.fetch("file", {}), filename: payload["filename"], tags: payload["tags"], related_task_refs: payload["related_task_refs"], related_note_ids: payload["related_note_ids"])
      render json: { ref: file.ref, updated_at: file.updated_at }, status: :created
    end

    def show
      render json: file_json(@file)
    end

    def update
      payload = request_payload
      StoredFile.transaction do
        @file.update!(filename: payload["filename"]) if payload.key?("filename")
        TagReconciler.call(@file, payload["tags"]) if payload.key?("tags")
        replace_tasks(payload["related_task_refs"]) if payload.key?("related_task_refs")
        replace_notes(payload["related_note_ids"]) if payload.key?("related_note_ids")
      end
      render json: { ref: @file.ref, updated_at: @file.reload.updated_at }
    end

    def destroy
      ref = @file.ref
      @file.destroy!
      render json: { ref: ref }
    end

    def read
      locator = params[:locator]
      locator = JSON.parse(locator) if locator.is_a?(String)
      read = FileReader.read(@file, representation: params[:representation].presence || "auto", locator: locator)
      render json: read.merge(source: { kind: "file", ref: @file.ref })
    rescue JSON::ParserError, ArgumentError
      render json: { error: { code: "validation_failed", message: "Invalid locator" } }, status: :unprocessable_content
    end

    def read_batch
      reads = Array(request_payload["reads"])
      render json: { results: reads.map { |read| { ref: read["ref"], read: FileReader.read(@file, representation: read["representation"] || "auto", locator: read["locator"]) } } }
    rescue ActiveRecord::RecordNotFound
      render json: { error: { code: "not_found", message: "Representation not found" } }, status: :not_found
    rescue ArgumentError
      render json: { error: { code: "validation_failed", message: "Invalid locator" } }, status: :unprocessable_content
    end

    def egress
      download_path = Rails.application.routes.url_helpers.rails_blob_path(
        @file.original,
        disposition: "attachment",
        expires_in: 10.minutes,
        only_path: true
      )
      render json: {
        file: {
          ref: @file.ref,
          filename: @file.filename,
          media_type: @file.media_type,
          byte_size: @file.byte_size,
          sha256: @file.sha256,
          download_path: download_path
        }
      }
    end

    def download
      send_data @file.original.download,
        filename: @file.filename,
        type: @file.media_type,
        disposition: "attachment"
    end

    def archive_list
      if params[:paginated].to_s == "true"
        values = ArchiveReader.entries(@file, path: params[:path], depth: params[:depth])
        context = pagination_context("archive", current_user.id, @file.ref, @file.sha256, params[:path], params[:depth])
        entries, next_cursor = paginate_values(values, primary: "path", context:, limit: params[:limit])
        render json: { entries:, next_cursor: }
      else
        render json: { entries: ArchiveReader.list(@file, path: params[:path], depth: params[:depth], limit: params[:limit]) }
      end
    rescue ArgumentError, ArchiveReader::Error, ArchiveReader::UnsafePath, ArchiveReader::LimitExceeded => error
      render json: { error: { code: "validation_failed", message: error.message } }, status: :unprocessable_content
    end

    def archive_entry
      locator = params[:locator]
      locator = JSON.parse(locator) if locator.is_a?(String)
      read = ArchiveReader.read_entry(@file, params[:path], representation: params[:representation].presence || "auto", locator:)
      render json: { read: read.merge(source: { kind: "archive_entry", ref: @file.ref, path: params[:path] }) }
    rescue JSON::ParserError, ArgumentError, ArchiveReader::Error, ArchiveReader::UnsafePath, ArchiveReader::LimitExceeded => error
      render json: { error: { code: "validation_failed", message: error.message } }, status: :unprocessable_content
    end

    def archive_extract
      payload = request_payload
      project = payload["project"].present? ? current_user.projects.find_by!(slug: payload["project"]) : @file.project
      file = ArchiveExtractor.call(source: @file, path: payload.fetch("path"), project:, filename: payload["filename"], tags: payload["tags"], related_task_refs: payload["related_task_refs"], related_note_ids: payload["related_note_ids"])
      render json: { ref: file.ref, updated_at: file.updated_at }, status: :created
    rescue KeyError
      render json: { error: { code: "validation_failed", message: "path is required" } }, status: :unprocessable_content
    rescue ArgumentError, ArchiveReader::Error, ArchiveReader::UnsafePath, ArchiveReader::LimitExceeded => error
      render json: { error: { code: "validation_failed", message: error.message } }, status: :unprocessable_content
    end

    private

    def set_project
      @project = current_user.projects.find_by!(slug: request.path_parameters[:project_slug])
    end

    def set_file_by_ref
      shorthand, number = request.path_parameters[:ref].to_s.split("-F", 2)
      @file = current_user.projects.joins(:stored_files).where(shorthand: shorthand.to_s.upcase).merge(StoredFile.where(number: number)).first!.stored_files.find_by!(number: number)
    end

    def replace_tasks(refs)
      @file.tasks = Array(refs).map do |ref|
        shorthand, number = ref.to_s.split("-", 2)
        raise ActiveRecord::RecordNotFound unless shorthand.to_s.casecmp?(@file.project.shorthand)
        @file.project.tasks.find_by!(number: number)
      end.uniq
    end

    def replace_notes(ids)
      ids = Array(ids).map(&:to_i).uniq
      notes = current_user.notes.where(id: ids).to_a
      raise ActiveRecord::RecordNotFound if notes.size != ids.size
      @file.notes = notes
    end
  end
end
