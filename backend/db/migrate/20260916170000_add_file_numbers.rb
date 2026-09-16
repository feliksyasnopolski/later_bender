class AddFileNumbers < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :next_file_number, :bigint, null: false, default: 1
    Project.reset_column_information
    Project.find_each do |project|
      project.update_columns(next_file_number: 1)
    end
  end
end
