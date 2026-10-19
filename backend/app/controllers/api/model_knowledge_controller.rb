module Api
  class ModelKnowledgeController < BaseController
    class RevisionConflict < StandardError; end
    class InvalidRevision < StandardError; end

    rescue_from RevisionConflict do |error|
      render json: { error: { code: "revision_conflict", message: error.message } }, status: :conflict
    end
    rescue_from InvalidRevision do |error|
      render json: { error: { code: "validation_failed", message: error.message, details: { expected_revision: [ "must be a non-negative integer" ] } } }, status: :unprocessable_content
    end

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
      item = save_versioned(current_user.model_workflows, name, payload) do |record|
        record.assign_attributes(description: payload["description"], workflow: payload["workflow"], tools: payload["tools"] || [], evidence: "claimed")
      end
      render json: workflow_json(item), status: :ok
    end

    def workflows_destroy
      return unless valid_name?(params[:name], ModelWorkflow)

      current_user.model_workflows.find_by!(name: params[:name]).destroy!
      head :no_content
    end

    def libraries_index
      scope = current_user.model_libraries.order(:name)
      scope = scope.where(name: params[:name]) if params[:name].present?
      render json: { libraries: scope.map { |item| library_json(item, include_source: params[:name].present?) } }
    end

    def libraries_save
      payload = request_payload
      item = save_versioned(current_user.model_libraries, payload["name"], payload) do |record|
        record.assign_attributes(source: payload["source"], description: payload["description"], exports: payload["exports"] || [])
      end
      render json: library_json(item, include_source: true), status: :ok
    end

    def libraries_destroy
      return unless valid_name?(params[:name], ModelLibrary)

      current_user.model_libraries.find_by!(name: params[:name]).destroy!
      head :no_content
    end

    private

    def save_versioned(scope, name, payload)
      item = nil
      ModelLibrary.transaction do
        item = scope.lock.find_by(name: name)
        if item
          check_revision!(item, payload)
          item.versions = (item.versions + [ snapshot(item) ]).last(10)
        else
          item = scope.build(name: name, revision: 1)
          check_revision!(item, payload)
        end
        yield item
        item.revision += 1 if item.persisted?
        item.save!
      end
      item
    rescue ActiveRecord::RecordNotUnique
      raise RevisionConflict, "The record was created concurrently; reload and retry with its revision"
    end

    def check_revision!(item, payload)
      expected = payload["expected_revision"]
      return if expected.nil?
      raise InvalidRevision, "expected_revision must be a non-negative integer" unless expected.is_a?(Integer) && expected >= 0
      return if expected == (item.persisted? ? item.revision : 0)

      raise RevisionConflict, "Revision conflict: expected #{expected}, current revision is #{item.persisted? ? item.revision : 0}"
    end

    def snapshot(item)
      attrs = item.attributes
      common = { revision: attrs["revision"] }
      common.merge(item.is_a?(ModelLibrary) ? { source: attrs["source"], description: attrs["description"], exports: attrs["exports"] } : { description: attrs["description"], workflow: attrs["workflow"], tools: attrs["tools"], evidence: attrs["evidence"] })
    end
    def valid_name?(name, model)
      name = name.to_s
      record = model.new(name: name)
      record.valid?
      errors = record.errors[:name].to_a
      errors << "is reserved" if model == ModelWorkflow && (name.start_with?("native.") || %w[memory.search tasks.manage notes.manage files.manage execution execution.interactive-terminal].include?(name))
      return true if errors.empty?

      render json: { error: { code: "validation_failed", message: "Invalid name", details: { name: errors.uniq } } }, status: :unprocessable_content
      false
    end
    def workflow_json(item) = { name: item.name, description: item.description, workflow: item.workflow, tools: item.tools, evidence: item.evidence, revision: item.revision, versions: item.versions }
    def library_json(item, include_source:)
      { name: item.name, description: item.description, exports: item.exports, revision: item.revision, updated_at: item.updated_at, versions_available: item.versions.length }.tap do |json|
        if include_source
          json[:source] = item.source
          json[:versions] = item.versions
        end
      end
    end
  end
end
