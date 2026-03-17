class CreateFolders < ActiveRecord::Migration[7.2]
  def change
    create_table :folders do |t|
      t.string :folder_type
      t.string :name
      t.string :parent

      t.timestamps
    end
  end
end
