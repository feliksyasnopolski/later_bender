module Api
  class TasksController < BaseController
    before_action :set_project, only: %i[index create]
    before_action :set_task, only: %i[show update destroy]

    def index
      scope = Task.includes(:project, :tags)
      scope = scope.where({ project: @project }) if @project
      scope = scope.joins(:project).where({ projects: { slug: params[:project] } }) if params[:project].present? && !@project
      render json: task_scope(scope).map { |task| task_json(task) }
    end

    def show
      render json: task_json(@task)
    end

    def create
      payload = request_payload
      task = @project.tasks.new(task_params(payload))
      Task.transaction do
        task.save!
        TagReconciler.call(task, payload["tags"]) if payload.key?("tags")
      end
      render json: task_json(task), status: :created
    end

    def update
      payload = request_payload
      Task.transaction do
        @task.update!(task_params(payload))
        TagReconciler.call(@task, payload["tags"]) if payload.key?("tags")
      end
      render json: task_json(@task)
    end

    def destroy
      @task.destroy!
      head :no_content
    end

    private

    def set_project
      project_slug = request.path_parameters[:project_slug]
      @project = Project.where([ "projects.slug = ?", project_slug ]).first! if project_slug
    end

    def set_task
      path = request.path_parameters
      @task = Task.find(path[:id])
      if path[:project_slug] && @task.project.slug != path[:project_slug]
        raise ActiveRecord::RecordNotFound
      end
    end

    def request_payload
      JSON.parse(request.raw_post)
    end

    def task_params(values)
      { "title" => values["title"], "status" => values["status"], "priority" => values["priority"], "context" => values["context"], "intended_direction" => values["intended_direction"] }.compact
    end
  end
end
