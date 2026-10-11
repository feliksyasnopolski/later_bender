module Api
  class WorkContextsController < BaseController
    class ContextSelectionRequired < StandardError; end

    rescue_from ContextSelectionRequired do |error|
      render json: { error: { code: "context_selection_required", message: error.message } }, status: :conflict
    end

    def current
      context = if params[:context_id].present?
        context_for_request(params[:context_id])
      else
        current_user.with_lock { current_context_or_adopt_legacy }
      end
      render json: context_json(context)
    end

    def index
      limit = Integer(params.fetch(:limit, 20))
      raise ArgumentError, "limit must be between 1 and 100" unless (1..100).cover?(limit)

      contexts = current_user.work_contexts.where(actor_key: [ nil, current_actor_key ]).recent
      contexts = contexts.where("work_contexts.id < ?", Integer(params[:before_id])) if params[:before_id].present?
      page = contexts.limit(limit + 1).to_a
      has_more = page.length > limit
      page = page.first(limit)
      render json: {
        contexts: page.map { |context| context_json(context).fetch(:context) },
        next_before_id: has_more ? page.last.id : nil
      }
    rescue ArgumentError, TypeError
      render json: { error: { code: "validation_failed", message: "limit and before_id must be valid integers; limit must be between 1 and 100" } }, status: :unprocessable_content
    end

    def show
      context = current_user.work_contexts.where(actor_key: [ nil, current_actor_key ]).includes(:task).find(params[:id])
      render json: context_json(context)
    end

    def start
      payload = request_payload
      task = resolve_task(payload["task"])
      @context = current_user.work_contexts.create!(task: task, scratchpad: "", actor_key: current_actor_key)
      render json: context_json(@context), status: :created
    end

    def select
      selected = current_user.work_contexts.find(params.fetch(:id))
      selected.with_lock do
        raise ActiveRecord::RecordNotFound unless [ nil, current_actor_key ].include?(selected.actor_key)
        selected.update!(actor_key: current_actor_key, ended_at: nil, finished_at: nil)
      end
      render json: context_json(selected.reload)
    rescue KeyError, ArgumentError, TypeError
      render json: { error: { code: "validation_failed", message: "id must be a valid work context ID" } }, status: :unprocessable_content
    end

    def finish
      context = context_for_request(request_payload["context_id"])
      now = Time.current
      context.update!(ended_at: now, finished_at: now)
      render json: context_json(context)
    end

    def attach_task
      payload = request_payload
      task = resolve_task(payload["task"])
      context = context_for_request(payload["context_id"])
      context.update!(task: task)
      render json: context_json(context)
    end

    def execution_select
      payload = request_payload
      context = context_for_request(payload["context_id"])
      workspace = current_user.workspaces.find_by_public_ref(payload.fetch("workspace"))
      raise ActiveRecord::RecordNotFound unless workspace && workspace.state == "ready"
      cwd = payload["cwd"].presence || (context.execution_workspace_ref == workspace.ref ? context.execution_cwd : nil) || workspace.workspace_root
      raise ArgumentError, "cwd must be a non-empty path" unless cwd.is_a?(String) && cwd.present?
      changed = context.execution_workspace_ref != workspace.ref
      context.update!(execution_workspace_ref: workspace.ref, execution_cwd: cwd, foreground_execution_ref: changed ? nil : context.foreground_execution_ref)
      render json: context_json(context).merge(workspace: { ref: workspace.ref, target: workspace.remote_workspace_placement&.remote_agent&.ref || "hosted", executor: workspace.remote_workspace_placement&.executor, cwd: cwd })
    rescue KeyError, ArgumentError => e
      render json: { error: { code: "validation_failed", message: e.message } }, status: :unprocessable_content
    end

    def execution_foreground
      payload = request_payload
      execution = current_user.workspaces.joins(:workspace_executions).merge(WorkspaceExecution.where(ref: payload.fetch("execution"))).first!.workspace_executions.find_by!(ref: payload.fetch("execution"))
      context = context_for_request(payload["context_id"])
      raise ArgumentError, "execution belongs to a different selected Workspace" unless execution.workspace.ref == context.execution_workspace_ref
      context.update!(foreground_execution_ref: execution.ref)
      render json: context_json(context)
    rescue KeyError, ArgumentError => e
      render json: { error: { code: "validation_failed", message: e.message } }, status: :unprocessable_content
    end

    def scratchpad
      context = context_for_request(params[:context_id])
      render json: { scratchpad: context.scratchpad }
    end

    def update_scratchpad
      payload = request_payload
      context = context_for_request(payload["context_id"])
      context.update!(scratchpad: payload.fetch("scratchpad").to_s)
      render json: { updated_at: context.updated_at, character_count: context.scratchpad.length }
    end

    private

    def actor_contexts
      current_user.work_contexts.where(actor_key: current_actor_key)
    end

    # Existing contexts predate actor isolation. The first actor to resume the
    # legacy current context claims it; subsequent actors cannot see it as current.
    # This preserves continuity across the migration without sharing new state.
    def current_context_or_adopt_legacy
      contexts = actor_contexts.current.to_a
      raise ContextSelectionRequired, "More than one active work context exists; pass context_id explicitly." if contexts.length > 1
      return contexts.first if contexts.one?

      legacy = current_user.work_contexts.where(actor_key: nil).current.to_a
      raise ContextSelectionRequired, "More than one unassigned work context exists; select one explicitly." if legacy.length > 1
      legacy.first&.update!(actor_key: current_actor_key)
      legacy.first
    end

    def context_for_request(id)
      if id.present?
        context = current_user.work_contexts.find(id)
        context.with_lock do
          raise ActiveRecord::RecordNotFound unless [ nil, current_actor_key ].include?(context.actor_key)
          context.update!(actor_key: current_actor_key) if context.actor_key.nil?
        end
        return context
      end

      current_user.with_lock do
        current_context_or_adopt_legacy || raise(ActiveRecord::RecordNotFound)
      end
    end

    def resolve_task(ref)
      return nil if ref.blank?

      shorthand, number = ref.to_s.split("-", 2)
      current_user.projects.joins(:tasks).where(shorthand: shorthand.to_s.upcase).merge(Task.where(number: number)).first!.tasks.find_by!(number: number)
    end

    def context_json(context)
      return { context: nil } unless context

      {
        context: {
          id: context.id,
          task: context.task && { ref: context.task.ref, title: context.task.title },
          current: context.current?,
          state: context.state,
          created_at: context.created_at,
          ended_at: context.ended_at,
          finished_at: context.finished_at,
          scratchpad_updated_at: context.updated_at,
          execution: { workspace: context.execution_workspace_ref, cwd: context.execution_cwd, foreground: context.foreground_execution_ref }
        }
      }
    end
  end
end
