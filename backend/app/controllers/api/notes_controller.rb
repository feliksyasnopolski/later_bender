module Api
  class NotesController < BaseController
    class EditError < StandardError; end

    rescue_from EditError do |error|
      render json: { error: { code: "validation_failed", message: error.message } }, status: :unprocessable_content
    end

    before_action :set_project, only: %i[index create]
    before_action :set_note, only: %i[show update edit destroy]

    def index
      scope = current_user.notes.includes(:project, :tags)
      scope = scope.where(project: @project) if @project
      scope = scope.where(project_id: nil) if params[:projectless].to_s == "true" || params[:scope] == "global"
      scope = scope.where(project: current_user.projects.find_by!(slug: params[:project])) if params[:project].present? && !@project
      tag_values = params[:tag].to_s.split(",").reject(&:blank?)
      if tag_values.present?
        matching_note_ids = NoteTag.joins(:tag).where(tags: { slug: tag_values.map(&:parameterize) }).group(:note_id).having("COUNT(DISTINCT tags.id) = ?", tag_values.length).select(:note_id)
        scope = scope.where(id: matching_note_ids)
      end
      scope = scope.where(project_id: nil) if params[:scope] == "global"
      scope = scope.where.not(project_id: nil) if params[:scope] == "project" && params[:project].blank? && !@project
      if params[:paginated].to_s == "true"
        sort = %w[created_at updated_at].include?(params[:sort]) ? params[:sort] : "updated_at"
        order = %w[asc desc].include?(params[:order]) ? params[:order] : "desc"
        context = pagination_context("notes", current_user.id, @project&.slug || params[:project], params[:scope], normalized_tags, sort, order)
        notes, next_cursor = paginate_relation(scope, primary: sort.to_sym, direction: order, context:, limit: params[:limit])
        render json: { notes: notes.map { |note| params[:summary].to_s == "true" ? note_list_json(note) : note_json(note) }, next_cursor: }
      else
        render json: scope.order(created_at: :desc).limit(params[:limit].to_i.clamp(1, 100)).map { |note| params[:summary].to_s == "true" ? note_list_json(note) : note_json(note) }
      end
    end

    def edit
      payload = request_payload
      operations = Array(payload["operations"])
      raise_edit_error("operations must contain at least one edit") if operations.empty?

      @note.with_lock do
        expected = payload["expected_updated_at"]
        raise_edit_error("Note has changed since expected_updated_at") if expected.present? && expected != @note.updated_at.as_json
        body = @note.body.dup
        operations.each do |operation|
          case operation["operation"]
          when "append"
            raise_edit_error("append text must be a string") unless operation["text"].is_a?(String)
            body << operation["text"]
          when "replace"
            old_text = operation["old_text"]
            new_text = operation["new_text"]
            raise_edit_error("replace text must be strings and old_text must not be empty") unless old_text.is_a?(String) && old_text.present? && new_text.is_a?(String)
            matches = body.scan(Regexp.new(Regexp.escape(old_text))).length
            raise_edit_error("old_text must match exactly once; found #{matches}") unless matches == 1
            body = body.sub(old_text, new_text)
          else
            raise_edit_error("Unsupported note edit operation")
          end
        end
        @note.update!(body:)
      end
      LiveEvents.publish(user: current_user, type: "note.updated", ref: @note.id.to_s)
      render json: note_json(@note)
    end

    def show
      render json: note_json(@note)
    end

    def create
      payload = request_payload
      note = current_user.notes.new(note_params(payload))
      note.project = note_project(payload) unless @project
      note.project = @project if @project
      Note.transaction do
        note.save!
        TagReconciler.call(note, payload["tags"]) if payload.key?("tags")
        replace_citations(note, payload["citations"]) if payload.key?("citations")
      end
      LiveEvents.publish(user: current_user, type: "note.updated", ref: note.id.to_s)
      render json: note_json(note), status: :created
    end

    def update
      payload = request_payload
      Note.transaction do
        @note.assign_attributes(note_params(payload))
        @note.project = note_project(payload) if payload.key?("project")
        @note.save!
        TagReconciler.call(@note, payload["tags"]) if payload.key?("tags")
        replace_citations(@note, payload["citations"]) if payload.key?("citations")
      end
      LiveEvents.publish(user: current_user, type: "note.updated", ref: @note.id.to_s)
      render json: note_json(@note)
    end

    def destroy
      id = @note.id
      @note.destroy!
      LiveEvents.publish(user: current_user, type: "note.updated", ref: id.to_s)
      render json: { id: id }
    end

    private

    def raise_edit_error(message)
      raise EditError, message
    end

    def set_project
      slug = request.path_parameters[:project_slug]
      @project = current_user.projects.find_by!(slug: slug) if slug
    end

    def set_note
      @note = current_user.notes.find(request.path_parameters[:id])
    end

    def note_project(payload)
      return nil if payload["project"].nil?

      current_user.projects.find_by!(slug: payload["project"].to_s)
    end

    def note_params(values)
      { "title" => values["title"], "body" => values["body"] }.compact
    end
  end
end
