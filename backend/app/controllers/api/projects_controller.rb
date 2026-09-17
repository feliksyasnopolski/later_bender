module Api
  class ProjectsController < BaseController
    before_action :set_project, only: %i[show update]

    def index
      scope = current_user.projects
      if params[:paginated].to_s == "true"
        context = pagination_context("projects", current_user.id, "created_at", "desc")
        projects, next_cursor = paginate_relation(scope, primary: :created_at, direction: :desc, context:, limit: params[:limit])
        render json: { projects: projects.map { |project| project_json(project) }, next_cursor: }
      else
        render json: scope.order({ created_at: :desc }).map { |project| project_json(project) }
      end
    end

    def show
      render json: project_json(@project)
    end

    def create
      project = current_user.projects.create!(project_params(request_payload))
      render json: project_json(project), status: :created
    end

    def update
      @project.update!(project_params(request_payload))
      render json: project_json(@project)
    end

    private

    def set_project
      @project = current_user.projects.find_by!({ slug: request.path_parameters[:slug] })
    end

    def project_params(values)
      { "name" => values["name"], "slug" => values["slug"], "shorthand" => values["shorthand"], "description" => values["description"], "archived_at" => values["archived_at"] }.compact
    end
  end
end
