module Api
  class BaseController < ApplicationController
    private

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
        project: {
          id: task.project.id,
          name: task.project.name,
          slug: task.project.slug
        },
        created_at: task.created_at,
        updated_at: task.updated_at
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
