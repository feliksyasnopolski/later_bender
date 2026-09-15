class CreateNotesAndTaskNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :notes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project, foreign_key: true
      t.string :title, null: false
      t.text :body, null: false
      t.timestamps
    end

    create_table :note_tags do |t|
      t.references :note, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.timestamps
    end
    add_index :note_tags, %i[note_id tag_id], unique: true

    create_table :task_notes do |t|
      t.references :task, null: false, foreign_key: true
      t.references :note, null: false, foreign_key: true
      t.timestamps
    end
    add_index :task_notes, %i[task_id note_id], unique: true
  end
end
