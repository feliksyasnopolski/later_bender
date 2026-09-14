class CreateTotpCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :totp_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :label, null: false, default: "Authenticator"
      t.text :secret, null: false
      t.datetime :confirmed_at
      t.bigint :last_used_counter
      t.datetime :last_used_at
      t.timestamps
    end
  end
end
