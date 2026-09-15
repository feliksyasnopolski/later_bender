module Api
  class SearchController < BaseController
    def index
      results = SearchService.new(
        user: current_user,
        q: params[:q],
        project: params[:project],
        scope: params[:scope],
        kinds: params[:kinds] || params[:kind],
        tags: params[:tags] || params[:tag],
        statuses: params[:task_statuses] || params[:status],
        priorities: params[:task_priorities] || params[:priority],
        limit: params[:limit]
      ).call
      render json: { results: results, total: results.length }
    end
  end
end
