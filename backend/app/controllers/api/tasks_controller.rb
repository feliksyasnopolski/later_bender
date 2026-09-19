module Api
  class TasksController < BaseController
    before_action :set_project, only: %i[index create]
    before_action :set_task, only: %i[show update destroy]
    before_action :set_task_by_ref, only: %i[show_by_ref update_by_ref]

    def index
      scope = Task.includes(:project, :tags).joins(:project).where(projects: { user_id: current_user.id })
      scope = scope.where(projects: { id: @project.id }) if @project
      scope = scope.where({ projects: { slug: params[:project] } }) if params[:project].present? && !@project
      scope = task_scope(scope, apply_limit: params[:paginated].to_s != "true")
      if params[:paginated].to_s == "true"
        context = pagination_context("tasks", current_user.id, @project&.slug || params[:project], params[:status], params[:priority], normalized_tags, params[:q], "position", "asc")
        tasks, next_cursor = paginate_relation(scope, primary: :position, direction: :asc, context:, limit: params[:limit])
        render json: { tasks: tasks.map { |task| params[:summary].to_s == "true" ? task_list_json(task) : task_json(task) }, next_cursor: }
      else
        render json: scope.map { |task| params[:summary].to_s == "true" ? task_list_json(task) : task_json(task) }
      end
    end

    def show
      render json: task_json(@task)
    end

    def show_by_ref
      render json: task_json(@task)
    end

    def create
      payload = request_payload
      task = @project.tasks.new(task_params(payload))
      Task.transaction do
        task.save!
        TagReconciler.call(task, payload["tags"]) if payload.key?("tags")
        replace_related_notes(task, payload["related_note_ids"]) if payload.key?("related_note_ids")
        replace_related_files(task, payload["related_file_refs"]) if payload.key?("related_file_refs")
        replace_citations(task, payload["citations"]) if payload.key?("citations")
      end
      render json: task_json(task), status: :created
    end

    def update
      payload = request_payload
      Task.transaction do
        @task.update!(task_params(payload))
        TagReconciler.call(@task, payload["tags"]) if payload.key?("tags")
        replace_related_notes(@task, payload["related_note_ids"]) if payload.key?("related_note_ids")
        replace_related_files(@task, payload["related_file_refs"]) if payload.key?("related_file_refs")
        replace_citations(@task, payload["citations"]) if payload.key?("citations")
      end
      render json: task_json(@task)
    end

    def update_by_ref
      update
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

    def set_task_by_ref
      shorthand, number = request.path_parameters[:ref].to_s.split("-", 2)
      @task = current_user.projects.joins(:tasks).where(shorthand: shorthand.to_s.upcase).merge(Task.where(number: number)).first!.tasks.find_by!(number: number)
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

    def replace_related_files(task, refs)
      files = Array(refs).map do |ref|
        shorthand, number = ref.to_s.split("-F", 2)
        raise ActiveRecord::RecordNotFound unless shorthand.to_s.casecmp?(task.project.shorthand)

        task.project.stored_files.find_by!(number: number)
      end.uniq
      task.stored_files = files
    end
  end
end
