class AddPositionToTasks < ActiveRecord::Migration[8.1]
  def up
    add_column :tasks, :position, :bigint
    execute <<~SQL
      WITH ranked AS (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY status ORDER BY created_at ASC, id ASC) * 1000 AS position
        FROM tasks
      )
      UPDATE tasks SET position = ranked.position FROM ranked WHERE tasks.id = ranked.id
    SQL
    change_column_null :tasks, :position, false
    add_index :tasks, %i[status position id]
  end

  def down
    remove_index :tasks, column: %i[status position id]
    remove_column :tasks, :position
  end
end
