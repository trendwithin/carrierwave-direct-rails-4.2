class AddAvatarProcessedToUsers < ActiveRecord::Migration
  def change
    add_column :users, :avatar_processed, :boolean
  end
end
