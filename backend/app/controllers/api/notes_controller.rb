module Api
  class NotesController < BaseController
    before_action :set_project, only: %i[index create]
    before_action :set_note, only: %i[show update]

    def index
      scope = current_user.notes.includes(:project, :tags).order(created_at: :desc)
      scope = scope.where(project: @project) if @project
      scope = scope.where(project_id: nil) if params[:projectless].to_s == "true" || params[:scope] == "global"
      scope = scope.where(project: current_user.projects.find_by!(slug: params[:project])) if params[:project].present? && !@project
      scope = scope.joins(:tags).where(tags: { slug: params[:tag].to_s.parameterize }).distinct if params[:tag].present?
      render json: scope.map { |note| note_json(note) }
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
      end
      render json: note_json(note), status: :created
    end

    def update
      payload = request_payload
      Note.transaction do
        @note.assign_attributes(note_params(payload))
        @note.project = note_project(payload) if payload.key?("project")
        @note.save!
        TagReconciler.call(@note, payload["tags"]) if payload.key?("tags")
      end
      render json: note_json(@note)
    end

    private

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
