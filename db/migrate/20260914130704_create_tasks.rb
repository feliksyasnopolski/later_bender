class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :project, null: false, foreign_key: true
      t.string :title, null: false
      t.string :status, null: false
      t.string :priority
      t.text :context
      t.text :intended_direction

      t.timestamps
    end
  end
end
