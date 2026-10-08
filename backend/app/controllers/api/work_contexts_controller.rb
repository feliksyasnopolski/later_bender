module Api
  class WorkContextsController < BaseController
    def current
      context = current_user.work_contexts.current.includes(:task).first
      render json: context_json(context)
    end

    def start
      payload = request_payload
      task = resolve_task(payload["task"])
      WorkContext.transaction do
        current_user.work_contexts.current.update_all(ended_at: Time.current, updated_at: Time.current)
        @context = current_user.work_contexts.create!(task: task, scratchpad: "")
      end
      render json: context_json(@context), status: :created
    end

    def finish
      context = current_context
      context.update!(ended_at: Time.current)
      render json: context_json(context)
    end

    def attach_task
      context = current_context
      task = resolve_task(request_payload["task"])
      context.update!(task: task)
      render json: context_json(context)
    end

    def execution_select
      context = current_user.work_contexts.current.first || current_user.work_contexts.create!(scratchpad: "")
      payload = request_payload
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
      context = current_context
      payload = request_payload
      execution = current_user.workspaces.joins(:workspace_executions).merge(WorkspaceExecution.where(ref: payload.fetch("execution"))).first!.workspace_executions.find_by!(ref: payload.fetch("execution"))
      raise ArgumentError, "execution belongs to a different selected Workspace" unless execution.workspace.ref == context.execution_workspace_ref
      context.update!(foreground_execution_ref: execution.ref)
      render json: context_json(context)
    rescue KeyError, ArgumentError => e
      render json: { error: { code: "validation_failed", message: e.message } }, status: :unprocessable_content
    end

    def scratchpad
      context = current_context
      render json: { scratchpad: context.scratchpad }
    end

    def update_scratchpad
      context = current_context
      payload = request_payload
      context.update!(scratchpad: payload.fetch("scratchpad").to_s)
      render json: { scratchpad: context.scratchpad, updated_at: context.updated_at }
    end

    private

    def current_context
      current_user.work_contexts.current.first || raise(ActiveRecord::RecordNotFound)
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
          scratchpad_updated_at: context.updated_at,
          execution: { workspace: context.execution_workspace_ref, cwd: context.execution_cwd, foreground: context.foreground_execution_ref }
        }
      }
    end
  end
end
