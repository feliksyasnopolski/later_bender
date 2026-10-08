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
          scratchpad_updated_at: context.updated_at
        }
      }
    end
  end
end
