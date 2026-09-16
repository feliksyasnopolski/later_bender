module Api
  class TasksController < BaseController
    before_action :set_project, only: %i[index create]
    before_action :set_task, only: %i[show update destroy]

    def index
      scope = Task.includes(:project, :tags).joins(:project).where(projects: { user_id: current_user.id })
      scope = scope.where(projects: { id: @project.id }) if @project
      scope = scope.where({ projects: { slug: params[:project] } }) if params[:project].present? && !@project
      render json: task_scope(scope).map { |task| params[:summary].to_s == "true" ? task_list_json(task) : task_json(task) }
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
        replace_related_notes(task, payload["related_note_ids"]) if payload.key?("related_note_ids")
      end
      render json: task_json(task), status: :created
    end

    def update
      payload = request_payload
      Task.transaction do
        @task.update!(task_params(payload))
        TagReconciler.call(@task, payload["tags"]) if payload.key?("tags")
        replace_related_notes(@task, payload["related_note_ids"]) if payload.key?("related_note_ids")
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
      @project = current_user.projects.where([ "projects.slug = ?", project_slug ]).first! if project_slug
    end

    def set_task
      path = request.path_parameters
      @task = current_user.projects.joins(:tasks).merge(Task.where(id: path[:id])).first!.tasks.find(path[:id])
      if path[:project_slug] && @task.project.slug != path[:project_slug]
        raise ActiveRecord::RecordNotFound
      end
    end

    def task_params(values)
      { "title" => values["title"], "status" => values["status"], "position" => values["position"], "priority" => values["priority"], "context" => values["context"], "intended_direction" => values["intended_direction"] }.compact
    end

    def replace_related_notes(task, ids)
      ids = Array(ids).map(&:to_i).uniq
      notes = current_user.notes.where(id: ids).to_a
      raise ActiveRecord::RecordNotFound if notes.size != ids.size

      task.notes = notes
    end
  end
end
