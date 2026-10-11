module Api
  class WorkContextsController < BaseController
    class ContextSelectionRequired < StandardError; end

    rescue_from ContextSelectionRequired do |error|
      render json: { error: { code: "context_selection_required", message: error.message } }, status: :conflict
    end

    def current
      context = current_user.with_lock do
        if params[:context_id].present?
          context_for_request(params[:context_id])
        elsif params[:conversation_key].present?
          bound_context(params[:conversation_key])
        else
          raise ContextSelectionRequired, "Conversation identity is unavailable; pass context_id explicitly."
        end
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
      conversation_key = payload["conversation_key"]
      @context = nil
      current_user.with_lock do
        @context = current_user.work_contexts.create!(task: task, scratchpad: "", actor_key: current_actor_key)
        bind_context_to_conversation!(@context, conversation_key) if conversation_key.present?
      end
      render json: context_json(@context), status: :created
    end

    def select
      payload = request_payload
      selected = nil
      current_user.with_lock do
        selected = current_user.work_contexts.find(payload.fetch("id"))
        selected.with_lock do
          raise ActiveRecord::RecordNotFound unless [ nil, current_actor_key ].include?(selected.actor_key)
          selected.update!(actor_key: current_actor_key, ended_at: nil, finished_at: nil)
        end
        bind_context_to_conversation!(selected, payload["conversation_key"]) if payload["conversation_key"].present?
      end
      render json: context_json(selected.reload)
    rescue KeyError, ArgumentError, TypeError
      render json: { error: { code: "validation_failed", message: "id must be a valid work context ID" } }, status: :unprocessable_content
    end

    def finish
      payload = request_payload
      context = nil
      now = Time.current
      with_context_for_request(payload["context_id"], conversation_key: payload["conversation_key"]) do |selected|
        selected.update!(ended_at: now, finished_at: now)
        current_user.work_context_bindings.where(actor_key: current_actor_key, work_context_id: selected.id).delete_all
        context = selected
      end
      render json: context_json(context)
    end

    def attach_task
      payload = request_payload
      task = resolve_task(payload["task"])
      context = nil
      with_context_for_request(payload["context_id"], conversation_key: payload["conversation_key"]) do |selected|
        selected.update!(task: task)
        context = selected
      end
      render json: context_json(context)
    end

    def execution_select
      payload = request_payload
      workspace = current_user.workspaces.find_by_public_ref(payload.fetch("workspace"))
      raise ActiveRecord::RecordNotFound unless workspace && workspace.state == "ready"

      selected_context = nil
      cwd = nil
      with_context_for_request(payload["context_id"], conversation_key: payload["conversation_key"]) do |context|
        cwd = payload["cwd"].presence || (context.execution_workspace_ref == workspace.ref ? context.execution_cwd : nil) || workspace.workspace_root
        raise ArgumentError, "cwd must be a non-empty path" unless cwd.is_a?(String) && cwd.present?
        changed = context.execution_workspace_ref != workspace.ref
        context.update!(execution_workspace_ref: workspace.ref, execution_cwd: cwd, foreground_execution_ref: changed ? nil : context.foreground_execution_ref)
        selected_context = context
      end
      render json: context_json(selected_context).merge(workspace: { ref: workspace.ref, target: workspace.remote_workspace_placement&.remote_agent&.ref || "hosted", executor: workspace.remote_workspace_placement&.executor, cwd: cwd })
    rescue KeyError, ArgumentError => e
      render json: { error: { code: "validation_failed", message: e.message } }, status: :unprocessable_content
    end

    def execution_foreground
      payload = request_payload
      execution = current_user.workspaces.joins(:workspace_executions).merge(WorkspaceExecution.where(ref: payload.fetch("execution"))).first!.workspace_executions.find_by!(ref: payload.fetch("execution"))
      context = nil
      with_context_for_request(payload["context_id"], conversation_key: payload["conversation_key"]) do |selected|
        raise ArgumentError, "execution belongs to a different selected Workspace" unless execution.workspace.ref == selected.execution_workspace_ref
        selected.update!(foreground_execution_ref: execution.ref)
        context = selected
      end
      render json: context_json(context)
    rescue KeyError, ArgumentError => e
      render json: { error: { code: "validation_failed", message: e.message } }, status: :unprocessable_content
    end

    def scratchpad
      scratchpad = nil
      with_context_for_request(params[:context_id], conversation_key: params[:conversation_key]) do |selected|
        scratchpad = selected.scratchpad
      end
      render json: { scratchpad: scratchpad }
    end

    def update_scratchpad
      payload = request_payload
      context = nil
      with_context_for_request(payload["context_id"], conversation_key: payload["conversation_key"]) do |selected|
        selected.update!(scratchpad: payload.fetch("scratchpad").to_s)
        context = selected
      end
      render json: { updated_at: context.updated_at, character_count: context.scratchpad.length }
    end

    private

    def with_context_for_request(id, conversation_key: nil)
      current_user.with_lock do
        context = context_for_request(id, conversation_key: conversation_key)
        yield context
      end
    end

    def context_for_request(id, conversation_key: nil)
      if id.present?
        context = current_user.work_contexts.find(id)
        context.with_lock do
          raise ActiveRecord::RecordNotFound unless [ nil, current_actor_key ].include?(context.actor_key)
          context.update!(actor_key: current_actor_key) if context.actor_key.nil?
        end
        return context
      end

      if conversation_key.present?
        return bound_context(conversation_key) || raise(ContextSelectionRequired, "No work context is selected for this ChatGPT conversation; call work_context_start or work_context_select first.")
      end

      raise ContextSelectionRequired, "Conversation identity is unavailable; pass context_id explicitly."
    end

    def bound_context(conversation_key)
      key = validate_conversation_key(conversation_key)
      binding = current_user.work_context_bindings.find_by(actor_key: current_actor_key, conversation_key: key)
      return nil unless binding

      context = binding.work_context
      unless context.current? && context.actor_key == current_actor_key
        binding.destroy!
        return nil
      end
      context
    end

    def bind_context_to_conversation!(context, conversation_key)
      key = validate_conversation_key(conversation_key)
      raise ActiveRecord::RecordNotFound unless context.user_id == current_user.id && context.actor_key == current_actor_key

      # A WorkContext can be bound to at most one conversation within an actor.
      # Selecting it elsewhere is an explicit handoff and removes its prior binding.
      current_user.work_context_bindings.where(actor_key: current_actor_key, work_context_id: context.id).delete_all
      binding = current_user.work_context_bindings.find_or_initialize_by(actor_key: current_actor_key, conversation_key: key)
      binding.work_context = context
      binding.save!
    end

    def validate_conversation_key(value)
      key = value.to_s
      raise ArgumentError, "conversation_key must be a 64-character lowercase SHA-256 hex digest" unless key.match?(/\A[0-9a-f]{64}\z/)
      key
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
