module Api
  class ProjectsController < BaseController
    before_action :set_project, only: %i[show update]

    def index
      render json: current_user.projects.order({ created_at: :desc }).map { |project| project_json(project) }
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
      { "name" => values["name"], "slug" => values["slug"], "description" => values["description"], "archived_at" => values["archived_at"] }.compact
    end
  end
end
