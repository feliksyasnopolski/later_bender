class AddUsersAndScopeExistingData < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :username, null: false
      t.string :encrypted_password, null: false
      t.timestamps
    end
    add_index :users, "LOWER(username)", unique: true, name: "index_users_on_lower_username"

    add_reference :projects, :user, foreign_key: true
    add_reference :api_tokens, :user, foreign_key: true

    migrate_existing_rows
    change_column_null :projects, :user_id, false
    change_column_null :api_tokens, :user_id, false

    remove_index :projects, :slug
    add_index :projects, %i[user_id slug], unique: true
  end

  private

  def migrate_existing_rows
    return if Project.none? && ApiToken.none?

    username = ENV.fetch("INITIAL_USERNAME", "local-development")
    password = ENV.fetch("INITIAL_PASSWORD", SecureRandom.base64(24))
    user = User.find_or_create_by!(username: username) do |record|
      record.password = password
      record.password_confirmation = password
    end
    Project.where(user_id: nil).update_all(user_id: user.id)
    ApiToken.where(user_id: nil).update_all(user_id: user.id)
  end
end
