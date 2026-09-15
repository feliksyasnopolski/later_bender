module Api
  class BaseController < ActionController::API
    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: { code: "not_found", message: "Resource not found" } }, status: :not_found
    end

    rescue_from ActiveRecord::RecordInvalid do |error|
      render_validation_errors(error.record)
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
        title: task.title,
        status: task.status,
        priority: task.priority,
        context: task.context,
        intended_direction: task.intended_direction,
        tags: task.tags.order(:name).pluck(:name),
        related_note_ids: task.notes.order(:id).pluck(:id),
        project: {
          id: task.project.id,
          name: task.project.name,
          slug: task.project.slug
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
        project: note.project && { id: note.project.id, name: note.project.name, slug: note.project.slug },
        created_at: note.created_at,
        updated_at: note.updated_at
      }
    end

    def task_scope(scope)
      scope = scope.where({ status: params[:status] }) if params[:status].present?
      scope = scope.where({ priority: params[:priority] }) if params[:priority].present?
      scope = scope.joins(:tags).where({ tags: { slug: params[:tag].to_s.parameterize } }).distinct if params[:tag].present?
      if params[:q].present?
        query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s)}%"
        scope = scope.where("tasks.title ILIKE :query OR tasks.context ILIKE :query OR tasks.intended_direction ILIKE :query", { query: query })
      end
      scope.order({ created_at: :desc })
    end
  end
end
