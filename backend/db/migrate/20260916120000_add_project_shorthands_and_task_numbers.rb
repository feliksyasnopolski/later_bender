class AddProjectShorthandsAndTaskNumbers < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :shorthand, :string
    add_column :projects, :next_task_number, :bigint, null: false, default: 1
    add_column :tasks, :number, :bigint

    backfill_project_identity
    backfill_task_numbers

    change_column_null :projects, :shorthand, false
    change_column_null :tasks, :number, false
    add_index :projects, :shorthand, unique: true
    add_index :tasks, %i[project_id number], unique: true
  end

  def down
    remove_index :tasks, column: %i[project_id number]
    remove_index :projects, column: :shorthand
    remove_column :tasks, :number
    remove_column :projects, :next_task_number
    remove_column :projects, :shorthand
  end

  private

  def backfill_project_identity
    used = execute("SELECT shorthand FROM projects WHERE shorthand IS NOT NULL").to_a.to_h { |row| [row["shorthand"], true] }
    execute("SELECT id, name, slug FROM projects ORDER BY id").each do |row|
      base = row["slug"] == "later-bender" ? "LB" : shorthand_for(row["name"])
      shorthand = base
      suffix = 2
      while used[shorthand]
        shorthand = "#{base[0, 10]}#{suffix}"
        suffix += 1
      end
      used[shorthand] = true
      execute("UPDATE projects SET shorthand = #{quote(shorthand)} WHERE id = #{row['id']}")
    end
  end

  def backfill_task_numbers
    execute("SELECT id, project_id FROM tasks ORDER BY project_id, id").group_by { |row| row["project_id"] }.each do |project_id, rows|
      rows.each { |row| execute("UPDATE tasks SET number = #{row['id']} WHERE id = #{row['id']}") }
      next_number = rows.map { |row| row["id"].to_i }.max.to_i + 1
      execute("UPDATE projects SET next_task_number = #{next_number} WHERE id = #{project_id}")
    end
  end

  def shorthand_for(name)
    words = name.to_s.upcase.scan(/[A-Z0-9]+/)
    candidate = words.map { |word| word[0] }.join
    candidate = words.first.to_s[0, 4] if candidate.length < 2
    candidate = "PROJECT" if candidate.blank?
    candidate[0, 12]
  end
end
