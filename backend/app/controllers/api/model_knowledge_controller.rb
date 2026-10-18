module Api
  class ModelKnowledgeController < BaseController
    def workflows_index
      scope = current_user.model_workflows.order(:name)
      if params[:name].present?
        name = ActiveRecord::Base.sanitize_sql_like(params[:name].to_s)
        scope = scope.where("name = :name OR name LIKE :prefix", name: params[:name], prefix: "#{name}.%")
      end
      if params[:query].present?
        terms = params[:query].to_s.downcase.scan(/[[:alnum:]]+/).uniq
        clauses = terms.map { "(name ILIKE ? OR description ILIKE ? OR workflow ILIKE ?)" }
        values = terms.flat_map { |term| [ "%#{ActiveRecord::Base.sanitize_sql_like(term)}%" ] * 3 }
        scope = clauses.any? ? scope.where([ clauses.join(" OR "), *values ]) : scope.none
      end
      render json: { workflows: scope.map { |item| workflow_json(item) } }
    end

    def workflows_save
      payload = request_payload
      name = payload["name"].to_s
      reserved = %w[memory.search tasks.manage notes.manage files.manage execution execution.interactive-terminal]
      raise ActiveRecord::RecordNotFound if name.start_with?("native.") || reserved.include?(name)
      item = current_user.model_workflows.find_or_initialize_by(name: name)
      item.versions = (item.versions + [ snapshot(item) ]).last(10) if item.persisted?
      item.assign_attributes(description: payload["description"], workflow: payload["workflow"], tools: payload["tools"] || [], evidence: "claimed")
      item.save!
      render json: workflow_json(item), status: :ok
    end

    def libraries_index
      scope = current_user.model_libraries.order(:name)
      scope = scope.where(name: params[:name]) if params[:name].present?
      render json: { libraries: scope.map { |item| library_json(item, include_source: params[:name].present?) } }
    end

    def libraries_save
      payload = request_payload
      item = current_user.model_libraries.find_or_initialize_by(name: payload["name"])
      if item.persisted?
        item.versions = (item.versions + [ { source: item.source, description: item.description, exports: item.exports } ]).last(10)
      end
      item.assign_attributes(source: payload["source"], description: payload["description"], exports: payload["exports"] || [])
      item.save!
      render json: library_json(item, include_source: true), status: :ok
    end

    private

    def snapshot(item) = { description: item.description, workflow: item.workflow, tools: item.tools, evidence: item.evidence }
    def workflow_json(item) = { name: item.name, description: item.description, workflow: item.workflow, tools: item.tools, evidence: item.evidence, versions: item.versions }
    def library_json(item, include_source:)
      { name: item.name, description: item.description, exports: item.exports, updated_at: item.updated_at, versions_available: item.versions.length }.tap do |json|
        if include_source
          json[:source] = item.source
          json[:versions] = item.versions
        end
      end
    end
  end
end
