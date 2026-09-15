module Api
  class SearchController < BaseController
    def index
      results = SearchService.new(
        user: current_user,
        q: params[:q],
        project: params[:project],
        kinds: params[:kinds] || params[:kind],
        tags: params[:tags] || params[:tag],
        limit: params[:limit]
      ).call
      render json: { results: results, total: results.length }
    end
  end
end
