require "digest"

module CursorPagination
  class InvalidCursor < StandardError; end

  private

  def paginate_relation(scope, primary:, direction:, context:, limit:)
    direction = direction.to_s == "asc" ? :asc : :desc
    page_size = Integer(limit || 50).clamp(1, 100)
    cursor = decode_cursor(params[:cursor], context)
    if cursor
      primary_value = scope.klass.type_for_attribute(primary.to_s).cast(cursor.fetch("primary"))
      id = Integer(cursor.fetch("id"))
      comparison = direction == :asc ? ">" : "<"
      table = scope.klass.arel_table
      predicate = table[primary].public_send(direction == :asc ? :gt : :lt, primary_value)
        .or(table[primary].eq(primary_value).and(table[:id].public_send(direction == :asc ? :gt : :lt, id)))
      scope = scope.where(predicate)
    end

    records = scope.reorder(primary => direction, id: direction).limit(page_size + 1).to_a
    has_more = records.length > page_size
    records = records.first(page_size)
    next_cursor = if has_more
      last = records.last
      encode_cursor(context, "primary" => serialize_cursor_value(last.public_send(primary)), "id" => last.id)
    end
    [records, next_cursor]
  rescue ArgumentError, KeyError, TypeError
    raise InvalidCursor, "Invalid cursor"
  end

  def paginate_values(values, primary:, context:, limit:)
    page_size = Integer(limit || 50).clamp(1, 100)
    cursor = decode_cursor(params[:cursor], context)
    values = values.drop_while { |value| value.fetch(primary) <= cursor.fetch("primary") } if cursor
    page = values.first(page_size + 1)
    has_more = page.length > page_size
    page = page.first(page_size)
    next_cursor = has_more ? encode_cursor(context, "primary" => page.last.fetch(primary)) : nil
    [page, next_cursor]
  rescue ArgumentError, KeyError, TypeError
    raise InvalidCursor, "Invalid cursor"
  end

  def pagination_context(*parts)
    Digest::SHA256.hexdigest(parts.map(&:to_s).join("\0"))
  end

  def encode_cursor(context, values)
    cursor_verifier.generate({ "v" => 1, "context" => context }.merge(values), purpose: "api-pagination")
  end

  def decode_cursor(cursor, context)
    return nil if cursor.blank?
    payload = cursor_verifier.verify(cursor, purpose: "api-pagination")
    raise InvalidCursor, "Invalid cursor" unless payload.is_a?(Hash) && payload["v"] == 1 && ActiveSupport::SecurityUtils.secure_compare(payload["context"].to_s, context)
    payload
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    raise InvalidCursor, "Invalid cursor"
  end

  def cursor_verifier
    Rails.application.message_verifier("api-pagination")
  end

  def serialize_cursor_value(value)
    value.respond_to?(:iso8601) ? value.iso8601(6) : value
  end

end
